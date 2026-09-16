import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

final biometricServiceProvider = Provider((ref) => BiometricService(ref));

class BiometricService {
  final Ref? _ref;
  final LocalAuthentication _auth = LocalAuthentication();

  /// Timestamp of the last REAL device-credential authentication —
  /// recorded only when [LocalAuthentication.authenticate] actually
  /// prompted the user and returned true. The fail-open bypasses in
  /// [authenticate] (biometrics unavailable, secure mode off) return
  /// true WITHOUT setting this: they are usability escapes, not human
  /// attestation. Consumers that need a proven-human signal (e.g.
  /// ConsensusService's human ballot quorum) must read this clock —
  /// never the boolean return of [authenticate], which deliberately
  /// answers "may the user proceed", not "was a human verified".
  DateTime? _lastAuthenticatedAt;

  DateTime? get lastAuthenticatedAt => _lastAuthenticatedAt;

  // ─── Per-vote human attestation tokens ─────────────────────────────
  //
  // (campaign-2 hardening) The [lastAuthenticatedAt] clock binds a
  // human ballot to a RECENT authentication — temporal recency only:
  // one unlock authorizes every vote cast inside the window, for any
  // change and either choice. The strong path below binds the
  // biometric event to ONE ballot: [attestVoteIntent] prompts for a
  // genuine device-credential authentication and, only on real success,
  // mints a short-lived HMAC token committing to the exact ballot
  // fields (voterKey ‖ changeId ‖ choice ‖ issuedAt ‖ nonce).
  // ConsensusService.castVote verifies the token against the actual
  // ballot — a token minted for a different change, a different
  // choice, a different voter, or outside its TTL attests nothing.
  //
  // KEY MODEL: the HMAC key is a random 256-bit secret held in secure
  // storage ('vote_attestation_key_v1'), created lazily on first use.
  // The token is LOCAL evidence consumed at cast time by this node; it
  // is not a wire credential. When no secure-storage ref is wired
  // (headless embedder, tests) a process-lifetime ephemeral key is
  // used — tokens then die with the process, which is safe because the
  // TTL is minutes anyway.
  //
  // FAIL-CLOSED: unlike [authenticate], [attestVoteIntent] has NO
  // usability escapes. Biometrics unavailable, a thrown plugin error,
  // or a dismissed prompt all yield null — an attestation that was
  // never prompted is never minted.

  /// Secure-storage key holding the vote-attestation HMAC secret.
  static const String _attestationKeyStorageKey = 'vote_attestation_key_v1';

  /// Token format/purpose tag, domain-separated from every other MAC
  /// in the codebase.
  static const String _tokenPrefix = 'va1';

  /// How long a minted attestation stays valid. Deliberately narrow —
  /// the token is minted on the vote screen moments before the cast.
  final Duration attestationTtl;

  /// Test/headless seam: a fixed attestation key. When null the key is
  /// loaded (or lazily created) in secure storage, falling back to an
  /// ephemeral in-process key when no storage is wired.
  final Uint8List? _attestationKeyOverride;
  Uint8List? _ephemeralKey;
  Uint8List? _cachedKey;

  /// Single-use registry: HMAC hex of consumed tokens → issuance
  /// millis. A token is burned at verification time so a copied token
  /// can never attest a second ballot. Entries are pruned once their
  /// TTL has lapsed (they could never verify again anyway), keeping
  /// the set bounded.
  final Map<String, int> _consumedTokens = {};

  // Optional-positional signature: zero-arg fakes/tests and the
  // `BiometricService(ref)` provider form must both keep compiling.
  // `attestationKey` pins the HMAC key for tests/headless callers that
  // have no secure-storage reference.
  BiometricService([
    this._ref,
    this.attestationTtl = const Duration(minutes: 2),
    this._attestationKeyOverride,
  ]);

  Future<bool> isBiometricsAvailable() async {
    try {
      final canAuth = await _auth.canCheckBiometrics;
      return canAuth || await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate(
      {String reason = 'Please authenticate to access Alexandria'}) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) return true;

      if (_ref != null) {
        final storage = _ref.read(secureStorageServiceProvider);
        final secureMode = await storage.read('secure_mode_enabled');
        if (secureMode != 'true') return true;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      if (authenticated) {
        // Only a genuine prompt success attests a human — the early
        // `return true` escapes above never reach this line.
        _lastAuthenticatedAt = DateTime.now();
      }
      return authenticated;
    } on PlatformException {
      return false;
    }
  }

