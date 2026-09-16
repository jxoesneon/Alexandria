import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'identity_service.dart' show AlexandriaIdentity, identityServiceProvider;

final meshTransportServiceProvider = Provider((ref) {
  // Mutual-auth wiring (dialer-auth residual closure): the service
  // presents the node's own Alexandria identity when dialing, so a
  // responder can verify the dialer owns the claimed self-certifying
  // peerId - a MITM that cannot produce that signature is refused.
  final identityService = ref.read(identityServiceProvider);
  return MeshTransportService(
    bootstrap: true,
    identitySigner: identityService.sign,
    localPeerIdResolver: () async =>
        (await identityService.getIdentity())?.publicKeyBase58,
  );
});

/// Probes a multiaddr for an actual reachable endpoint.
///
/// Returns `true` only when the remote end demonstrably answered the
/// handshake (e.g. a TCP connect + protocol ping completed). This is the
/// seam that keeps [MeshTransportService.connectToPeer] honest AND
/// testable: production uses the built-in socket probe, tests inject a
/// delegate to simulate success/failure without real sockets.
///
/// Prefer [MeshSessionProbe] for new code: a bool answer proves the
/// handshake happened but carries none of the transcript needed to
/// derive the post-handshake channel key (round-5 residual closure).
typedef MeshHandshakeProbe = Future<bool> Function(String multiaddr);

/// The material a completed ALX-MESH/1 handshake leaves behind:
///   * the exact wire transcript both ends recompute - the dialer's
///     `HELLO` line (nonce + multiaddr + dialer ephemeral X25519 key)
///     and the responder's `ACK` line (peerId + signature + responder
///     ephemeral X25519 key), and
///   * the X25519 shared secret the two ephemeral keys produced.
///
/// Both halves matter (round-5 residual closure): the transcript alone
/// is PUBLIC wire material - a relay that forwarded the handshake could
/// recompute a transcript-only key and still splice frames. The
/// ephemeral DH secret is what a forward-only relay cannot learn, and
/// the responder's Ed25519 signature covers BOTH ephemeral keys, so a
/// MITM cannot substitute its own keypair without forging the claimed
/// identity's signature. Key derivation is HKDF-SHA256(salt =
/// sharedSecret, ikm = transcript) - bound to the handshake AND
/// uncomputable by observers.
///
/// [transcriptBound] is false only for SYNTHETIC tickets - produced
/// when a legacy bool [MeshHandshakeProbe] (or a test double) reports
/// success without running the wire exchange. A synthetic ticket still
/// yields a per-dial session key, but one no remote peer can recompute;
/// it exists to keep the injectable seam honest, not to impersonate a
/// real transcript.
class MeshHandshakeTicket {
  final String peerId;
  final String multiaddr;
  final String nonce;
  final Uint8List responderSignature;
  final String dialerEphemeral;
  final String responderEphemeral;

  /// (dialer-auth residual closure) The dialer's self-certifying
  /// peerId and its Ed25519 signature over
  /// `nonce‖dialerPeerId‖multiaddr‖dialerEphemeral` - present only on
  /// the MUTUAL (7-field) HELLO form. Empty for anonymous dials and
  /// synthetic tickets.
  final String dialerPeerId;
  final Uint8List dialerSignature;

  /// The X25519 shared secret from the ephemeral exchange - the part a
  /// handshake-observing relay cannot recompute. Random for synthetic
  /// tickets (local-only binding).
  final Uint8List sharedSecret;
  final bool transcriptBound;

  /// Whether this ticket describes the RESPONDER end of the handshake
  /// (produced by [MeshTransportService.serveHandshake]). Direction
  /// binding: frames carry a direction bit inside their MAC domain so
  /// a relay cannot reflect one side's frames back to the sender.
  final bool responderSide;

  /// The live handshake socket + its broadcast byte stream, when the
  /// ticket came from a real wire exchange. The channel pump
  /// ([MeshTransportService._attachSocket]) consumes [socketStream]
  /// for inbound length-prefixed frames and writes outbound frames to
  /// [socket]. Null for injected/synthetic tickets - those channels
  /// keep routing-stub dispatch semantics.
  ///
  /// Do NOT listen on [socket] directly: it is single-subscription and
  /// already consumed by the handshake read; [socketStream] is the
  /// shareable view.
  final Socket? socket;
  final Stream<Uint8List>? socketStream;

  MeshHandshakeTicket({
    required this.peerId,
    required this.multiaddr,
    required this.nonce,
    required this.responderSignature,
    this.dialerEphemeral = '',
    this.responderEphemeral = '',
    this.dialerPeerId = '',
    Uint8List? dialerSignature,
    Uint8List? sharedSecret,
    this.transcriptBound = true,
    this.responderSide = false,
    this.socket,
    this.socketStream,
  })  : sharedSecret = sharedSecret ?? MeshTransportService.randomBytes(32),
        dialerSignature = dialerSignature ?? Uint8List(0);

  /// A locally-fabricated ticket for injected-probe success paths: the
  /// nonce and secret are fresh randomness, no responder signature
  /// exists, so the derived channel key is bound to THIS dial's
  /// material only.
  factory MeshHandshakeTicket.synthetic(String peerId, String multiaddr) =>
      MeshHandshakeTicket(
        peerId: peerId,
        multiaddr: multiaddr,
        nonce: MeshTransportService.randomNonceHex(),
        responderSignature: Uint8List(0),
        transcriptBound: false,
      );

  /// The canonical transcript both sides recompute - the two wire lines
  /// exactly as exchanged (`HELLO` sent by the dialer, `ACK` answered
  /// by the responder). The mutual (7-field) HELLO is reproduced
  /// verbatim when the dialer authenticated, so BOTH signatures feed
  /// the session-key transcript (dialer-auth residual closure).
  Uint8List get transcriptBytes {
    final hello = dialerPeerId.isEmpty
        ? '${MeshTransportService.handshakeProtocol} HELLO $nonce '
            '$multiaddr $dialerEphemeral'
        : '${MeshTransportService.handshakeProtocol} HELLO $nonce '
            '$multiaddr $dialerEphemeral $dialerPeerId '
            '${base64Encode(dialerSignature)}';
    return Uint8List.fromList(utf8.encode('$hello\n'
        '${MeshTransportService.handshakeProtocol} ACK $nonce $peerId '
        '${base64Encode(responderSignature)} $responderEphemeral'));
  }
}

/// A handshake probe that returns the full [MeshHandshakeTicket] so the
/// session channel can be bound to the transcript (round-5 residual
/// closure). Returns null when the handshake fails.
typedef MeshSessionProbe = Future<MeshHandshakeTicket?> Function(
    String multiaddr);

