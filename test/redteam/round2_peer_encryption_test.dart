// RED TEAM PoC — EncryptionService.encryptForPeer derives its AES-GCM
// key as sha256(utf8.encode(peerPublicKey)) — a PUBLIC value.
//
// lib/services/encryption_service.dart:42-47: the "peer key" is a hash
// of a public-key STRING. A public key is, by definition, public —
// every node in the swarm can derive the identical key and decrypt.
// There is no ECDH, no ephemeral key, no recipient private-key
// involvement: this is obfuscation, not peer-to-peer confidentiality.
// Any caller believing it protects data "for" a specific peer exposes
// that data to the entire network.
//
// Asserts the SECURE expectation: ciphertext addressed to a peer must
// be undecryptable without that peer's PRIVATE key. Failure marks a
// broken confidentiality primitive.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

void main() {
  test('peer ciphertext must require the peer private key, not the '
      'public key string', () async {
    final enc = EncryptionService();
    const peerPublicKey = 'attacker-known-public-key-base58-string';
    final secret =
        Uint8List.fromList(utf8.encode('escrow-release-preimage-42'));

    final ciphertext = await enc.encryptForPeer(secret, peerPublicKey);

    // Eavesdropper: knows ONLY the public key string (broadcast on the
    // mesh) — derives the same key and decrypts. No private key, no
    // handshake, no service internals.
    final eavesKey = await enc
        .keyFromBytes(sha256.convert(utf8.encode(peerPublicKey)).bytes);
    final recovered = await enc.decryptData(ciphertext, eavesKey);

    expect(recovered, isNot(equals(secret)),
        reason:
            'an eavesdropper decrypted "peer-encrypted" data using only '
            'the recipient\'s PUBLIC key — sha256(pubkey) is a '
            'deterministic public value, so encryptForPeer provides '
            'zero confidentiality');
  });
}
