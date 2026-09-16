// RED TEAM PoC - Round-3: the new ECIES path in
// EncryptionService.encryptForPeer / decryptFromPeer performs X25519
// WITHOUT a non-contributory (low-order point / all-zero shared
// secret) check. package:cryptography's X25519 returns the all-zero
// 32-byte shared secret for low-order public inputs (verified: u=0,
// u=1, and u=p-1 all yield 0x00*32) instead of aborting the way
// libsodium's crypto_scalarmult does.
//
// CONSEQUENCE 1 (confidentiality collapse): a hostile peer can publish
// an "identity public key" whose Ed25519 encoding maps to a low-order
// Montgomery point. EncryptionService.ed25519PublicToX25519 maps the
// canonical low-order encodings onto u=0/u=1/… - e.g. the Ed25519
// compressed point y = -1 (bytes EC FF…FF 7F) converts to u = 0.
// encryptForPeer then derives the AEAD key from a PUBLIC CONSTANT
// (all-zero secret) and public salts (ephPub ‖ u). ANY observer can
// recompute the key and read the plaintext - the sender believes the
// data is sealed to that peer; it is sealed to no one.
//
// CONSEQUENCE 2 (recipient-side acceptance): decryptFromPeer likewise
// accepts an envelope whose ephemeral key is a low-order point - the
// shared secret is again the all-zero constant, so an attacker can
// forge a decryptable envelope to any victim whose public key is
// known (it always is), injecting attacker-chosen plaintext into the
// "confidential" peer channel.
//
// CONSEQUENCE 3 (documented-API self-inconsistency): the service
// treats every 32-byte input as an ED25519 key and re-runs the
// Edwards→Montgomery map. IdentityService.x25519PublicKeyBytes()
// documents its return value as "the value a sender needs inside
// EncryptionService.encryptForPeer" - but passing that u-coordinate
// gets it re-mapped, producing a ciphertext the real recipient key
// can never open (silent data loss reported as success).
//
// Asserts the SECURE expectations:
//   * encryptForPeer must reject (or at minimum fail to produce a
//     universally-decryptable envelope for) low-order peer keys;
//   * decryptFromPeer must reject envelopes whose ephemeral key is
//     non-contributory (all-zero shared secret);
//   * a ciphertext produced for the peer's documented X25519 public
//     key must be openable by that peer's private key.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

/// Replicates the public (non-secret) portion of the key schedule:
/// AEAD key = HKDF-SHA256(secret=shared, salt=ephPub‖peerU,
/// info='alexandria:peer-e2e:v1'). Everything except `shared` is on
/// the wire or published.
Future<SecretKey> _attackerAeadKey({
  required SecretKey shared,
  required Uint8List ephemeralPub,
  required Uint8List peerU,
}) {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final salt = BytesBuilder()
    ..add(ephemeralPub)
    ..add(peerU);
  return hkdf.deriveKey(
    secretKey: shared,
    nonce: salt.toBytes(),
    info: utf8.encode('alexandria:peer-e2e:v1'),
  );
}