/// Dispatches a MAC'd, sequenced channel frame to [peerId]. Injectable
/// so tests can capture frames / simulate a failing link; the default
/// is still a routing stub (see [MeshTransportService.sendPayload]).
typedef MeshFrameTransport = Future<bool> Function(
    String peerId, Uint8List frame);

enum TransportTier {
  lanMdns,
  wifiDirect,
  webrtcDirect,
  bleProximity,
  circuitRelay,
}

class MeshPeer {
  final String peerId;
  final String address;
  final TransportTier tier;
  final int latencyMs;
  final bool isReachable;
  final bool isPending;

  /// (round-3 red finding) `isReachable` defaults to FALSE - a peer is
  /// proven by a completed handshake, never by construction.
  MeshPeer({
    required this.peerId,
    required this.address,
    required this.tier,
    required this.latencyMs,
    this.isReachable = false,
    this.isPending = false,
  });

  MeshPeer copyWith({
    String? peerId,
    String? address,
    TransportTier? tier,
    int? latencyMs,
    bool? isReachable,
    bool? isPending,
  }) {
    return MeshPeer(
      peerId: peerId ?? this.peerId,
      address: address ?? this.address,
      tier: tier ?? this.tier,
      latencyMs: latencyMs ?? this.latencyMs,
      isReachable: isReachable ?? this.isReachable,
      isPending: isPending ?? this.isPending,
    );
  }
}

class MeshTransportService {
  final Map<String, MeshPeer> _peers = {};
  final StreamController<MeshPeer> _peerDiscoveryController =
      StreamController.broadcast();
  final StreamController<Uint8List> _incomingPayloadController =
      StreamController.broadcast();
  final StreamController<List<MeshPeer>> _peerListController =
      StreamController.broadcast();

  final Set<TransportTier> _activeTiers = {
    TransportTier.lanMdns,
    TransportTier.wifiDirect,
    TransportTier.webrtcDirect,
    TransportTier.bleProximity,
    TransportTier.circuitRelay,
  };

  /// Reachability prover used by [connectToPeer]. Defaults to a real
  /// TCP connect + signed protocol exchange against `/…/tcp/<port>`
  /// multiaddrs (see [_defaultSessionProbe]); injectable so tests can
  /// simulate a peer that answers or one that never will.
  ///
  /// The probe returns a [MeshHandshakeTicket] - not a bare bool - so a
  /// successful handshake leaves the transcript needed to derive the
  /// post-handshake channel key (round-5 residual closure). A legacy
  /// bool [MeshHandshakeProbe] is adapted into a SYNTHETIC ticket (the
  /// channel key then binds this dial's material only - enough to keep
  /// the injected-probe test seam working, not a shared secret).
  /// Assigned in the constructor body (the default tears off an
  /// instance method).
  late final MeshSessionProbe _sessionProbe;

  /// Frame dispatcher used by [sendPayload]. The default
  /// ([_dispatchFrame]) writes length-prefixed frames to the peer's
  /// handshake socket - or, for socket-less injected-probe channels,
  /// reports whether a tier route exists (routing-stub semantics).
  /// Injectable so tests can observe the exact MAC'd frames that
  /// leave the channel.
  late final MeshFrameTransport _frameTransport;

  /// (round-5 residual closure) Post-handshake channel state per peer.
  /// The handshake binds IDENTITY (round-4) but previously derived no
  /// key material, so a relay that passed the handshake could splice
  /// later frames. Now every sendPayload frame is
  /// `seq(8 BE) ‖ payload ‖ HMAC-SHA256(channelKey, domain ‖ seq ‖
  /// payload)` where the channel key is HKDF-SHA256 over the handshake
  /// transcript ([MeshHandshakeTicket.transcriptBytes]) - a relay that
  /// merely forwarded the HELLO/ACK cannot forge the MAC, and the
  /// per-direction sequence counter rejects replays.
  final Map<String, _MeshChannel> _channels = {};

  /// Upper bound on a handshake attempt - a peer that cannot answer
  /// inside this window is unreachable for routing purposes.
  static const Duration handshakeTimeout = Duration(seconds: 4);

  /// (dialer-auth residual closure) Local identity material for the
  /// MUTUAL handshake form. When [identitySigner] and a self-certifying
  /// [localPeerId] (static or via [localPeerIdResolver]) are both
  /// present, the default dialer sends the 7-field HELLO carrying an
  /// Ed25519 signature over
  /// `nonce‖dialerPeerId‖multiaddr‖dialerEphemeral` - the responder
  /// verifies it against the public key the peerId itself encodes, so a
  /// MITM cannot complete a handshake toward the responder while
  /// claiming an identity it does not own. With no identity plumbed in
  /// the dialer stays anonymous (5-field HELLO): the responder is still
  /// authenticated, the dialer is not.
  final String? localPeerId;
  final Future<String?> Function()? localPeerIdResolver;
  final Future<Uint8List> Function(Uint8List payload)? identitySigner;

  MeshTransportService({
    bool bootstrap = false,
    this.localPeerId,
    this.localPeerIdResolver,
    this.identitySigner,
    MeshHandshakeProbe? handshakeProbe,
    MeshSessionProbe? sessionProbe,
    MeshFrameTransport? frameTransport,
  }) {
    _sessionProbe = sessionProbe ??
        (handshakeProbe != null
            ? _legacyProbeAdapter(handshakeProbe)
            : _defaultSessionProbeWithIdentity);
    _frameTransport = frameTransport ?? _dispatchFrame;
    if (bootstrap) {
      bootstrapDefaultPeers();
    }
  }

  /// Resolves the local peerId for the mutual handshake: the static
  /// [localPeerId] wins, else the lazy resolver (used by the provider
  /// wiring so identity creation order does not matter). Null → the
  /// dial is anonymous.
  Future<String?> _resolveLocalPeerId() async {
    final staticId = localPeerId;
    if (staticId != null) return staticId;
    final resolver = localPeerIdResolver;
    if (resolver == null) return null;
    try {
      return await resolver();
    } catch (_) {
      return null;
    }
  }

  /// Instance entry point for the production dialer: passes the
  /// configured identity material into the static wire routine so the
  /// [MeshSessionProbe] seam stays a bare `multiaddr → ticket`.
  Future<MeshHandshakeTicket?> _defaultSessionProbeWithIdentity(
          String multiaddr) async =>
      _defaultSessionProbe(
        multiaddr,
        localPeerId: await _resolveLocalPeerId(),
        identitySigner: identitySigner,
      );

  /// Adapts the legacy bool seam: a `true` answer produces a synthetic
  /// ticket (fresh local nonce, no responder signature). The derived
  /// channel key is per-dial and unshareable - documented by
  /// [MeshHandshakeTicket.transcriptBound].
  static MeshSessionProbe _legacyProbeAdapter(MeshHandshakeProbe probe) =>
      (String multiaddr) async {
        final ok = await probe(multiaddr);
        if (!ok) return null;
        final peerId = _peerIdFromMultiaddrStatic(multiaddr);
        if (peerId == null || peerId.isEmpty) return null;
        return MeshHandshakeTicket.synthetic(peerId, multiaddr);
      };

