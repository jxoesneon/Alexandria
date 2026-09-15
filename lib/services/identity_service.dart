import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'secure_storage_service.dart';

/// Provider for the IdentityService
final identityServiceProvider = Provider((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final service = IdentityService(secureStorage);
  ref.onDispose(service.dispose);
  return service;
});

/// Revision counter for the stored identity.
///
/// Emits a new value on EVERY successful identity mutation performed
/// through [IdentityService] (generate / import / delete / reload).
/// Any provider whose value derives from the identity should
/// `ref.watch(identityRevisionProvider)` so it rebuilds automatically
/// when the keypair is replaced — enforced by construction, so no call
/// site can forget to invalidate (which previously left stale
/// DID/pubkey reads after a recovery or rotation).
final identityRevisionProvider = StreamProvider<int>((ref) {
  final identityService = ref.watch(identityServiceProvider);
  return identityService.revisionStream;
});

/// Provider for the current identity.
///
/// Watches [identityRevisionProvider], so it re-resolves automatically
/// after every identity mutation. Explicit `ref.invalidate` calls at
/// call sites remain harmless.
final identityStateProvider = FutureProvider<AlexandriaIdentity?>((ref) async {
  ref.watch(identityRevisionProvider);
  final identityService = ref.watch(identityServiceProvider);
  return identityService.getIdentity();
});

/// Storage keys for identity data
class _IdentityKeys {
  static const privateKey = 'alexandria_identity_private_key';
  static const publicKey = 'alexandria_identity_public_key';
  static const identityCreated = 'alexandria_identity_created';

  /// JSON list of every public key (canonical lowercase hex) this node
  /// has EVER installed — current plus retired rotation predecessors.
  /// Append-only (Safety item 3): a receipt verifier-signed by a
  /// retired key is still self-issued, so the history is never pruned,
  /// not even by deleteIdentity.
  static const publicKeyHistory = 'alexandria_identity_pubkey_history';
}

/// Represents a cryptographic identity with Ed25519 keypair
class AlexandriaIdentity {
  final Uint8List publicKey;
  final Uint8List privateKey;
  final DateTime createdAt;

  AlexandriaIdentity({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
  });

  /// Get the Base58-encoded public key (for display)
  String get publicKeyBase58 => _base58Encode(publicKey);

  /// Get the short identity (first 8 chars of Base58)
  String get shortId => publicKeyBase58.substring(0, 8);

  /// Convert to JSON for debugging (never export private key in production)
  Map<String, dynamic> toJson() => {
        'publicKey': publicKeyBase58,
        'shortId': shortId,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Base58 encoding implementation
  static String _base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var result = '';
    var value = BigInt.zero;

    for (var byte in bytes) {
      value = (value << 8) + BigInt.from(byte);
    }

    while (value > BigInt.zero) {
      final remainder = (value % BigInt.from(58)).toInt();
      result = alphabet[remainder] + result;
      value = value ~/ BigInt.from(58);
    }

    // Add leading '1's for leading zero bytes
    for (var byte in bytes) {
      if (byte == 0) {
        result = '1$result';
      } else {
        break;
      }
    }

    return result;
  }

  /// Decodes a Base58-encoded public key (inverse of [_base58Encode]).
  /// Throws [FormatException] on invalid characters.
  static Uint8List decodePublicKeyBase58(String encoded) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var value = BigInt.zero;
    for (final ch in encoded.codeUnits) {
      final idx = alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) {
        throw const FormatException('Invalid Base58 character');
      }
      value = value * BigInt.from(58) + BigInt.from(idx);
    }
    final bytes = <int>[];
    while (value > BigInt.zero) {
      bytes.insert(0, (value % BigInt.from(256)).toInt());
      value = value ~/ BigInt.from(256);
    }
    var zeroes = 0;
    while (zeroes < encoded.length && encoded[zeroes] == '1') {
      zeroes++;
    }
    return Uint8List.fromList(List.filled(zeroes, 0) + bytes);
  }
}

/// Represents a signed identity proof
class IdentityProof {
  final String message;
  final Uint8List signature;
  final Uint8List publicKey;
  final DateTime timestamp;

  IdentityProof({
    required this.message,
    required this.signature,
    required this.publicKey,
    required this.timestamp,
  });

  /// Get Base64-encoded signature
  String get signatureBase64 => base64Encode(signature);