void main() {
  final enc = EncryptionService();
  final aes = AesGcm.with256bits();
  final x = X25519();

  // The Ed25519 compressed encoding of y = -1 (mod p): converts to
  // Montgomery u = 0 - a low-order point with no private key.
  final lowOrderEd = Uint8List.fromList([0xec, ...List.filled(30, 0xff), 0x7f]);
  final lowOrderU = EncryptionService.ed25519PublicToX25519(lowOrderEd);
  assert(lowOrderU.every((b) => b == 0), 'expected u=0 mapping');

  test(
      'envelope for a low-order peer key must NOT be decryptable by '
      'an eavesdropper who knows only public values', () async {
    final secret =
        Uint8List.fromList(utf8.encode('sealed-bid: pay 42 credits'));

    // Attacker "identity" - a syntactically valid 32-byte public key
    // string (hex spelling of the low-order point).
    final envelope = await enc.encryptForPeer(secret, _hex(lowOrderEd));

    // Eavesdropper path - zero private knowledge required:
    //   shared = X25519(anything, u=0) = 0*32  (public constant)
    //   salt   = ephPub (from envelope) ‖ u=0 (from the public key)
    final eavesKp = await x.newKeyPair();
    final shared = await x.sharedSecretKey(
      keyPair: eavesKp,
      remotePublicKey: SimplePublicKey(lowOrderU, type: KeyPairType.x25519),
    );
    final sharedBytes = await shared.extractBytes();
    expect(sharedBytes.every((b) => b == 0), isTrue,
        reason: 'cryptography/X25519 returned a non-zero secret for u=0 '
            '— the premise no longer holds, re-verify the finding');

    final ephPub = Uint8List.fromList(envelope.sublist(1, 33));
    final aeadKey = await _attackerAeadKey(
        shared: shared, ephemeralPub: ephPub, peerU: lowOrderU);
    final box = SecretBox.fromConcatenation(
      envelope.sublist(33),
      nonceLength: aes.nonceLength,
      macLength: aes.macAlgorithm.macLength,
    );
    Uint8List? recovered;
    try {
      recovered =
          Uint8List.fromList(await aes.decrypt(box, secretKey: aeadKey));
    } catch (_) {
      recovered = null;
    }

    expect(recovered, isNot(equals(secret)),
        reason: 'an eavesdropper decrypted a "peer-encrypted" envelope using '
            'ONLY public values: the recipient key is a low-order point, '
            'so the X25519 shared secret is the all-zero constant and the '
            'HKDF salt is entirely on the wire. encryptForPeer must reject '
            'non-contributory peer keys (libsodium-compatible all-zero '
            'check) — otherwise confidentiality silently collapses for '
            'exactly the peers that warrant it (hostile ones).');
  });

  test('decryptFromPeer must reject a non-contributory ephemeral key',
      () async {
    // Victim keypair.
    final victimKp = await x.newKeyPair();
    final victimPriv =
        Uint8List.fromList(await victimKp.extractPrivateKeyBytes());
    final victimPub =
        Uint8List.fromList((await victimKp.extractPublicKey()).bytes);

    // Forger crafts an envelope with ephPub = u=0. Victim computes
    // shared = X25519(victimPriv, 0) = 0 - the forger knows it too.
    final forgeKp = await x.newKeyPair();
    final shared = await x.sharedSecretKey(
      keyPair: forgeKp,
      remotePublicKey: SimplePublicKey(Uint8List(32), type: KeyPairType.x25519),
    );
    final aeadKey = await _attackerAeadKey(
        shared: shared, ephemeralPub: Uint8List(32), peerU: victimPub);
    final forged = await aes.encrypt(
        Uint8List.fromList(utf8.encode('FORGED peer message')),
        secretKey: aeadKey);
    final envelope = (BytesBuilder()
          ..addByte(EncryptionService.peerEnvelopeVersion)
          ..add(Uint8List(32)) // low-order ephemeral key
          ..add(forged.concatenation()))
        .toBytes();

    Object? threw;
    Uint8List? plain;
    try {
      plain = await enc.decryptFromPeer(envelope, victimPriv);
    } catch (e) {
      threw = e;
    }

    expect(threw, isNotNull,
        reason: 'decryptFromPeer accepted an envelope whose ephemeral key is '
            'the low-order point u=0: the victim derived the all-zero '
            'shared secret and released attacker-chosen plaintext '
            '("${plain == null ? '' : utf8.decode(plain)}"). A '
            'contributory-behavior check (reject all-zero shared secrets '
            'and low-order public inputs) is required.');
  });

  test(
      'the documented x25519PublicKeyBytes value must round-trip '
      'through encryptForPeer/decryptFromPeer', () async {
    // Real Ed25519 identity.
    final seed = Uint8List.fromList(List.generate(32, (i) => i + 7));
    final edKp = await Ed25519().newKeyPairFromSeed(seed);
    final edPub = Uint8List.fromList((await edKp.extractPublicKey()).bytes);

    // The recipient's X25519 material, derived per the documented
    // conversion (IdentityService.x25519PrivateKeyBytes /
    // x25519PublicKeyBytes equivalents).
    final xPriv = EncryptionService.ed25519SeedToX25519Seed(seed);
    final xKp = await x.newKeyPairFromSeed(xPriv);
    final xPub = Uint8List.fromList((await xKp.extractPublicKey()).bytes);
    // Sanity: the u-coordinate the documentation intends senders to use
    // equals the Edwards→Montgomery map of the Ed25519 public key.
    expect(xPub, equals(EncryptionService.ed25519PublicToX25519(edPub)));

    final data = Uint8List.fromList(utf8.encode('peer-shared DEK'));

    // Path A (works): sender passes the Ed25519 key - mapped once.
    final envA = await enc.encryptForPeer(data, _hex(edPub));
    expect(await enc.decryptFromPeer(envA, xPriv), equals(data));

    // Path B (the documented sender input): pass the X25519
    // u-coordinate itself. _resolvePeerAgreementKey treats it as an
    // Ed25519 key and maps it AGAIN → wrong point → sealed ciphertext.
    final envB = await enc.encryptForPeer(data, _hex(xPub));
    Object? threw;
    Uint8List? opened;
    try {
      opened = await enc.decryptFromPeer(envB, xPriv);
    } catch (e) {
      threw = e;
    }
    expect(opened, equals(data),
        reason: 'encryptForPeer was fed the peer\'s documented X25519 public '
            'key (IdentityService.x25519PublicKeyBytes, "the value a '
            'sender needs inside EncryptionService.encryptForPeer") and '
            'produced a ciphertext the real recipient can never open '
            '(threw=$threw). Success was reported for a permanently '
            'sealed message — silent data loss on the documented path.');
  });
}