  /// Wire protocol identifier for the peer handshake.
  static const String handshakeProtocol = 'ALX-MESH/1';

  /// The exact byte string the answering peer signs to prove identity -
  /// `ALX-MESH/1|nonce|peerId|multiaddr-as-dialed|dialerEph|
  /// responderEph` - binding the claimed identity to THIS dial
  /// (round-4 red finding) AND to both ephemeral X25519 keys, so a MITM
  /// cannot substitute its own keypair to learn the channel secret
  /// (round-5 residual closure). When both ephemeral fields are empty
  /// the legacy identity-only form `ALX-MESH/1|nonce|peerId|multiaddr`
  /// is produced verbatim.
  ///
  /// (dialer-auth residual closure) When [dialerPeerId] is non-empty it
  /// is appended as a sixth field, so the responder's signature also
  /// attests WHO it completed the mutual handshake with - the ACK
  /// cannot be re-contextualized as an answer to a different claimed
  /// dialer identity.
  static Uint8List handshakeSignBytes(
    String nonce,
    String peerId,
    String multiaddr, [
    String dialerEphemeral = '',
    String responderEphemeral = '',
    String dialerPeerId = '',
  ]) =>
      Uint8List.fromList(utf8.encode(
        dialerEphemeral.isEmpty && responderEphemeral.isEmpty
            ? '$handshakeProtocol|$nonce|$peerId|$multiaddr'
            : '$handshakeProtocol|$nonce|$peerId|$multiaddr|$dialerEphemeral|$responderEphemeral${dialerPeerId.isEmpty ? '' : '|$dialerPeerId'}',
      ));

  /// The exact byte string the DIALER signs to prove it owns the
  /// claimed [dialerPeerId] - `ALX-MESH/1|DIALER|nonce|dialerPeerId|
  /// multiaddr|dialerEphemeral`. The distinct `DIALER` domain tag keeps
  /// the two signature roles non-interchangeable: a dialer signature
  /// can never be replayed as a responder ACK (or vice versa), and the
  /// nonce + ephemeral binding keeps it scoped to this dial.
  static Uint8List dialerHelloSignBytes(
    String nonce,
    String dialerPeerId,
    String multiaddr,
    String dialerEphemeral,
  ) =>
      Uint8List.fromList(utf8.encode(
        '$handshakeProtocol|DIALER|$nonce|$dialerPeerId|$multiaddr|$dialerEphemeral',
      ));

