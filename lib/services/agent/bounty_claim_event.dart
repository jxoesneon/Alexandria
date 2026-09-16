import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'beacon_models.dart';
import 'escrow_attestation.dart';

/// Abstract transport for Beacon v2 bounty envelopes (ALX-006 §3).
///
/// This is the seam the deferred "full remote transport" milestone
/// plugs into: any concrete transport (Moltbook API poller, libp2p pubsub,
/// mesh gossip, relay) implements [publish] for outbound envelopes and
/// exposes inbound ones on [envelopes]. `MoltbookService` wires the
/// stream into `ingestBountyEnvelope` / `ingestBountyClaimEnvelope`, so
/// the verification and attribution layer is fully exercised regardless
/// of which transport is bound.
///
/// TRANSPORT CONTRACT: implementations carry opaque [BeaconEnvelope]s -
/// they must never pre-validate, pre-fulfill, or mutate payloads. All
/// trust decisions happen inside the ingest gates.
abstract class BountyTransport {
  /// Broadcasts a signed envelope to the agent swarm.
  Future<void> publish(BeaconEnvelope envelope);

  /// Envelopes received from remote agents (announcements, claim events).
  Stream<BeaconEnvelope> get envelopes;
}

/// In-process fan-out transport - a real [BountyTransport] useful for
/// tests, loopback dev harnesses, and pairing two service instances in
/// one isolate. Delivery is synchronous broadcast to every *other*
/// registered node; a node's own publications are not echoed back
/// (matching remote-transport semantics, where echo suppression lives
/// in the ingest layer's `_locallyPostedBountyIds` guard anyway).
/// The bus itself is not a transport - [attach] returns the per-node
/// [BountyTransport] endpoint.
class InMemoryBountyTransport {
  final _nodes = <int, _Node>{};
  var _nextHandle = 0;

  /// Registers a node and returns its side of the transport. Detach the
  /// returned handle via `_AttachedTransport.detach`.
  BountyTransport attach() {
    final handle = _nextHandle++;
    final node = _Node();
    _nodes[handle] = node;
    return _AttachedTransport(this, handle, node);
  }

  void _deliver(int fromHandle, BeaconEnvelope envelope) {
    for (final entry in _nodes.entries) {
      if (entry.key == fromHandle) continue;
      entry.value.sink.add(envelope);
    }
  }

  void _detach(int handle) {
    _nodes.remove(handle)?.sink.close();
  }
}

class _Node {
  final sink = StreamController<BeaconEnvelope>.broadcast();
}

class _AttachedTransport implements BountyTransport {
  _AttachedTransport(this._bus, this._handle, this._node);
  final InMemoryBountyTransport _bus;
  final int _handle;
  final _Node _node;

  @override
  Future<void> publish(BeaconEnvelope envelope) async =>
      _bus._deliver(_handle, envelope);

  @override
  Stream<BeaconEnvelope> get envelopes => _node.sink.stream;

  /// Removes this node from the bus (closes its inbound stream).
  void detach() => _bus._detach(_handle);
}

/// A signed bounty-claim event: cryptographic evidence that the holder
/// of a specific Ed25519 key claims to have fulfilled a specific bounty
/// (ALX-006 / ALX-012 REV4 remote-claim seam).
///
/// ONLY constructible via [BountyClaimEvent.verify] (signature-checked)
/// or [BountyClaimEvent.issue] (locally signed) - no code path can mint
/// an "event" that did not verify, same enforcement-by-construction rule
/// as [EscrowAttestation].
///
/// The signed preimage binds `bountyId`, `cid`, `claimedAt`,
/// `claimNonce` and `claimantAgentId` under the domain
/// `alexandria:bounty-claim:v2:` - domain separation keeps the event
/// non-replayable as an escrow attestation, a work receipt, or a Beacon
/// envelope. The claimant's *agent id* is additionally bound to the
/// signing key inside [verify] (derived `bcn_` id must match), so a
/// claim event attributes an origin/claimant to a real key, never to a
/// self-asserted string.
///
/// REPLAY NOTE: replaying a claim event is idempotent - it re-asserts
/// the same signed fact about the same bounty. Settlement dedup lives
/// in the durable `claimed_bounties` CAS and payout-row prefixes, so no
/// freshness nonce is required until claim events trigger cross-ledger
/// value movement (see the remote-settlement seam documented on
/// `MoltbookService.ingestBountyClaimEnvelope`).
class BountyClaimEvent {
  /// Beacon envelope kind carrying a claim-event payload.
  static const String envelopeKind = 'bounty_claim';