  Map<String, dynamic> toJson() => {
        'message': message,
        'signature': signatureBase64,
        'publicKey': AlexandriaIdentity._base58Encode(publicKey),
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Service for managing cryptographic identity
class IdentityService {
  final SecureStorageService _storage;
  final _algorithm = Ed25519();

  IdentityService(this._storage);

  AlexandriaIdentity? _cachedIdentity;

  // ─────────────────────────────────────────────────────────────────
  // Mutation serialization + revision tracking
  // ─────────────────────────────────────────────────────────────────

  /// Chained future serializing EVERY storage-touching identity
  /// operation (reads included). A cold [getIdentity] therefore can
  /// never interleave with a multi-key write in [generateIdentity] /
  /// [importIdentity] and observe a half-written "Franken" keypair.
  Future<void> _opChain = Future<void>.value();

  /// Serializes [op] behind all previously scheduled identity
  /// operations. The chain itself never fails: an op's error is
  /// delivered to ITS caller while later ops still run.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _opChain.then<T>((_) => op());
    _opChain = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  int _revision = 0;
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast(sync: true);

  /// Monotonic counter bumped after every successful identity
  /// mutation. Exposed through [identityRevisionProvider].
  int get revision => _revision;

  /// Broadcast stream of [revision] values. Emits synchronously during
  /// each mutation so dependents are invalidated before the mutating
  /// call returns.
  Stream<int> get revisionStream => _revisionController.stream;

  void _bumpRevision() {
    _revision++;
    if (!_revisionController.isClosed) {
      _revisionController.add(_revision);
    }
  }

  /// Release resources held by this service.
  Future<void> dispose() => _revisionController.close();

  /// Check if an identity exists.
  ///
  /// Requires ALL identity keys to be present — checking the private
  /// key alone reported true on a partially-written store while
  /// [getIdentity] returned null (its read needs the public key and
  /// the creation stamp too), so UI would skip the "replace existing
  /// identity" warning for an identity it could not even serve.
  Future<bool> hasIdentity() {
    return _serialized(() async {
      final privateKeyHex = await _storage.read(_IdentityKeys.privateKey);
      final publicKeyHex = await _storage.read(_IdentityKeys.publicKey);
      final createdStr = await _storage.read(_IdentityKeys.identityCreated);
      return privateKeyHex != null &&
          publicKeyHex != null &&
          createdStr != null;
    });
  }

  /// Get the current identity (cached for performance)
  Future<AlexandriaIdentity?> getIdentity() {
    final cached = _cachedIdentity;
    if (cached != null) return Future<AlexandriaIdentity?>.value(cached);
    return _serialized(_readIdentityUnlocked);
  }

  /// Every public key this node has EVER held, as a canonical lowercase
  /// hex set — the current identity plus all retired rotation
  /// predecessors (Safety item 3). CreditService's self-dealing guard
  /// consumes this so a receipt verifier-signed by a rotated-away key
  /// is still recognized as self-issued and can never mint attested
  /// value post-rotation.
  ///
  /// The set NEVER shrinks: [deleteIdentity] removes the keypair but
  /// not its history — a deleted key still signed receipts while held,
  /// so they remain self-vouched forever. The currently stored key is
  /// always included even when its history append failed or the install
  /// predates the feature; a corrupt history blob degrades to that
  /// current-key floor rather than failing.
  Future<Set<String>> knownLocalPubkeyHexes() {
    return _serialized(() async {
      final out = (await _readPubkeyHistoryUnlocked()).toSet();
      final current = await _storage.read(_IdentityKeys.publicKey);
      if (current != null) {
        final canonical = current.trim().toLowerCase();
        if (canonical.isNotEmpty) out.add(canonical);
      }
      return out;
    });
  }

  /// Reads the append-only local-key history. Must only be called
  /// inside [_serialized]. A missing or corrupt blob resolves to an
  /// empty list — the caller's current-key floor covers the gap.
  Future<List<String>> _readPubkeyHistoryUnlocked() async {
    try {
      final raw = await _storage.read(_IdentityKeys.publicKeyHistory);
      if (raw == null) return <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      final out = <String>[];
      for (final e in decoded) {
        if (e is String) {
          final canonical = e.trim().toLowerCase();
          if (canonical.isNotEmpty && !out.contains(canonical)) {
            out.add(canonical);
          }
        }
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  /// Appends [publicKeyHex] to the append-only local-key history.
  /// Must only be called inside [_serialized]. Best-effort: a failing
  /// store skips the append rather than breaking the identity mutation
  /// that triggered it — [knownLocalPubkeyHexes] always re-derives the
  /// current-key floor, so the degradation is bounded to the missed
  /// retired key.
  Future<void> _recordPubkeyInHistoryUnlocked(String publicKeyHex) async {
    final canonical = publicKeyHex.trim().toLowerCase();
    if (canonical.isEmpty) return;
    try {
      final history = await _readPubkeyHistoryUnlocked();
      if (history.contains(canonical)) return;
      history.add(canonical);
      await _storage.write(
          _IdentityKeys.publicKeyHistory, jsonEncode(history));
    } catch (_) {}
  }

  /// Read the stored identity. Must only be called inside [_serialized].
  ///
  /// Read-time verification heals legacy "Franken" pairs persisted by
  /// pre-fix partial writes (or any other out-of-band corruption): the
  /// stored private key is AUTHORITATIVE — it derives everything — so
  /// when `derivePublic(storedPriv) != storedPub` the stored public key
  /// is rewritten to the derived value and the healed pair is served.
  /// Serving the pair unverified would make [sign] emit signatures
  /// that fail against the reported public key. Material that cannot
  /// be healed (undecodable hex, a non-seed private key, a failing
  /// heal write) is treated as "no usable identity": the cache is
  /// dropped and null returned.
  Future<AlexandriaIdentity?> _readIdentityUnlocked() async {
    final cached = _cachedIdentity;
    if (cached != null) return cached;

    final privateKeyHex = await _storage.read(_IdentityKeys.privateKey);
    final publicKeyHex = await _storage.read(_IdentityKeys.publicKey);
    final createdStr = await _storage.read(_IdentityKeys.identityCreated);

    if (privateKeyHex == null || publicKeyHex == null || createdStr == null) {
      return null;
    }

    final createdAt = DateTime.tryParse(createdStr);
    if (createdAt == null) return null;

    try {
      final privateKey = _hexDecode(privateKeyHex);
      var publicKey = _hexDecode(publicKeyHex);

      // Verify the stored pair: the private key must derive the stored
      // public key. On mismatch, heal storage with the derived value.
      final keyPair = await _algorithm.newKeyPairFromSeed(privateKey);
      final derivedPublicKey =
          Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
      final derivedPublicKeyHex = _hexEncode(derivedPublicKey);
      if (derivedPublicKeyHex != publicKeyHex.toLowerCase()) {
        await _storage.write(_IdentityKeys.publicKey, derivedPublicKeyHex);
        publicKey = derivedPublicKey;
        // The public key the app now reports changed — bump the
        // revision so identity-derived providers rebuild. Converges:
        // the next read verifies the healed pair and does not bump.
        _bumpRevision();
      }

      // Record the served key in the append-only history (Safety item
      // 3): this covers installs that predate the feature AND the heal
      // path above, where the stored pubkey just changed to the derived
      // value. Best-effort — a history write failure must not break
      // the read.
      await _recordPubkeyInHistoryUnlocked(_hexEncode(publicKey));

      _cachedIdentity = AlexandriaIdentity(
        privateKey: privateKey,
        publicKey: publicKey,
        createdAt: createdAt,
      );

      return _cachedIdentity;
    } catch (_) {
      // Unhealable corruption — never cache or serve a suspect pair.
      _cachedIdentity = null;
      return null;
    }
  }

  /// Generate a new Ed25519 keypair and store securely
  Future<AlexandriaIdentity> generateIdentity() {
    return _serialized(() async {
      final keyPair = await _algorithm.newKeyPair();
      final privateKeyBytes = Uint8List.fromList(
        await keyPair.extractPrivateKeyBytes(),
      ); // 32 bytes seed
      final publicKeyObj = await keyPair.extractPublicKey();
      final publicKeyBytes = Uint8List.fromList(publicKeyObj.bytes);

      // A genuinely NEW identity stamps a fresh creation time.
      return _persistIdentityUnlocked(
        seed: privateKeyBytes,
        publicKey: publicKeyBytes,
        createdAt: DateTime.now(),
      );
    });
  }

  /// Import an identity from a raw Ed25519 private-key seed.
  ///
  /// Writes through [_storage] — the same store [getIdentity] reads —
  /// and refreshes [_cachedIdentity] atomically. This is the ONLY
  /// supported way to replace the stored identity out-of-band (it is
  /// what `MnemonicService.recoverFromMnemonic` uses): writing the
  /// identity keys from anywhere else lets the cached and stored
  /// identities diverge, so [getIdentity] would keep serving the OLD
  /// keypair while storage holds the new one (split-brain).
  ///
  /// The seed is defensively copied so a caller mutating its buffer
  /// afterwards cannot corrupt the stored identity. When the imported
  /// seed derives to the SAME public key already stored (i.e. a
  /// recovery of the current identity), the existing `createdAt` is
  /// preserved — stamping `now` would reset governance account-age
  /// checks (`minAccountAgeDays`) on every recovery.
  Future<AlexandriaIdentity> importIdentity(Uint8List privateKeySeed) {
    final seed = Uint8List.fromList(privateKeySeed);
    return _serialized(() async {
      final keyPair = await _algorithm.newKeyPairFromSeed(seed);
      final publicKeyObj = await keyPair.extractPublicKey();
      final publicKeyBytes = Uint8List.fromList(publicKeyObj.bytes);
      final publicKeyHex = _hexEncode(publicKeyBytes);

      final existingPublicKeyHex =
          await _storage.read(_IdentityKeys.publicKey);
      final existingCreatedStr =
          await _storage.read(_IdentityKeys.identityCreated);
      final createdAt =
          (existingPublicKeyHex == publicKeyHex && existingCreatedStr != null)
              ? (DateTime.tryParse(existingCreatedStr) ?? DateTime.now())
              : DateTime.now();

      return _persistIdentityUnlocked(
        seed: seed,
        publicKey: publicKeyBytes,
        createdAt: createdAt,
      );
    });
  }

  /// Atomically write + verify an identity. Must only be called inside
  /// [_serialized].
  ///
  /// Write ordering is defensive: the private key is written LAST so
  /// its presence implies the full write was attempted. After writing,
  /// the keys are re-read and `derivePublic(storedPriv) == storedPub`
  /// is verified BEFORE the in-memory cache is touched. On mismatch the
  /// whole write is retried once; if it still mismatches, the previous
  /// (consistent) key material is restored — or the keys are cleared
  /// when there was none — and a [StateError] is thrown. A mixed
  /// private/public pair therefore can never persist or be cached.
  ///
  /// When the stored public key CHANGES, the mnemonic-backup marker is
  /// cleared: an old recovery phrase no longer restores the current
  /// identity, so the UI must warn again until a fresh backup is
  /// confirmed. Re-importing the SAME key keeps the marker (the old
  /// phrase still recovers it).
  Future<AlexandriaIdentity> _persistIdentityUnlocked({
    required Uint8List seed,
    required Uint8List publicKey,
    required DateTime createdAt,
  }) async {
    final seedHex = _hexEncode(seed);
    final publicKeyHex = _hexEncode(publicKey);
    final createdStr = createdAt.toIso8601String();

    // Snapshot the prior state so a failed import can restore it
    // instead of leaving a partially-overwritten keypair.
    final prevPrivHex = await _storage.read(_IdentityKeys.privateKey);
    final prevPubHex = await _storage.read(_IdentityKeys.publicKey);
    final prevCreated = await _storage.read(_IdentityKeys.identityCreated);

    // Record the OUTGOING key in the append-only history BEFORE it is
    // replaced (Safety item 3, REV4a F3): serve-time appends in
    // [_readIdentityUnlocked] only cover keys that were READ while
    // installed — a key installed pre-feature (or by any out-of-band
    // write) and rotated away before its first read would otherwise
    // escape the history entirely, and receipts verifier-signed by it
    // would mint attested value as if foreign. Best-effort:
    // [_recordPubkeyInHistoryUnlocked] swallows its own failures, so a
    // faulting store can never block the identity write. Recording the
    // outgoing key is still correct when the write below later rolls
    // back — the restored previous key genuinely was (and remains)
    // installed, so it belongs in the history either way.
    if (prevPubHex != null) {
      await _recordPubkeyInHistoryUnlocked(prevPubHex);
    }

    // When the keypair is changing, clear the mnemonic-backup marker
    // UP-FRONT and best-effort: a stale marker that survives would
    // falsely claim the NEW identity is backed up by the OLD phrase,
    // while a spuriously-cleared marker only re-prompts a backup. An
    // awaited delete inside the success path below could throw AFTER
    // the verified write and strand the cache — deleting here means
    // the marker is gone before storage can diverge.
    if (prevPubHex != publicKeyHex) {
      try {
        await _storage.delete(SecureStorageKeys.mnemonicBackup);
      } catch (_) {}
    }

    Object? lastWriteError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _storage.write(_IdentityKeys.publicKey, publicKeyHex);
        await _storage.write(_IdentityKeys.identityCreated, createdStr);
        await _storage.write(_IdentityKeys.privateKey, seedHex);
      } catch (e) {
        // A throwing write can still leave a partial pair behind —
        // verification below decides what was actually persisted.
        lastWriteError = e;
      }

      if (await _verifyStoredIdentity(seedHex, publicKeyHex)) {
        _cachedIdentity = AlexandriaIdentity(
          privateKey: Uint8List.fromList(seed),
          publicKey: Uint8List.fromList(publicKey),
          createdAt: createdAt,
        );
        // Append the now-verified key to the never-shrinking history
        // (Safety item 3) — a receipt signed by this key stays
        // self-issued even after a later rotation retires it. Only a
        // SUCCESSFUL install is recorded: the rollback path below never
        // installed the new key, so it must not enter the history.
        await _recordPubkeyInHistoryUnlocked(publicKeyHex);
        _bumpRevision();
        return _cachedIdentity!;
      }
    }

    // Persistent verification failure: restore the prior consistent
    // state if there was one, otherwise remove the partial writes. In
    // both cases no mixed private/public pair may survive — and the
    // rollback writes THEMSELVES may throw (the keychain is already
    // faulting), so the cache drop and revision bump live in a
    // `finally`: a stale in-memory identity must never outlive storage
    // whose contents are now uncertain.
    try {
      if (prevPrivHex != null && prevPubHex != null && prevCreated != null) {
        await _storage.write(_IdentityKeys.publicKey, prevPubHex);
        await _storage.write(_IdentityKeys.identityCreated, prevCreated);
        await _storage.write(_IdentityKeys.privateKey, prevPrivHex);
        if (!await _verifyStoredIdentity(prevPrivHex, prevPubHex)) {
          await _deleteIdentityKeysUnlocked();
        }
      } else {
        await _deleteIdentityKeysUnlocked();
      }
    } catch (_) {
      // The rollback failed too — storage is in an unknown state. The
      // StateError below still reports the original write failure;
      // the read path self-heals or rejects whatever survived.
    } finally {
      // Drop the cache: it may no longer match whatever is stored now.
      _cachedIdentity = null;
      _bumpRevision();
    }
    throw StateError(
      'Identity write failed post-write verification '
      '(last storage error: $lastWriteError); '
      'the previous identity was restored or partial keys cleared.',
    );
  }

  /// Re-read storage and confirm the stored private key derives the
  /// stored public key. Must only be called inside [_serialized].
  Future<bool> _verifyStoredIdentity(
    String expectedPrivateKeyHex,
    String expectedPublicKeyHex,
  ) async {
    try {
      final privateKeyHex = await _storage.read(_IdentityKeys.privateKey);
      final publicKeyHex = await _storage.read(_IdentityKeys.publicKey);
      final createdStr = await _storage.read(_IdentityKeys.identityCreated);
      if (privateKeyHex != expectedPrivateKeyHex ||
          publicKeyHex != expectedPublicKeyHex ||
          createdStr == null) {
        return false;
      }
      final keyPair =
          await _algorithm.newKeyPairFromSeed(_hexDecode(privateKeyHex!));
      final derived = await keyPair.extractPublicKey();
      return _hexEncode(Uint8List.fromList(derived.bytes)) ==
          expectedPublicKeyHex;
    } catch (_) {
      return false;
    }
  }

  /// Remove all identity keys. Must only be called inside [_serialized].
  ///
  /// Records the outgoing public key in the append-only history BEFORE
  /// deleting it (Safety item 3, REV4a F3): a key deleted before it was
  /// ever read escapes the serve-time append in [_readIdentityUnlocked],
  /// and without this record its verifier-signed receipts would mint
  /// attested value after a fresh install. Best-effort — a history
  /// failure must never abort the delete.
  Future<void> _deleteIdentityKeysUnlocked() async {
    try {
      final currentPubHex = await _storage.read(_IdentityKeys.publicKey);
      if (currentPubHex != null) {
        await _recordPubkeyInHistoryUnlocked(currentPubHex);
      }
    } catch (_) {}
    await _storage.delete(_IdentityKeys.privateKey);
    await _storage.delete(_IdentityKeys.publicKey);
    await _storage.delete(_IdentityKeys.identityCreated);
    await _storage.delete(SecureStorageKeys.mnemonicBackup);
  }

  /// Clear the in-memory identity cache and reload it from secure
  /// storage.
  ///
  /// Must be called whenever the stored identity keys may have been
  /// replaced out-of-band so [getIdentity] stops serving a stale cached
  /// keypair. (Recoveries via [importIdentity] already refresh the
  /// cache; this is wired to `MnemonicService.onIdentityRecovered` as
  /// belt-and-suspenders cache coherency.)
  Future<void> reloadIdentity() {
    return _serialized(() async {
      _cachedIdentity = null;
      await _readIdentityUnlocked();
      _bumpRevision();
    });
  }

  /// Record that the recovery phrase for the CURRENT identity has been
  /// backed up, writing [SecureStorageKeys.mnemonicBackup] inside the
  /// same [_serialized] chain as every identity mutation.
  ///
  /// Ownership of this marker lives here — not in `MnemonicService` —
  /// because only the serialized chain can order the write against a
  /// concurrent [importIdentity]/[generateIdentity]: an unserialized
  /// write could land AFTER the replacement's marker-clear and
  /// resurrect a stale "backed up" flag for a phrase that recovers the
  /// OLD key.
  ///
  /// When [expectedPublicKeyHex] is provided (the public key the
  /// phrase actually recovers, derived by the caller), the marker is
  /// written only while that key is still the stored one — making the
  /// outcome independent of which serialized op runs first. Callers
  /// that cannot decode the phrase may omit it; ordering with the
  /// clearing writes still applies.
  Future<void> markMnemonicBackupConfirmed(
    String phraseHash, {
    String? expectedPublicKeyHex,
  }) {
    return _serialized(() async {
      if (expectedPublicKeyHex != null) {
        final currentPublicKeyHex =
            await _storage.read(_IdentityKeys.publicKey);
        if (currentPublicKeyHex != expectedPublicKeyHex) {
          // The phrase confirms a backup of a keypair that is no
          // longer stored — writing the marker would claim the NEW
          // identity is backed up by a phrase that cannot recover it.
          return;
        }
      }
      await _storage.write(SecureStorageKeys.mnemonicBackup, phraseHash);
    });
  }

  /// Create an identity proof (signed message with timestamp)
  Future<IdentityProof> createIdentityProof() async {
    final identity = await getIdentity();
    if (identity == null) {
      throw StateError('No identity exists. Generate one first.');
    }

    final timestamp = DateTime.now();
    final message = 'Alexandria Identity Proof: ${timestamp.toIso8601String()}';
    final messageBytes = utf8.encode(message);

    // Reconstruct keypair from stored bytes
    final keyPair = await _algorithm.newKeyPairFromSeed(identity.privateKey);

    // Sign the message
    final signature = await _algorithm.sign(messageBytes, keyPair: keyPair);

    return IdentityProof(
      message: message,
      signature: Uint8List.fromList(signature.bytes),
      publicKey: identity.publicKey,
      timestamp: timestamp,
    );
  }

  /// Verify an identity proof
  Future<bool> verifyIdentityProof(IdentityProof proof) async {
    try {
      final messageBytes = utf8.encode(proof.message);
      final publicKey = SimplePublicKey(
        proof.publicKey,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(proof.signature, publicKey: publicKey);

      return await _algorithm.verify(messageBytes, signature: signature);
    } catch (e) {
      return false;
    }
  }

  /// Sign arbitrary data with the identity's private key
  Future<Uint8List> sign(Uint8List data) async {
    final identity = await getIdentity();
    if (identity == null) {
      throw StateError('No identity exists. Generate one first.');
    }

    final keyPair = await _algorithm.newKeyPairFromSeed(identity.privateKey);
    final signature = await _algorithm.sign(data, keyPair: keyPair);

    return Uint8List.fromList(signature.bytes);
  }

  /// Verify a signature against a public key
  Future<bool> verifySignature(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey,
  ) async {
    try {
      final pubKey = SimplePublicKey(publicKey, type: KeyPairType.ed25519);

      final sig = Signature(signature, publicKey: pubKey);
      return await _algorithm.verify(data, signature: sig);
    } catch (e) {
      return false;
    }
  }

  /// Delete the current identity (dangerous - cannot be recovered without backup)
  Future<void> deleteIdentity() {
    return _serialized(() async {
      try {
        await _deleteIdentityKeysUnlocked();
      } finally {
        // The cache drop and revision bump are unconditional: a
        // throwing mid-sequence delete may leave partial keys behind,
        // but a cached identity must never outlive them.
        _cachedIdentity = null;
        _bumpRevision();
      }
    });
  }

  /// Compute SHA-256 hash of data
  Uint8List sha256(Uint8List data) {
    final digest = crypto.sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper methods
  // ─────────────────────────────────────────────────────────────────────────

  String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