  /// Decodes a self-certifying peerId into its Ed25519 public key.
  /// A mesh peerId IS the Base58 spelling of the peer's 32-byte
  /// identity key - anything else is unverifiable and unproven.
  static Uint8List? _peerIdPublicKey(String peerId) {
    try {
      final decoded = AlexandriaIdentity.decodePublicKeyBase58(peerId);
      return decoded.length == 32 ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Default reachability proof: parse a `/ip4|ip6|dns4|dns6 …`
  /// `/tcp/<port>`
  /// multiaddr, open a TCP connection, and complete a real protocol
  /// handshake. The anonymous dialer sends
  ///   `ALX-MESH/1 HELLO <nonce> <multiaddr> <dialerEphB64>`
  /// or, when [localPeerId] + [identitySigner] give it credentials, the
  /// mutual form
  ///   `ALX-MESH/1 HELLO <nonce> <multiaddr> <dialerEphB64>`
  ///   `<dialerPeerId> <dialerSigB64>`
  /// and requires
  ///   `ALX-MESH/1 ACK <nonce> <peerId> <sigB64> <responderEphB64>`
  /// where `<peerId>` must equal the `/p2p/` component of the dialed
  /// multiaddr AND `<sigB64>` must be a valid Ed25519 signature - under
  /// the public key the peerId itself encodes - over
  /// `nonce‖peerId‖multiaddr‖dialerEph‖responderEph[‖dialerPeerId]`.
  /// The ephemeral X25519 keys produce a shared secret that seeds the
  /// channel key - a forward-only relay can read the transcript but
  /// cannot recompute the secret, and cannot swap in its own keys
  /// without breaking the responder's signature (round-5 residual
  /// closure). In the mutual form the dialer additionally signs
  /// `nonce‖dialerPeerId‖multiaddr‖dialerEphemeral`, so the responder
  /// authenticates the dialer by the same self-certifying peerId rule -
  /// a MITM that cannot produce that signature is refused before the
  /// ephemeral exchange (dialer-auth residual closure).
  ///
  /// On success returns the [MeshHandshakeTicket] carrying the full
  /// transcript + shared secret, with the socket LEFT OPEN as the
  /// frame transport ([MeshHandshakeTicket.socket] /
  /// [MeshHandshakeTicket.socketStream]); the caller attaches the
  /// channel pump or destroys it.
  ///
  /// (round-3 red finding) A bare TCP accept is NOT proof of a peer.
  /// (round-4 red finding) An echoed peerId is NOT proof either - the
  /// round-3 ACK let any listener claim ANY peerId (the caller had just
  /// told it which one to echo). The signature binds the handshake to
  /// the claimed identity's private key, so an endpoint without those
  /// credentials can never mint `isReachable` for a victim peerId.
  ///
  /// Key-distribution residual: peerIds are self-certifying (the id IS
  /// the public key), so no out-of-band key channel is needed for the
  /// handshake itself - but whatever produces the multiaddr (discovery,
  /// rendezvous) still chooses WHICH peerId you dial; that binding is
  /// only as trustworthy as its source.
  static Future<MeshHandshakeTicket?> _defaultSessionProbe(
    String multiaddr, {
    String? localPeerId,
    Future<Uint8List> Function(Uint8List payload)? identitySigner,
  }) async {
    final match = RegExp(
      r'^/(ip4|ip6|dns4|dns6)/([^/]+)/tcp/(\d+)(?:/|$)',
    ).firstMatch(multiaddr);
    if (match == null) return null;
    final host = match.group(2)!;
    final port = int.tryParse(match.group(3)!);
    if (port == null || port <= 0 || port > 65535) return null;
    final peerId = _peerIdFromMultiaddrStatic(multiaddr);
    if (peerId == null || peerId.isEmpty) return null;
    final peerKey = _peerIdPublicKey(peerId);
    if (peerKey == null) return null; // peerId carries no public key
    // Mutual auth is possible only when the local peerId is itself
    // self-certifying - a signature over a peerId that carries no
    // public key could never be verified and would poison the dial.
    final mutual = localPeerId != null &&
        identitySigner != null &&
        _peerIdPublicKey(localPeerId) != null;
    Socket? socket;
    var completed = false;
    try {
      socket = await Socket.connect(host, port, timeout: handshakeTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      // One broadcast view for the handshake read AND the later frame
      // pump - the socket is single-subscription; when the line read
      // cancels, the underlying subscription pauses (no bytes lost)
      // until the pump attaches.
      final stream = socket.asBroadcastStream();
      final nonce = randomNonceHex();
      // Ephemeral X25519 for the channel secret (round-5 residual
      // closure): the dialer contributes a fresh keypair per dial.
      final x25519 = X25519();
      final dialerPair = await x25519.newKeyPair();
      final dialerEph =
          base64Encode((await dialerPair.extractPublicKey()).bytes);
      Uint8List? dialerSignature;
      final String hello;
      if (mutual) {
        dialerSignature = await identitySigner(
            dialerHelloSignBytes(nonce, localPeerId, multiaddr, dialerEph));
        // A signer that cannot produce an Ed25519 signature is broken
        // identity plumbing - fail the dial closed rather than
        // silently downgrade to the anonymous form the operator did
        // not ask for.
        if (dialerSignature.length != 64) return null;
        hello = '$handshakeProtocol HELLO $nonce $multiaddr $dialerEph '
            '$localPeerId ${base64Encode(dialerSignature)}';
      } else {
        hello = '$handshakeProtocol HELLO $nonce $multiaddr $dialerEph';
      }
      socket.add(utf8.encode('$hello\n'));
      await socket.flush();
      final line = await utf8.decoder
          .bind(stream)
          .transform(const LineSplitter())
          .first
          .timeout(handshakeTimeout);
      final parts = line.trim().split(' ');
      if (parts.length != 6 ||
          parts[0] != handshakeProtocol ||
          parts[1] != 'ACK' ||
          parts[2] != nonce ||
          parts[3] != peerId) {
        return null;
      }
      final signature = base64Decode(parts[4]);
      final responderEph = parts[5];
      final responderEphBytes = base64Decode(responderEph);
      if (responderEphBytes.length != 32) return null;
      // The signature must cover BOTH ephemeral keys - otherwise a MITM
      // could strip the eph fields or substitute its own pair and learn
      // the channel secret - and, in the mutual form, the claimed
      // dialer identity, so the ACK cannot be re-attributed.
      final verified = await Ed25519().verify(
        handshakeSignBytes(nonce, peerId, multiaddr, dialerEph, responderEph,
            mutual ? localPeerId : ''),
        signature: Signature(
          Uint8List.fromList(signature),
          publicKey: SimplePublicKey(peerKey, type: KeyPairType.ed25519),
        ),
      );
      if (!verified) return null;
      final shared = await x25519.sharedSecretKey(
        keyPair: dialerPair,
        remotePublicKey:
            SimplePublicKey(responderEphBytes, type: KeyPairType.x25519),
      );
      final sharedBytes = Uint8List.fromList(await shared.extractBytes());
      // Low-order-point guard: an all-zero shared secret means the peer
      // sent a degenerate public key (contributed-keylog/forgery edge)
      // - refuse rather than derive a public-known channel key.
      if (sharedBytes.every((b) => b == 0)) return null;
      completed = true;
      return MeshHandshakeTicket(
        peerId: peerId,
        multiaddr: multiaddr,
        nonce: nonce,
        responderSignature: Uint8List.fromList(signature),
        dialerEphemeral: dialerEph,
        responderEphemeral: responderEph,
        dialerPeerId: mutual ? localPeerId : '',
        dialerSignature: dialerSignature,
        sharedSecret: sharedBytes,
        socket: socket,
        socketStream: stream,
      );
    } catch (_) {
      return null;
    } finally {
      // The socket stays open ONLY on a completed handshake - it is the
      // frame transport. Every failure path still destroys it.
      if (!completed) socket?.destroy();
    }
  }

  /// Responder half of the handshake, for the inbound-listener path:
  /// reads the dialer's `HELLO <nonce> [<multiaddr> [<dialerEphB64>`
  /// `[<dialerPeerId> <dialerSigB64>]]]` line and answers with an ACK
  /// carrying an Ed25519 signature over
  /// `nonce‖localPeerId‖multiaddr‖dialerEph‖responderEph[‖dialerPeerId]`
  /// produced by [identitySigner] (e.g. `IdentityService.sign`).
  /// Without a signer the endpoint can only prove liveness - it emits
  /// an unsigned ACK that identity-binding dialers always reject, and
  /// this method reports false.
  ///
  /// (dialer-auth residual closure) The 7-field HELLO is the mutual
  /// form: the responder verifies the dialer's Ed25519 signature over
  /// `nonce‖dialerPeerId‖multiaddr‖dialerEphemeral` against the public
  /// key `dialerPeerId` encodes BEFORE doing any ephemeral work - a
  /// forged or unverifiable dialer identity is refused with NO answer
  /// (the dialer is presumably hostile; a silent close is the cheapest
  /// refusal). A 6-field HELLO - a claimed identity with no proof -
  /// is malformed and refused the same way.
  ///
  /// [onSessionBound] (round-5 residual closure) receives the
  /// responder-side [MeshHandshakeTicket] - transcript plus the X25519
  /// shared secret - when a SIGNED ack over an ephemeral exchange was
  /// produced; feed it to [deriveSessionKey] to reconstruct the same
  /// channel key the dialer derives. The ticket also carries the live
  /// [MeshHandshakeTicket.socket]/[MeshHandshakeTicket.socketStream]
  /// so the listener can attach a frame pump - do not re-listen on the
  /// socket itself. It is never invoked for the unsigned path, for a
  /// legacy HELLO carrying no ephemeral key (the exchange can bind
  /// identity but not a channel), or for a degenerate low-order peer
  /// key.
  static Future<bool> serveHandshake(
    Socket socket,
    String localPeerId, {
    Future<Uint8List> Function(Uint8List payload)? identitySigner,
    void Function(MeshHandshakeTicket ticket)? onSessionBound,
  }) async {
    try {
      // Broadcast view: the handshake line read and any later frame
      // pump share the single-subscription socket without losing
      // buffered bytes between listeners.
      final stream = socket.asBroadcastStream();
      final line = await utf8.decoder
          .bind(stream)
          .transform(const LineSplitter())
          .first
          .timeout(handshakeTimeout);
      final parts = line.trim().split(' ');
      // Valid HELLO arities: 3 (nonce only), 4 (+multiaddr),
      // 5 (+dialerEph), 7 (+dialerPeerId+dialerSig - mutual). Six
      // fields is a claimed identity without proof - refuse it.
      if (parts.length < 3 ||
          parts.length == 6 ||
          parts.length > 7 ||
          parts[0] != handshakeProtocol ||
          parts[1] != 'HELLO' ||
          !RegExp(r'^[0-9a-f]{16,64}$').hasMatch(parts[2])) {
        return false;
      }
      final nonce = parts[2];
      final dialedMultiaddr = parts.length >= 4 ? parts[3] : '';
      final dialerEph = parts.length >= 5 ? parts[4] : '';
      final dialerPeerId = parts.length == 7 ? parts[5] : '';
      final signer = identitySigner;
      if (signer == null) {
        // No credentials for the claimed peerId - answer (so the dialer
        // fails fast) but never produce a proof we cannot make.
        socket.add(utf8.encode('$handshakeProtocol ACK $nonce $localPeerId\n'));
        await socket.flush();
        return false;
      }
      Uint8List dialerSignature = Uint8List(0);
      if (dialerPeerId.isNotEmpty) {
        // Mutual form: authenticate the DIALER first. The signature
        // must verify under the public key the claimed peerId itself
        // encodes - an endpoint asserting an identity it does not own
        // is refused before any key exchange work.
        final dialerKey = _peerIdPublicKey(dialerPeerId);
        if (dialerKey == null) return false;
        try {
          dialerSignature = base64Decode(parts[6]);
        } catch (_) {
          return false;
        }
        if (dialerSignature.length != 64) return false;
        final dialerOk = await Ed25519().verify(
          dialerHelloSignBytes(nonce, dialerPeerId, dialedMultiaddr, dialerEph),
          signature: Signature(
            dialerSignature,
            publicKey: SimplePublicKey(dialerKey, type: KeyPairType.ed25519),
          ),
        );
        if (!dialerOk) return false;
      }
      if (dialerEph.isEmpty) {
        // Legacy HELLO with no ephemeral key: identity can still be
        // proven, but no channel secret exists - sign the identity-only
        // form and bind no channel.
        final signature = await signer(
            handshakeSignBytes(nonce, localPeerId, dialedMultiaddr));
        socket.add(utf8.encode(
            '$handshakeProtocol ACK $nonce $localPeerId ${base64Encode(signature)}\n'));
        await socket.flush();
        return true;
      }
      final dialerEphBytes = base64Decode(dialerEph);
      if (dialerEphBytes.length != 32) return false;
      final x25519 = X25519();
      final responderPair = await x25519.newKeyPair();
      final responderEph =
          base64Encode((await responderPair.extractPublicKey()).bytes);
      // Mutual form: the responder's signature additionally covers the
      // verified dialer identity, so the ACK cannot be re-attributed to
      // a different claimed dialer.
      final signature = await signer(handshakeSignBytes(nonce, localPeerId,
          dialedMultiaddr, dialerEph, responderEph, dialerPeerId));
      socket.add(utf8.encode(
          '$handshakeProtocol ACK $nonce $localPeerId ${base64Encode(signature)} $responderEph\n'));
      await socket.flush();
      final shared = await x25519.sharedSecretKey(
        keyPair: responderPair,
        remotePublicKey:
            SimplePublicKey(dialerEphBytes, type: KeyPairType.x25519),
      );
      final sharedBytes = Uint8List.fromList(await shared.extractBytes());
      // Low-order-point guard - mirrors the dialer-side check: never
      // bind a channel on a degenerate all-zero shared secret.
      if (sharedBytes.every((b) => b == 0)) return true;
      onSessionBound?.call(MeshHandshakeTicket(
        peerId: localPeerId,
        multiaddr: dialedMultiaddr,
        nonce: nonce,
        responderSignature: signature,
        dialerEphemeral: dialerEph,
        responderEphemeral: responderEph,
        dialerPeerId: dialerPeerId,
        dialerSignature: dialerSignature,
        sharedSecret: sharedBytes,
        responderSide: true,
        socket: socket,
        socketStream: stream,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String randomNonceHex() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));

  // --- Post-handshake channel binding (round-5 residual closure) ---
  //
  // Frame wire format: seq(8, big-endian) ‖ payload ‖ mac(32) where
  //   mac = HMAC-SHA256(channelKey,
  //             "alx-mesh-frame:v1" ‖ direction(1) ‖ seq ‖ payload)
  //   channelKey = HKDF-SHA256(
  //     salt = ticket.sharedSecret,      // ephemeral X25519 output
  //     ikm  = ticket.transcriptBytes,   // both wire lines
  //     info = "alexandria:mesh-channel:v1")
  //
  // The transcript is `HELLO nonce multiaddr dialerEph [dialerPeerId
  // dialerSig]` ‖ `ACK nonce peerId sigB64 responderEph` - both wire
  // lines verbatim, so BOTH signatures feed the key (dialer-auth
  // residual closure). The DH secret keeps the key out of a
  // forward-only relay's reach; the transcript keeps it bound to THIS
  // handshake on THIS multiaddr.
  //
  // The direction byte (implicit - never serialized) makes the two
  // halves of the conversation non-interchangeable: a relay that
  // reflects a dialer's own frame back at it gets a MAC mismatch, not
  // a looped payload. (Reflection needs no key knowledge - it is a
  // pure copy - so an unkeyed direction would not help; the direction
  // lives inside the MAC domain so the tag itself differs per
  // direction.)

  static const int _frameSeqLen = 8;
  static const int _frameMacLen = 32;
  static const int _framePrefixLen = 4;

  /// Frame direction tags mixed into the MAC domain (not sent on the
  /// wire - both sides derive them from the ticket's responderSide).
  static const int _dirDialerToResponder = 0;
  static const int _dirResponderToDialer = 1;

  /// Upper bound on a single channel frame. A peer declaring more is a
  /// memory-exhaustion attempt - the link is torn down.
  static const int maxFrameBytes = 1 << 20;

  static final List<int> _frameMacDomain = utf8.encode('alx-mesh-frame:v1');

  static Uint8List _hmacSha256(List<int> key, List<int> msg) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(msg).bytes);

  /// HKDF-SHA256 (RFC 5869 extract+expand), 32-byte output.
  static Uint8List _hkdfSha256({
    required List<int> salt,
    required List<int> ikm,
    required List<int> info,
    int length = 32,
  }) {
    final prk = _hmacSha256(salt, ikm);
    final out = BytesBuilder();
    var t = <int>[];
    var counter = 1;
    while (out.length < length) {
      t = _hmacSha256(prk, [...t, ...info, counter]);
      out.add(t);
      counter++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  /// Derives the channel key both ends compute from a completed
  /// handshake: HKDF-SHA256 keyed/mixed by the ephemeral shared secret
  /// (unknown to handshake observers) over the transcript (binds the
  /// key to this dial). Public so the responder path ([serveHandshake]'s
  /// session-bound callback) and tests can recompute it.
  static Uint8List deriveSessionKey(MeshHandshakeTicket ticket) => _hkdfSha256(
        salt: ticket.sharedSecret,
        ikm: ticket.transcriptBytes,
        info: utf8.encode('alexandria:mesh-channel:v1'),
      );

  static Uint8List _frameMac(
      Uint8List key, int seq, List<int> payload, int direction) {
    final seqBytes = ByteData(_frameSeqLen)..setUint64(0, seq);
    return _hmacSha256(key, [
      ..._frameMacDomain,
      direction,
      ...seqBytes.buffer.asUint8List(),
      ...payload,
    ]);
  }

  /// Encodes a channel frame under [key] at sequence [seq]. Static so
  /// the peer side (and tests) can interop with [_attemptSend]'s wire
  /// format. [direction] is the MAC-domain direction tag: it defaults
  /// to responder→dialer - the direction any *inbound* frame takes on
  /// a dialer-side channel, which is what test-constructed frames
  /// simulate.
  static Uint8List encodeFrame(Uint8List key, int seq, Uint8List payload,
          [int direction = _dirResponderToDialer]) =>
      (BytesBuilder()
            ..add((ByteData(_frameSeqLen)..setUint64(0, seq))
                .buffer
                .asUint8List())
            ..add(payload)
            ..add(_frameMac(key, seq, payload, direction)))
          .toBytes();

  /// Seeds the well-known bootstrap/relay addresses.
  ///
  /// HONESTY: these are *candidate* endpoints, not proven peers. They
  /// start `isReachable: false` with `isPending: true` and
  /// `latencyMs: 0` - no reachability or latency is claimed until a
  /// real handshake (e.g. [connectToPeer]) completes. Callers should
  /// treat them as dial targets, not as active peers.
  void bootstrapDefaultPeers() {
    final defaultBootstrap = [
      MeshPeer(
        peerId: 'QmBootstrapNode1AlexandriaAlpha',
        address:
            '/dns4/node1.alexandria.network/tcp/4001/p2p/QmBootstrapNode1AlexandriaAlpha',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmBootstrapNode2AlexandriaBeta',
        address:
            '/dns4/node2.alexandria.network/tcp/4001/p2p/QmBootstrapNode2AlexandriaBeta',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmRelayNodeEuropeanLibraryCommons',
        address:
            '/dns4/relay.alexandria.network/tcp/4001/p2p/QmRelayNodeEuropeanLibraryCommons',
        tier: TransportTier.circuitRelay,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmLocalMeshDiscoveryRelay',
        address: '/ip4/127.0.0.1/tcp/4001/p2p/QmLocalMeshDiscoveryRelay',
        tier: TransportTier.lanMdns,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
    ];

    for (final peer in defaultBootstrap) {
      if (!_peers.containsKey(peer.peerId)) {
        _peers[peer.peerId] = peer;
      }
    }
  }

  Stream<MeshPeer> get onPeerDiscovered => _peerDiscoveryController.stream;
  Stream<Uint8List> get onPayloadReceived => _incomingPayloadController.stream;
  Stream<List<MeshPeer>> get peerListStream => _peerListController.stream;

  List<MeshPeer> get activePeers =>
      _peers.values.where((p) => p.isReachable).toList();

  List<MeshPeer> get peers => List.unmodifiable(_peers.values);

  /// (round-3 red finding) Reachability is PROOF, not a caller claim.
  /// A wire/UI-supplied `isReachable` flag is dropped: a registered peer
  /// enters unproven and only a successful [connectToPeer] handshake
  /// marks it reachable. An existing record keeps its proven status
  /// only when the re-registered address is identical - a changed
  /// address invalidates the handshake binding (a swapped address could
  /// otherwise smuggle an unproven endpoint in under a proven peerId).
  void registerPeer(MeshPeer peer) {
    final existing = _peers[peer.peerId];
    final stillProven = existing != null &&
        existing.isReachable &&
        existing.address == peer.address;
    final admitted = peer.copyWith(
      isReachable: stillProven,
      isPending: !stillProven,
    );
    _peers[peer.peerId] = admitted;
    // A re-registration that keeps the SAME proven address also keeps
    // its handshake-bound channel; any other admission is unproven and
    // must not inherit channel state (the channel is bound to the
    // transcript of a specific dial to a specific multiaddr).
    if (!stillProven) {
      _dropChannel(peer.peerId);
    }
    _peerDiscoveryController.add(admitted);
    _emitPeerList();
  }

  void unregisterPeer(String peerId) {
    _peers.remove(peerId);
    _dropChannel(peerId);
    _emitPeerList();
  }

  void setTierEnabled(TransportTier tier, bool enabled) {
    if (enabled) {
      _activeTiers.add(tier);
    } else {
      _activeTiers.remove(tier);
    }
    _emitPeerList();
  }

  bool isTierEnabled(TransportTier tier) => _activeTiers.contains(tier);

  TransportTier? selectBestTransport(String peerId) {
    final peer = _peers[peerId];
    if (peer == null || !peer.isReachable) return null;
    return _bestTierFor(peer);
  }

  /// Picks the peer's own tier when enabled, else falls back through
  /// the tier priority cascade. Returns null when no tier is active.
  TransportTier? _bestTierFor(MeshPeer peer) {
    if (_activeTiers.contains(peer.tier)) return peer.tier;

    // Fallback tier priority cascade
    for (final candidate in TransportTier.values) {
      if (_activeTiers.contains(candidate)) return candidate;
    }
    return null;
  }

  /// Attempts to send [data] to [peerId] over the handshake-bound
  /// channel.
  ///
  /// Returns `false` when the peer is unknown, not currently reachable
  /// (i.e. no handshake has proven it - including unproven bootstrap
  /// candidates and peers whose probe just failed), has no channel
  /// binding, or when no transport tier is available.
  ///
  /// (round-5 residual closure) [data] never goes out bare: it is
  /// framed as `seq ‖ payload ‖ HMAC-SHA256(channelKey, …)` under the
  /// key derived from the handshake transcript, so frames cannot be
  /// forged or replayed by a relay that merely observed/passed the
  /// handshake. The default transport writes the frame
  /// length-prefixed to the peer's handshake socket (frame dispatch
  /// residual closure); `true` still means "the MAC'd frame was
  /// handed to the wire", not "delivery acknowledged" - transport
  /// ACKs remain a separate milestone.
  Future<bool> sendPayload(String peerId, Uint8List data) =>
      _attemptSend(peerId, data);

  /// Whether a handshake-derived channel exists for [peerId]. This is
  /// the gate [sendPayload]/[receiveFrame] apply on top of
  /// `isReachable`: reachability proves the peer answered once, the
  /// channel proves the traffic belongs to that handshake.
  bool hasChannelBinding(String peerId) => _channels.containsKey(peerId);

  /// Dispatch gate for [sendPayload]: only proven `isReachable` peers
  /// WITH a live channel may carry payload traffic. Reachability itself
  /// is established exclusively by the [connectToPeer] handshake probe -
  /// payload sends can never bootstrap a peer into the reachable set.
  Future<bool> _attemptSend(String peerId, Uint8List data) async {
    final peer = _peers[peerId];
    if (peer == null || !peer.isReachable) return false;
    final channel = _channels[peerId];
    // A reachable peer without a channel cannot happen through the
    // public API (channels are installed by the same write-back that
    // marks reachability) - this is defense in depth, not bookkeeping.
    if (channel == null) return false;
    final direction =
        channel.responderSide ? _dirResponderToDialer : _dirDialerToResponder;
    final frame = encodeFrame(channel.key, channel.sendSeq, data, direction);
    // The sequence is consumed whether or not dispatch reports
    // success - a "failed" send may still have hit the wire, and
    // re-using a seq for different bytes reads as a replay attack to
    // the receiver.
    channel.sendSeq++;
    return _frameTransport(peerId, frame);
  }

  /// The default frame dispatcher: writes the frame to the peer's
  /// handshake socket as `len(4, big-endian) ‖ frame` - the same
  /// TCP connection that carried HELLO/ACK carries channel traffic,
  /// so frames inherit the socket's liveness (close → demotion, see
  /// [_handleSocketGone]).
  ///
  /// Channels built from injected/synthetic tickets carry no socket -
  /// for them this keeps the documented routing-stub semantics:
  /// `true` means "a tier route exists", never "delivered".
  Future<bool> _dispatchFrame(String peerId, Uint8List frame) async {
    final peer = _peers[peerId];
    if (peer == null || !peer.isReachable) return false;
    if (frame.length > maxFrameBytes) return false;
    final channel = _channels[peerId];
    if (channel == null) return false;
    final socket = channel.socket;
    if (socket == null) {
      return _bestTierFor(peer) != null;
    }
    try {
      socket.add((BytesBuilder()
            ..add((ByteData(_framePrefixLen)..setUint32(0, frame.length))
                .buffer
                .asUint8List())
            ..add(frame))
          .toBytes());
      await socket.flush();
      return true;
    } catch (_) {
      // The write side of the handshake socket is dead - demote the
      // failed address under the round-6 TOCTOU rules.
      _handleSocketGone(peerId, channel, peer.address);
      return false;
    }
  }

  /// Attaches the frame pump: the handshake socket becomes the
  /// channel's transport, parsing `len ‖ frame` chunks into
  /// [receiveFrame]. Byte loss between the handshake line read and
  /// this attach is impossible - the ticket's broadcast stream pauses
  /// the underlying socket while it has no listeners.
  void _attachSocket(
      String peerId, _MeshChannel channel, MeshHandshakeTicket ticket) {
    final socket = ticket.socket;
    final stream = ticket.socketStream;
    if (socket == null || stream == null) return;
    channel.socket = socket;
    channel.socketSub = stream.listen(
      (chunk) => _onSocketChunk(peerId, channel, ticket.multiaddr, chunk),
      onError: (_) => _handleSocketGone(peerId, channel, ticket.multiaddr),
      onDone: () => _handleSocketGone(peerId, channel, ticket.multiaddr),
      cancelOnError: true,
    );
  }

  /// Accumulates socket bytes into the channel's reassembly buffer and
  /// drains every complete `len(4 BE) ‖ frame` unit through
  /// [receiveFrame] (MAC + sequence verification happen there - this
  /// pump never releases plaintext itself).
  void _onSocketChunk(
      String peerId, _MeshChannel channel, String multiaddr, List<int> chunk) {
    final buf = channel.rxBuf;
    buf.addAll(chunk);
    while (buf.length >= _framePrefixLen) {
      final declared = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
      if (declared > maxFrameBytes) {
        // Protocol violation / memory-exhaustion attempt - tear the
        // link down rather than buffer toward an unbounded frame.
        _handleSocketGone(peerId, channel, multiaddr);
        return;
      }
      if (buf.length < _framePrefixLen + declared) {
        return; // partial frame - wait for more bytes
      }
      final frame = Uint8List.fromList(
          buf.sublist(_framePrefixLen, _framePrefixLen + declared));
      buf.removeRange(0, _framePrefixLen + declared);
      unawaited(receiveFrame(peerId, frame));
    }
  }

  /// The handshake socket died (close, error, or a failed write).
  /// Round-6 TOCTOU rules apply verbatim: re-read the peer row after
  /// the async gap and demote ONLY when the dead socket's channel is
  /// still the installed one AND the record still points at the
  /// address this socket was dialed to - a re-registered or re-dialed
  /// record (different address, or a fresher channel) is left alone.
  void _handleSocketGone(
      String peerId, _MeshChannel channel, String multiaddr) {
    final wasCurrent = identical(_channels[peerId], channel);
    if (wasCurrent) {
      _dropChannel(peerId);
    } else {
      // Stale socket (a newer channel replaced it) - just clean up.
      channel.socketSub?.cancel();
      channel.socket?.destroy();
    }
    final current = _peers[peerId];
    if (wasCurrent &&
        current != null &&
        current.address == multiaddr &&
        current.isReachable) {
      _peers[peerId] = current.copyWith(isReachable: false);
      _emitPeerList();
    }
  }

  /// Removes the channel and tears down its transport: the pump
  /// subscription is cancelled and the handshake socket destroyed.
  /// Centralizes what raw `_channels.remove` used to leak.
  void _dropChannel(String peerId) {
    final channel = _channels.remove(peerId);
    if (channel != null) {
      channel.socketSub?.cancel();
      channel.socket?.destroy();
    }
  }

  /// Inbound half of the channel: verifies a frame's MAC and sequence
  /// against the handshake-bound key, then emits the payload on
  /// [onPayloadReceived].
  ///
  /// Returns false - releasing nothing - when the peer is unknown or
  /// unproven, has no channel, the frame is truncated, the MAC fails
  /// (forged or wrong-key input), or the sequence is not ahead of the
  /// last accepted one (replay/drop).
  Future<bool> receiveFrame(String peerId, Uint8List frame) async {
    final peer = _peers[peerId];
    final channel = _channels[peerId];
    if (peer == null || !peer.isReachable || channel == null) {
      return false;
    }
    if (frame.length < _frameSeqLen + _frameMacLen) return false;
    final seq = ByteData.sublistView(frame, 0, _frameSeqLen).getUint64(0);
    final payload = frame.sublist(_frameSeqLen, frame.length - _frameMacLen);
    final mac = frame.sublist(frame.length - _frameMacLen);
    // Inbound frames travel the OPPOSITE direction to our sends - a
    // reflected copy of our own outbound frame fails this MAC.
    final direction =
        channel.responderSide ? _dirDialerToResponder : _dirResponderToDialer;
    final expected = _frameMac(channel.key, seq, payload, direction);
    // Constant-time tag compare - a mismatch is forged/tampered input
    // and is rejected BEFORE any plaintext is released.
    var diff = 0;
    for (var i = 0; i < _frameMacLen; i++) {
      diff |= mac[i] ^ expected[i];
    }
    if (diff != 0) return false;
    if (seq <= channel.recvSeq) return false; // replayed or out-of-order drop
    channel.recvSeq = seq;
    if (!_incomingPayloadController.isClosed) {
      _incomingPayloadController.add(Uint8List.fromList(payload));
    }
    return true;
  }

  Stream<List<MeshPeer>> watchPeers() async* {
    yield peers;
    yield* _peerListController.stream;
  }

  Future<bool> connectToPeer(String multiaddr) async {
    final peerId = _peerIdFromMultiaddr(multiaddr);
    if (peerId == null || peerId.isEmpty) return false;

    MeshPeer? peer = _peers[peerId];
    if (peer == null) {
      peer = MeshPeer(
        peerId: peerId,
        address: multiaddr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
      );
      _peers[peerId] = peer;
    }

    // Mark dial-in-progress - but (round-4 red finding) do NOT strip a
    // proven record's reachability up front, and on failure only demote
    // when the probed address IS the proven one. A failed handshake to
    // a DIFFERENT address says nothing about the proven endpoint, so a
    // poisoned multiaddr announcement can never revoke an honest peer's
    // routing (demotion-poisoning DoS).
    final pendingSnapshot = peer.copyWith(isPending: true);
    _peers[peerId] = pendingSnapshot;
    _emitPeerList();

    final stopwatch = Stopwatch()..start();
    // Real handshake attempt: the probe must observe the remote endpoint
    // answer. No tier/bookkeeping shortcut - a peer enters `isReachable`
    // only on proof, so phantom/Sybil addresses cannot inflate
    // activePeers or unlock selectBestTransport/sendPayload (round-2
    // red finding).
    bool ok;
    MeshHandshakeTicket? ticket;
    try {
      ticket = await _sessionProbe(multiaddr).timeout(handshakeTimeout);
      ok = ticket != null;
    } catch (_) {
      ok = false;
    }
    stopwatch.stop();

    // (round-6 red finding) TOCTOU: the peer map may have changed while
    // the async probe was in flight. Writing back the T0 snapshot
    // unconditionally RESURRECTED a peer revoked by unregisterPeer -
    // marked isReachable, the only gate on sendPayload - and clobbered
    // fresher records from disconnectPeer/registerPeer. Re-read the map
    // and write back ONLY if the record is still the pending snapshot
    // we installed; otherwise the newer owner manages the state.
    final current = _peers[peerId];
    if (current == null) {
      // Removed mid-probe - a completed handshake must not resurrect
      // it, and its socket must not leak as a live transport.
      ticket?.socket?.destroy();
      return ok;
    }
    if (!identical(current, pendingSnapshot)) {
      // disconnectPeer/registerPeer/unregisterPeer touched the record -
      // keep the newer state, drop our stale write-back entirely.
      ticket?.socket?.destroy();
      return ok;
    }

    if (ok) {
      _peers[peerId] = current.copyWith(
        address: multiaddr,
        isPending: false,
        isReachable: true,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      // (round-5 residual closure) bind the channel to THIS handshake:
      // the key derives from the transcript the probe just completed.
      // The install happens only on the identical-snapshot write-back,
      // so a revoked/re-registered peer can never inherit the channel
      // (same TOCTOU bound as the reachability write). A previous
      // channel (re-dial of the same peerId) is dropped first - its
      // socket is torn down via _dropChannel, and its demotion path
      // is disarmed because it is no longer the installed channel.
      _dropChannel(peerId);
      final channel = _MeshChannel(
        deriveSessionKey(ticket!),
        responderSide: ticket.responderSide,
        transcriptBound: ticket.transcriptBound,
      );
      _channels[peerId] = channel;
      // The handshake socket becomes the frame transport.
      _attachSocket(peerId, channel, ticket);
    } else if (peer.isReachable && peer.address != multiaddr) {
      // Failed probe of a NEW address - the proven record stands, and
      // so does its channel (bound to the still-valid handshake).
      _peers[peerId] = current.copyWith(isPending: false);
    } else {
      // Unproven peer, or the proven address itself now fails.
      _peers[peerId] = current.copyWith(isPending: false, isReachable: false);
      _dropChannel(peerId);
    }
    _emitPeerList();
    return ok;
  }

  Future<void> disconnectPeer(String peerId) async {
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(isReachable: false, isPending: false);
      _dropChannel(peerId);
      _emitPeerList();
    }
  }

  String? _peerIdFromMultiaddr(String multiaddr) =>
      _peerIdFromMultiaddrStatic(multiaddr);

  static String? _peerIdFromMultiaddrStatic(String multiaddr) {
    final match = RegExp(r'/p2p/([^/]+)$').firstMatch(multiaddr);
    return match?.group(1);
  }

  void _emitPeerList() {
    if (!_peerListController.isClosed) {
      _peerListController.add(peers);
    }
  }

  void dispose() {
    for (final peerId in _channels.keys.toList()) {
      _dropChannel(peerId);
    }
    _peerDiscoveryController.close();
    _incomingPayloadController.close();
    _peerListController.close();
  }
}

/// Per-peer post-handshake channel state (round-5 residual closure):
/// the HKDF-derived key plus per-direction sequence cursors. [sendSeq]
/// is consumed monotonically (even on dispatch failure - a "failed"
/// send may have reached the wire); [recvSeq] records the highest
/// accepted inbound sequence so replays and stale frames are dropped.
/// In-memory only: a process restart re-handshakes anyway, so there is
/// nothing durable to leak.
///
/// [socket]/[socketSub]/[rxBuf] are the wire transport (frame
/// dispatch residual closure): the handshake socket is retained as
/// the frame carrier, [rxBuf] reassembles `len ‖ frame` units across
/// arbitrary chunk boundaries, and socket teardown flows through
/// [MeshTransportService._handleSocketGone]'s demotion rules.
class _MeshChannel {
  _MeshChannel(this.key,
      {required this.responderSide, required this.transcriptBound});

  final Uint8List key;

  /// Which side of the handshake this service holds - fixes the
  /// direction tag this channel SENDS under and the one it accepts.
  final bool responderSide;

  /// False only for synthetic-ticket channels (injected bool probes):
  /// the key binds this dial's material but no peer can recompute it.
  final bool transcriptBound;

  /// The live handshake socket (null for injected-probe channels -
  /// those dispatch through the routing-stub fallback instead).
  Socket? socket;

  /// The frame pump subscription on the ticket's broadcast stream.
  StreamSubscription<Uint8List>? socketSub;

  /// Reassembly buffer for `len ‖ frame` units split across chunks.
  final List<int> rxBuf = <int>[];

  int sendSeq = 0;
  int recvSeq = -1;
}