  /// Hex-encoded Ed25519 pubkey of the claiming agent (the signing key).
  final String claimantPubkey;

  /// `bcn_<first 12 pubkey hex>` derived id - proven inside [verify] to
  /// equal `deriveAgentId(claimantPubkey)`, so this is always an
  /// attributed identity, not a self-declared one.
  final String claimantAgentId;

  /// Bounty id as spelled in the signed preimage. Compare canonically
  /// (`bountyIdsEquivalent` in bounty_id_canonicalization.dart) - the
  /// stored record carries the NFD-normalized form.
  final String bountyId;

  /// Content CID the claim covers.
  final String cid;

  /// Claim timestamp, epoch milliseconds (inside the signed preimage).
  final int claimedAt;

  /// Random claim nonce (inside the signed preimage) - distinct events
  /// for the same bounty get distinct signatures.
  final String claimNonce;

  /// Base64 Ed25519 signature over [signingPreimage].
  final String signature;

  const BountyClaimEvent._({
    required this.claimantPubkey,
    required this.claimantAgentId,
    required this.bountyId,
    required this.cid,
    required this.claimedAt,
    required this.claimNonce,
    required this.signature,
  });

  /// The canonical signed statement - the exact byte preimage the
  /// claimant signs and verifiers recompute. Canonical JSON (sorted
  /// keys) makes field boundaries structural; the
  /// `alexandria:bounty-claim:v2:` domain prefix prevents collisions
  /// with every other signed artifact class in the system.
  static Uint8List signingPreimage({
    required String bountyId,
    required String cid,
    required String claimantAgentId,
    required int claimedAt,
    required String claimNonce,
  }) =>
      Uint8List.fromList(
        utf8.encode(
          'alexandria:bounty-claim:v2:${toCanonicalJson(<String, dynamic>{
                'bountyId': bountyId,
                'cid': cid,
                'claimedAt': claimedAt,
                'claimNonce': claimNonce,
                'claimantAgentId': claimantAgentId,
              })}',
        ),
      );

  /// Constructs an event ONLY if the Ed25519 signature verifies AND the
  /// declared [claimantAgentId] derives from [claimantPubkey] - the
  /// attribution binding. Returns null on any failure (malformed fields,
  /// bad signature, agent-id/pubkey mismatch, throwing [verifyFn]).
  /// [verifyFn] defaults to the same hex-Ed25519 oracle
  /// [EscrowAttestation.verifyEd25519] uses.
  static Future<BountyClaimEvent?> verify({
    required String claimantPubkey,
    required String claimantAgentId,
    required String bountyId,
    required String cid,
    required int claimedAt,
    required String claimNonce,
    required String signature,
    EscrowAttestationVerifier verifyFn = EscrowAttestation.verifyEd25519,
  }) async {
    try {
      if (claimantPubkey.isEmpty ||
          claimantAgentId.isEmpty ||
          bountyId.isEmpty ||
          cid.isEmpty ||
          claimNonce.isEmpty ||
          claimedAt <= 0) {
        return null;
      }
      // Attribution binding: the claimed agent id must be the one
      // derived from the signing key - otherwise the event names an
      // identity the signer cannot control (a bare self-assertion).
      final pkBytes = hexToBytes(claimantPubkey);
      if (pkBytes.length != 32) return null;
      if (BeaconEnvelope.deriveAgentId(pkBytes).toLowerCase() !=
          claimantAgentId.trim().toLowerCase()) {
        return null;
      }
      final sigBytes = base64Decode(signature);
      if (sigBytes.length != 64) return null;
      final ok = await verifyFn(
        signingPreimage(
          bountyId: bountyId,
          cid: cid,
          claimantAgentId: claimantAgentId,
          claimedAt: claimedAt,
          claimNonce: claimNonce,
        ),
        sigBytes,
        claimantPubkey,
      );
      if (!ok) return null;
      return BountyClaimEvent._(
        claimantPubkey: claimantPubkey,
        claimantAgentId: claimantAgentId,
        bountyId: bountyId,
        cid: cid,
        claimedAt: claimedAt,
        claimNonce: claimNonce,
        signature: signature,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses and verifies a claim event out of a Beacon envelope payload.
  /// Returns null for malformed payloads or failed verification -
  /// transports drop, never throw.
  static Future<BountyClaimEvent?> fromPayload(
    Map<String, dynamic> payload, {
    EscrowAttestationVerifier verifyFn = EscrowAttestation.verifyEd25519,
  }) async {
    final claim = payload['claim'];
    if (claim is! Map) return null;
    final m = claim.cast<String, dynamic>();
    return verify(
      claimantPubkey: m['claimant_pubkey'] as String? ?? '',
      claimantAgentId: m['claimant_agent_id'] as String? ?? '',
      bountyId: m['bounty_id'] as String? ?? '',
      cid: m['cid'] as String? ?? '',
      claimedAt: (m['claimed_at'] as num?)?.toInt() ?? 0,
      claimNonce: m['claim_nonce'] as String? ?? '',
      signature: m['sig'] as String? ?? '',
      verifyFn: verifyFn,
    );
  }

  /// Signs a claim event under [keyPair] for [bountyId]/[cid]. The local
  /// node issues one after winning `claimBounty` so the POSTER's node
  /// gets verifiable settlement evidence (the remote-claim transport
  /// caller the `cancelBounty` cross-ledger guard documents).
  static Future<BountyClaimEvent> issue({
    required SimpleKeyPair keyPair,
    required String bountyId,
    required String cid,
    int? claimedAt,
    String? claimNonce,
  }) async {
    final pub = await keyPair.extractPublicKey();
    final pubkeyHex = bytesToHex(pub.bytes);
    final agentId = BeaconEnvelope.deriveAgentId(pub.bytes);
    final at = claimedAt ?? DateTime.now().millisecondsSinceEpoch;
    final nonce = claimNonce ??
        sha256
            .convert(utf8.encode(
                'claim-$bountyId-$agentId-${DateTime.now().microsecondsSinceEpoch}'))
            .toString()
            .substring(0, 20);
    final preimage = signingPreimage(
      bountyId: bountyId,
      cid: cid,
      claimantAgentId: agentId,
      claimedAt: at,
      claimNonce: nonce,
    );
    final sig = await Ed25519().sign(preimage, keyPair: keyPair);
    return BountyClaimEvent._(
      claimantPubkey: pubkeyHex,
      claimantAgentId: agentId,
      bountyId: bountyId,
      cid: cid,
      claimedAt: at,
      claimNonce: nonce,
      signature: base64Encode(sig.bytes),
    );
  }

  /// The `claim` block carried inside a `bounty_claim` envelope payload.
  Map<String, dynamic> toPayloadBlock() => {
        'claimant_pubkey': claimantPubkey,
        'claimant_agent_id': claimantAgentId,
        'bounty_id': bountyId,
        'cid': cid,
        'claimed_at': claimedAt,
        'claim_nonce': claimNonce,
        'sig': signature,
      };

  /// Wraps this event in a signed Beacon v2 envelope of kind
  /// [envelopeKind], signed by the same claimant [keyPair] - the
  /// transport binding: `envelope.agentId == claimantAgentId` and
  /// `envelope.pubkey == claimantPubkey` are enforced by
  /// `MoltbookService.ingestBountyClaimEnvelope`.
  Future<BeaconEnvelope> toEnvelope(
    SimpleKeyPair keyPair, {
    Map<String, dynamic>? clientInfo,
  }) =>
      BeaconEnvelope.create(
        kind: envelopeKind,
        keyPair: keyPair,
        clientInfo: clientInfo,
        payload: {'claim': toPayloadBlock()},
      );
}