  /// Mint a per-vote human attestation token.
  ///
  /// Prompts for a REAL device-credential authentication (no fail-open
  /// escapes — this is evidence minting, not an app-lock gate), and on
  /// success returns an opaque token string binding that biometric
  /// event to exactly this ballot: [voterKey], [changeId], [approve].
  /// Returns null on any failure — the caller must then cast a
  /// non-human ballot or refuse, never claim `isHuman` on faith.
  Future<String?> attestVoteIntent({
    required Uint8List voterKey,
    required String changeId,
    required bool approve,
  }) async {
    try {
      if (!await isBiometricsAvailable()) return null;
      // Deliberately bypasses [authenticate]'s fail-open escapes
      // (secure-mode-off / unavailable → true): an attestation exists
      // only when a real prompt succeeded.
      final authenticated = await _auth.authenticate(
        localizedReason: 'Confirm your vote',
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) return null;
      _lastAuthenticatedAt = DateTime.now();

      final key = await _attestationKey();
      final issuedAt = DateTime.now().millisecondsSinceEpoch;
      final nonce = _randomHex(8);
      final mac = _tokenMac(key, voterKey, changeId, approve, issuedAt, nonce);
      return '$_tokenPrefix.$issuedAt.$nonce.$mac';
    } on PlatformException {
      return null;
    }
  }

  /// Verify AND consume a per-vote attestation token.
  ///
  /// Returns true only when the token carries a valid HMAC over
  /// exactly ([voterKey], [changeId], [approve]) plus a timestamp
  /// inside [attestationTtl] — and has never been consumed before.
  /// Every failure mode (malformed, forged MAC, wrong field binding,
  /// stale, future-dated, replayed, no key) returns false. The token
  /// is burned on the FIRST call regardless of outcome-neighbouring
  /// reuse: once consumed, the same string can never attest again.
  ///
  /// Wired into ConsensusService as the `voteAttestationVerifier`.
  Future<bool> consumeVoteAttestation(
    String token, {
    required Uint8List voterKey,
    required String changeId,
    required bool approve,
  }) async {
    try {
      final parts = token.split('.');
      if (parts.length != 4 || parts[0] != _tokenPrefix) return false;
      final issuedAt = int.tryParse(parts[1]);
      final nonce = parts[2];
      final presentedMac = parts[3];
      if (issuedAt == null || nonce.isEmpty || presentedMac.isEmpty) {
        return false;
      }

      // Freshness: stale tokens and future-dated tokens both refuse —
      // same anti-pre-minting rule as the attestation clock.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (issuedAt > now) return false;
      if (now - issuedAt > attestationTtl.inMilliseconds) return false;

      // Single-use: replay of an already-consumed token refuses even
      // when the fields still match.
      _pruneConsumed(now);
      if (_consumedTokens.containsKey(presentedMac)) return false;

      final key = await _attestationKey();
      final expectedMac =
          _tokenMac(key, voterKey, changeId, approve, issuedAt, nonce);
      if (!_constantTimeEquals(presentedMac, expectedMac)) return false;

      // Burn it: a token attests exactly one cast.
      _consumedTokens[presentedMac] = issuedAt;
      return true;
    } catch (_) {
      return false; // fail closed — an attestation that errors attests nothing
    }
  }

  /// HMAC-SHA256 over the domain-separated token preimage:
  /// `alexandria:vote-attestation:v1|voterKey|changeId|choice|issuedAt|nonce`.
  static String _tokenMac(Uint8List key, Uint8List voterKey, String changeId,
      bool approve, int issuedAt, String nonce) {
    final preimage = 'alexandria:vote-attestation:v1|${base64Encode(voterKey)}|'
        '$changeId|$approve|$issuedAt|$nonce';
    return Hmac(sha256, key).convert(utf8.encode(preimage)).toString();
  }

  /// The attestation HMAC secret: injected override → secure storage
  /// (lazily created) → ephemeral in-process key, in that order.
  Future<Uint8List> _attestationKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;
    final override = _attestationKeyOverride;
    if (override != null) return _cachedKey = override;
    final ref = _ref;
    if (ref != null) {
      try {
        final storage = ref.read(secureStorageServiceProvider);
        final existing = await storage.read(_attestationKeyStorageKey);
        if (existing != null && existing.isNotEmpty) {
          return _cachedKey = base64Decode(existing);
        }
        final created = _randomBytes(32);
        await storage.write(_attestationKeyStorageKey, base64Encode(created));
        return _cachedKey = created;
      } catch (_) {
        // Storage broken → fall through to the ephemeral key.
      }
    }
    return _cachedKey ??= _ephemeralKey ??= _randomBytes(32);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static String _randomHex(int n) =>
      _randomBytes(n).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Drop consumed-token records whose TTL has lapsed — they could
  /// never verify again, so retaining them only grows the set.
  void _pruneConsumed(int nowMillis) {
    _consumedTokens.removeWhere(
        (_, issuedAt) => nowMillis - issuedAt > attestationTtl.inMilliseconds);
  }

  /// Constant-time hex comparison (same XOR-fold discipline as the
  /// headless SDK bearer check): no early exit on content, length
  /// difference folded into the accumulator.
  static bool _constantTimeEquals(String a, String b) {
    final xa = utf8.encode(a);
    final xb = utf8.encode(b);
    var diff = xa.length ^ xb.length;
    final n = xa.length < xb.length ? xa.length : xb.length;
    for (var i = 0; i < n; i++) {
      diff |= xa[i] ^ xb[i];
    }
    return diff == 0;
  }

  Future<void> setSecureMode(bool enabled) async {
    if (_ref != null) {
      final storage = _ref.read(secureStorageServiceProvider);
      await storage.write('secure_mode_enabled', enabled.toString());
    }
  }
}
