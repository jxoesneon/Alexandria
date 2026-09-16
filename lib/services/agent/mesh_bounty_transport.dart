import 'dart:async';
import 'dart:convert';

import '../mesh_transport_service.dart';
import 'beacon_models.dart';
import 'bounty_claim_event.dart';

/// Production [BountyTransport] bound to the mesh channel layer
/// (ALX-006 §3 / the deferred remote-transport milestone).
///
/// WHY THE MESH CHANNEL (and not `IpfsService.publishToPubsub`): the
/// mesh layer is the only transport in-tree that carries real
/// peer-authenticated frames — every outbound payload leaves as
/// `seq ‖ payload ‖ HMAC-SHA256(channelKey, …)` under a key derived
/// from the ALX-MESH/1 ephemeral-X25519 handshake, and inbound frames
/// are MAC-verified and replay-checked by `receiveFrame` before
/// release. `IpfsService.publishToPubsub` is a loopback stub that
/// echoes to its own controller with `sender: 'self'` — binding a
/// transport to it would deliver envelopes only to ourselves, which is
/// strictly less real than InMemoryBountyTransport. When dart_ipfs
/// gains a real pubsub backend this class can be swapped at the seam.
///
/// WIRE FORMAT: each outbound envelope is one mesh frame payload —
/// `utf8(jsonEncode(envelope.toJson()))`. Inbound payloads are decoded
/// and parsed structurally ONLY ([BeaconEnvelope.parse]); signature
/// verification, kind allowlists and trust decisions all live in
/// `MoltbookService`'s ingest gates, per the [BountyTransport]
/// contract — the transport never pre-validates or mutates.
///
/// FAN-OUT MODEL: the mesh channel is point-to-point, so publish is a
/// unicast to every currently-proven peer (`isReachable` AND
/// `hasChannelBinding`). Envelopes carry their own attribution
/// (signature-bound `agent_id`/`pubkey`), so the sender identity is
/// not needed at this layer.
///
/// HONEST DELIVERY BOUND: `MeshTransportService.sendPayload` reports
/// "frame dispatched toward a route" — the wire dispatch inside the
/// mesh layer is itself an injected seam (`MeshFrameTransport`), and
/// inbound delivery requires the node's socket listener to feed
/// `receiveFrame` (an orchestrator wiring step, not something this
/// class can perform). publish() therefore means "handed to every
/// proven channel", never "acknowledged by a remote ingest gate".
/// `MoltbookService` already treats publish as best-effort, matching
/// this bound.
class MeshBountyTransport implements BountyTransport {
  MeshBountyTransport(
    this._mesh, {
    this.maxEnvelopeBytes = 64 * 1024,
  });

  final MeshTransportService _mesh;

  /// Inbound payload size cap — a peer can only send frames the channel
  /// MACs, but a compromised/misbehaving proven peer could still push
  /// oversized garbage; drop it before decode costs accrue.
  final int maxEnvelopeBytes;

  @override
  Stream<BeaconEnvelope> get envelopes => _mesh.onPayloadReceived
      .map(_tryDecode)
      .where((e) => e != null)
      .cast<BeaconEnvelope>();

  BeaconEnvelope? _tryDecode(List<int> payload) {
    if (payload.isEmpty || payload.length > maxEnvelopeBytes) return null;
    try {
      return BeaconEnvelope.parse(utf8.decode(payload));
    } catch (_) {
      return null; // undecodable frames drop — never surface
    }
  }

  /// Fans the envelope out to every proven mesh channel. Per-peer
  /// dispatch failures are isolated (one wedged peer cannot block the
  /// rest) and reported via [lastFanout]. Completes normally even when
  /// no peer is currently proven — the caller treats transport as
  /// best-effort and the durable ledger, not the broadcast, is the
  /// settlement record.
  @override
  Future<void> publish(BeaconEnvelope envelope) async {
    final bytes = utf8.encode(jsonEncode(envelope.toJson()));
    if (bytes.length > maxEnvelopeBytes) return; // refuse to emit junk
    var delivered = 0;
    final targets = _mesh.peers.where(
        (p) => p.isReachable && _mesh.hasChannelBinding(p.peerId));
    for (final peer in targets) {
      try {
        if (await _mesh.sendPayload(peer.peerId, bytes)) delivered++;
      } catch (_) {
        // One peer's dispatch failure must not stop the fan-out.
      }
    }
    lastFanout = delivered;
  }

  /// How many proven channels the last [publish] dispatched onto —
  /// operator-observable honesty about delivery reach.
  int lastFanout = 0;
}
