import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_network.dart';
import '../../data/database.dart' show AppDatabase, databaseProvider;
import '../build_info_service.dart';
import '../credits/credit_models.dart' show CreditTransaction, CreditType;
import '../credits/credit_service.dart';
import '../credits/work_receipt.dart';
import '../ipfs_service.dart';
import '../mesh_transport_service.dart';
import '../release/release_manifest.dart';
import '../release/release_manifest_authority.dart';
import '../release/release_providers.dart';
import 'beacon_models.dart';
import 'bounty_claim_event.dart';
import 'bounty_id_canonicalization.dart';
import 'escrow_attestation.dart';
import 'mesh_bounty_transport.dart';

/// Outcome of [MoltbookService.releaseBountyEscrow] - the poster-side
/// evidence-checked escrow-release rail (cross-ledger payout).
enum BountyEscrowRelease {
  /// The escrow was released INTO a verified claim/settlement record -
  /// durably consumed (spent tombstone), never refunded. This is the
  /// settlement direction: the claimant's payout already minted on its
  /// own ledger and our consumed hold is its backing.
  settledToVerifiedClaim,

  /// The escrow hold was refunded to the poster via
  /// [CreditService.releaseEscrow] - reachable only through the
  /// explicit `operatorReconciliation` override with no verified
  /// claim/settlement record present.
  refunded,

  /// Release refused: not a locally escrowed id, already released, a
  /// settlement-state probe failed, or the refund found no hold.
  refused,

  /// Release refused: no verified claim/settlement record exists and
  /// no operator reconciliation was asserted - an announced escrow can
  /// never prove it was not claimed on a remote ledger.
  refusedUnproven,
}

/// Riverpod provider for MoltbookService
final moltbookServiceProvider = ChangeNotifierProvider<MoltbookService>((ref) {
  final creditService = ref.read(creditServiceProvider);
  return MoltbookService(
    creditService: creditService,
    ipfsService: ref.read(ipfsServiceProvider),
    // Durable bounty-claim dedup (REV3 review): the claimed_bounties
    // ledger makes a won claim restart-proof and unreachable through
    // any returned bounty copy.
    db: ref.read(databaseProvider),
    // Production BountyTransport: bounty announcements, signed claim
    // events and release manifests ride the MAC'd mesh channel layer -
    // every outbound envelope is fanned out to proven peers, every
    // inbound payload re-enters through the signature-checked ingest
    // gates (the transport is never trusted).
    bountyTransport:
        MeshBountyTransport(ref.read(meshTransportServiceProvider)),
    // ALX-012 §5.1 machinery: the release manifest authority (empty
    // registry by default - fails closed until a quorum is configured
    // via releaseKeyRegistryProvider, the RFC's trigger condition i).
    releaseManifestAuthority: ref.read(releaseManifestAuthorityProvider),
  );
});

/// Service managing social agent transport, Moltbook submolt feeds, and Beacon v2 envelopes (ALX-006)
class MoltbookService extends ChangeNotifier {
  final CreditService _creditService;
  final IpfsService? _ipfsService;
  final AppDatabase? _db;

  /// Ambient trust root for funding attestations (REV3 review Safety
  /// fix). This used to be a per-call `trustedAttestors` parameter on
  /// [ingestBountyAnnouncement] - a footgun that let every future
  /// transport call site weaken policy by passing announcement-derived
  /// keys. Now it is node configuration, frozen (unmodifiable) at
  /// construction; the default EMPTY set fails closed, so no
  /// attestation is ever trusted until the operator configures the
  /// node's attestor quorum.
  final Set<String> _trustedAttestorPubkeys;

  final String _baseUrl;
  String? _apiKey;

  /// Optional remote transport (the deferred-milestone seam): when
  /// injected, inbound envelopes stream into [ingestBountyEnvelope] /
  /// [ingestBountyClaimEnvelope] and outbound announcements/claim events
  /// are published through it. The verification+attribution layer is
  /// complete and exercised here; what remains external is a concrete
  /// networked [BountyTransport] implementation.
  final BountyTransport? _bountyTransport;
  StreamSubscription<BeaconEnvelope>? _transportSubscription;

  /// Optional release manifest authority (ALX-012 §5.1 machinery):
  /// when injected, `release_manifest` envelopes arriving over
  /// [_bountyTransport] are routed into its verification chain - the
  /// signed-manifest transport binding the RFC's trigger condition (ii)
  /// names. Null by default: no authority means manifest envelopes are
  /// dropped like every other non-bounty kind.
  final ReleaseManifestAuthority? _manifestAuthority;

  /// Verified remote claim events keyed by NFD-normalized bounty id.
  /// Insertion-ordered; oldest evicts first at capacity so a claim-event
  /// flood cannot grow memory without bound (same DoS class as the
  /// bounty registry cap).
  final Map<String, BountyClaimEvent> _remoteClaims = {};
  static const int _maxRemoteClaims = 512;

  /// Normalized ids carrying at least one verified remote claim -
  /// settlement evidence for the cancel path: a verified remote claim
  /// means the escrow is spoken for even when the registry record is
  /// gone (post-restart), so [cancelBounty] must refuse it.
  final Set<String> _remoteClaimedBountyIds = {};

  /// Normalized ids whose `originAgentId` was attributed to a verified
  /// envelope signer through [ingestBountyEnvelope] - these ids arrived
  /// over a signature-checked channel; records ingested through raw
  /// [ingestBountyAnnouncement] stay unattributed by construction.
  final Set<String> _verifiedOriginBountyIds = {};
  static const int _maxVerifiedOriginIds = 4096;

  SimpleKeyPair? _keyPair;
  String _pubkeyHex = '';
  String _agentId = '';

  DateTime? _lastPostTime;
  static const Duration postingCooldown = Duration(minutes: 30);

  final Map<String, List<MoltbookPost>> _submoltPosts = {
    AppNetwork.submolt('alexandria-bounties'): [],
    AppNetwork.submolt('open-science'): [],
    AppNetwork.submolt('preservation-alerts'): [],
  };

  final List<PreservationBounty> _bounties = [];

  /// Hard cap on the bounty registry (REV4 review / Safety 4A): once a
  /// transport exists, unbounded ingest is a remote memory-DoS - a
  /// flooding announcer could grow the list without limit. At capacity,
  /// eviction prefers the oldest UNFUNDED record (no escrow evidence
  /// behind it); a FUNDED (attested) incoming announcement may displace
  /// the oldest funded record, while an unfunded one is dropped when
  /// every stored record is funded - unattested spam can never evict
  /// claimable escrow-backed bounties.
  ///
  /// LOCAL ESCROW PROTECTION (E-REV4b F7): a record whose id is in
  /// [_locallyPostedBountyIds] is NEVER evicted - its escrow hold sits
  /// on OUR ledger, and losing the record would strand the refund:
  /// [cancelBounty] could no longer reach it while the hold stayed
  /// locked. If every stored record is locally protected, the incoming
  /// announcement is dropped instead.
  static const int _maxBounties = 512;

  /// Durable payout-row id prefix - must mirror
  /// `CreditService._kBountyPayoutTxPrefix`, which is private to that
  /// service. The persisted payout row is the "claim durably settled"
  /// proof the crash-window reconciler probes by primary key.
  static const String _bountyPayoutTxPrefix = 'tx_bounty_payout_';

  /// Durable escrow-release row id prefix - must mirror
  /// `CreditService._kEscrowReleaseTxPrefix`, which is private to that
  /// service. A claim whose payout-row write was LOST writes a
  /// zero-amount tombstone under this prefix: CreditService hydration
  /// rebuilds its `_releasedEscrowIds` dedup set from persisted
  /// `tx_escrow_release_*` rows, so the tombstone makes the bounty id
  /// permanently un-payable AND un-refundable across restarts - the
  /// durable fix for the E-REV4b E1 double-pay window.
  static const String _escrowReleaseTxPrefix = 'tx_escrow_release_';

  /// Durable escrow-hold row id prefix - must mirror
  /// `CreditService._kEscrowHoldTxPrefix`, which is private to that
  /// service. Every locally escrowed bounty leaves a durable hold row,
  /// so the prefix listing rebuilds [_locallyPostedBountyIds] and
  /// [_escrowedBountyIds] after a restart (RE-REV4b E1).
  static const String _escrowHoldTxPrefix = 'tx_escrow_hold_';

  /// Default bound on the durable payout write (E-REV4b F6 carried
  /// forward): a wedged `insertCreditTransactionIfAbsent` must never
  /// park a won claim forever while holding the in-flight mark AND the
  /// durable claim row - that bricks the bounty for the process.
  /// [claimBounty] awaits `awardBountyEscrowDurable` under a
  /// `.timeout(_payoutWriteTimeout)`; expiry takes the
  /// indeterminate-write path (spent tombstone + standing claim row -
  /// the id is dead whether the queued CAS lands late or never).
  /// Injectable for tests via the `payoutWriteTimeout` constructor
  /// argument.
  static const Duration _maxPayoutSettleWait = Duration(seconds: 30);

  /// A claim row older than this WITHOUT a durable payout row is
  /// treated as stale/orphaned - either a crash stranded it between the
  /// CAS and the payout, or a claim-release delete threw. Such rows are
  /// deleted and the CAS retried (claim path) or swept (startup). A
  /// younger row can still be a genuinely in-flight claim, so it is
  /// left alone.
  static const Duration _claimRowTtl = Duration(minutes: 15);

  /// Envelope kinds that may carry a [PreservationBounty] payload
  /// through [ingestBountyEnvelope]: `preservation_bounty` is the
  /// dedicated wire kind for transports that route bounty
  /// announcements; `moltbook_post` is how [postPreservationBounty]
  /// broadcasts today (bounty fields ride the post payload). Unknown
  /// kinds fail closed.
  static const Set<String> bountyEnvelopeKinds = {
    'preservation_bounty',
    'moltbook_post',
  };

  /// IDs of bounties escrowed by THIS node via [postPreservationBounty].
  /// The self-claim guard keys off this set - not the mutable [_agentId] -
  /// so rotating the local keypair can never launder a self-claim on our
  /// own escrow (ALX-010 / E-T5 #2).
  final Set<String> _locallyPostedBountyIds = {};

  /// Bounty ids whose escrow hold actually landed via
  /// [CreditService.debitEscrow] - every locally-posted bounty by
  /// construction (postPreservationBounty throws otherwise), tracked
  /// separately so [cancelBounty] can distinguish "release refused"
  /// (return false) from "nothing was ever held" (return true).
  final Set<String> _escrowedBountyIds = {};

  /// In-flight claim guard (single-isolate TOCTOU): an id is added
  /// synchronously before [claimBounty]'s first `await`, so a second
  /// overlapping call observes it and bails before the durable CAS can
  /// even run. Entries are removed on every failure path; a won claim
  /// keeps its entry as a fast-path alongside the durable row.
  final Set<String> _claimedBountyIds = {};

  /// Permanent tombstone for ids whose local bounty was CANCELLED
  /// (E-REV4b F1): a cancelled id must never be re-animated - its escrow
  /// was refunded, so a claim paying it out mints unbacked value.
  /// [_locallyPostedBountyIds] is never shrunk by [cancelBounty], so it
  /// doubles as the tombstone for ingest drops and the self-claim
  /// guard; this set additionally records the id's terminal state so a
  /// re-ingested record is stored provably UNFUNDED and [claimBounty]
  /// refuses it even if a record slips through. The durable half of the
  /// protection lives in CreditService: `awardBountyEscrow` refuses ids
  /// whose `tx_escrow_release_` row exists.
  final Set<String> _cancelledBountyIds = {};

  /// In-flight cancel serialization (E-REV4b F3): an id is added only
  /// AFTER the durable claim-state await completes, then re-validated
  /// state is committed synchronously, so two overlapping
  /// [cancelBounty] calls cannot both observe "unclaimed" and both
  /// remove + refund. Removed in a `finally` so an exception cannot
  /// leak the mark.
  final Set<String> _cancellingBountyIds = {};

  /// Escrow ids whose `tx_escrow_release_<id>` spent-tombstone write has
  /// been ATTEMPTED but not yet proven durable (RE-REV4b F): the
  /// tombstone row is the ONLY durable record that a lost payout-row
  /// write ever happened, so losing BOTH writes in one fault window
  /// lets a restart re-pay the escrow (the E1 double-pay resurrected
  /// through the tombstone's own failure path). Pending ids are retried
  /// at service init and on every [claimBounty] entry.
  ///
  /// The map value is the tombstone row's human-readable reason -
  /// currently two settlement causes share the row shape: a lost
  /// payout-row write (claimant-side, RE-REV4b F2) and a verified
  /// remote-claim settlement (poster-side payout rail). Both assert the
  /// same invariant - "this escrow is spent; never pay or refund".
  ///
  /// The map is keyed by the SHARED [AppDatabase] handle rather than by
  /// service instance: a freshly-constructed MoltbookService on the
  /// same database retries tombstones a previous incarnation
  /// registered - which is what makes the retry meaningful across a
  /// service-layer restart. An [Expando] is used so the mapping never
  /// pins a database past its own lifetime (important in tests, which
  /// create and close many databases in one process).
  static final Expando<Map<String, String>> _pendingReleaseTombstones =
      Expando<Map<String, String>>('pendingReleaseTombstones');

  /// Completes when the locally-posted / cancelled / escrowed id sets
  /// have been rebuilt from durable ledger rows
  /// ([_restoreLocalBountyState]). [cancelBounty] and
  /// [postPreservationBounty] await it so a call issued immediately
  /// after construction still sees the restored state - the escrow hold
  /// rows outlive the process, so the paths that act on them must too.
  late final Future<void> _localStateReady;

  /// Bound on the durable payout CAS inside [claimBounty] - see
  /// [_maxPayoutSettleWait]. Constructor-injectable so tests can model
  /// a wedged ledger write without a 30-second wait.
  final Duration _payoutWriteTimeout;

  MoltbookService({
    required CreditService creditService,
    IpfsService? ipfsService,
    AppDatabase? db,
    Set<String> trustedAttestorPubkeys = const {},
    BountyTransport? bountyTransport,
    ReleaseManifestAuthority? releaseManifestAuthority,
    Duration payoutWriteTimeout = _maxPayoutSettleWait,
    String baseUrl = 'https://www.moltbook.com',
    String? apiKey,
  })  : _creditService = creditService,
        _ipfsService = ipfsService,
        _db = db,
        _bountyTransport = bountyTransport,
        _manifestAuthority = releaseManifestAuthority,
        _payoutWriteTimeout = payoutWriteTimeout,
        // Frozen copy: the caller must not be able to grow the trust
        // root after construction by mutating the set it handed in.
        _trustedAttestorPubkeys = Set.unmodifiable(trustedAttestorPubkeys),
        _baseUrl = baseUrl,
        _apiKey = apiKey {
    _initKey();
    // Startup reconciliation (REV4 review): heal claim rows nobody will
    // ever retry - the in-claimBounty healer only runs when a claim is
    // attempted, so a stranded row for a bounty nobody claims again
    // would block head-of-line forever. Fire-and-forget; gated on
    // _db != null inside the sweep. Also flushes pending escrow-spent
    // tombstones (RE-REV4b F).
    unawaited(_reconcileClaimedBounties());
    // RE-REV4b E1: rebuild the locally-posted/cancelled/escrowed id sets
    // from durable hold/release rows - without it a cancelled id
    // re-ingests as a FUNDED zombie and a live locally-posted bounty is
    // un-cancellable after a restart. Stored so [cancelBounty] and
    // [postPreservationBounty] can await the rebuild before acting.
    _localStateReady = _restoreLocalBountyState();

    // Remote transport (verified bounty claim events milestone): every
    // inbound envelope funnels through the signature-checked ingest
    // paths - the transport itself is never trusted.
    final transport = _bountyTransport;
    if (transport != null) {
      _transportSubscription = transport.envelopes.listen((envelope) {
        unawaited(_routeTransportEnvelope(envelope));
      });
    }
  }

  /// Transport-frame routing: claim events and bounty announcements get
  /// separate verification paths; every ingest gate fails closed by
  /// dropping, so a malformed or hostile frame can never surface as an
  /// unhandled stream error.
  Future<void> _routeTransportEnvelope(BeaconEnvelope envelope) async {
    try {
      if (envelope.kind == BountyClaimEvent.envelopeKind) {
        await ingestBountyClaimEnvelope(envelope);
      } else if (envelope.kind == ReleaseManifest.envelopeKind) {
        // release manifest channel (ALX-012 §5.1): routed only when an
        // authority is injected - the envelope itself is unsigned
        // metadata until the authority's threshold chain evaluates it.
        await _manifestAuthority?.ingestEnvelope(envelope);
      } else {
        await ingestBountyEnvelope(envelope);
      }
    } catch (_) {}
  }

  /// Best-effort envelope broadcast - publication failure must never
  /// fail a completed ledger operation (the durable ledger rows, not
  /// the announcement, are the settlement record).
  void _publishEnvelope(BeaconEnvelope? envelope) {
    final transport = _bountyTransport;
    if (transport == null || envelope == null) return;
    unawaited(() async {
      try {
        await transport.publish(envelope);
      } catch (_) {}
    }());
  }

  /// Signs and broadcasts a [BountyClaimEvent] for a won claim - the
  /// claimant-side half of the remote-claim transport: the poster's
  /// node can then verify settlement evidence instead of trusting a
  /// self-asserted `is_claimed` flag.
  Future<void> _publishClaimEvent(PreservationBounty bounty) async {
    if (_bountyTransport == null) return;
    try {
      await _ensureKeyPair();
      final event = await BountyClaimEvent.issue(
        keyPair: _keyPair!,
        bountyId: bounty.id,
        cid: bounty.cid,
      );
      final envelope = await event.toEnvelope(
        _keyPair!,
        clientInfo: BuildInfo.current().claimedBroadcastInfo,
      );
      await _bountyTransport.publish(envelope);
    } catch (_) {
      // Settlement evidence is best-effort: the claim already settled
      // on this node's durable ledger.
    }
  }

  /// The verified remote claim event recorded for [bountyId] (canonical
  /// id comparison), or null. The returned event's claimant identity is
  /// attributed to the signing key by [BountyClaimEvent.verify] - never
  /// a self-asserted string.
  BountyClaimEvent? remoteClaimFor(String bountyId) =>
      _remoteClaims[normalizeBountyId(bountyId)];

  /// Whether [bountyId] carries a verified remote claim - settlement
  /// evidence that the escrow is spoken for.
  bool isRemotelyClaimed(String bountyId) =>
      _remoteClaimedBountyIds.contains(normalizeBountyId(bountyId));

  /// Whether [bountyId]'s `originAgentId` arrived over a signature-
  /// checked envelope (attributed to a real key) rather than an
  /// unattributed raw announcement.
  bool isOriginVerified(String bountyId) =>
      _verifiedOriginBountyIds.contains(normalizeBountyId(bountyId));

  /// Adds [value] to an insertion-ordered set, evicting the oldest
  /// entry when at capacity. `LinkedHashSet` iterates in insertion
  /// order, so `set.first` is the oldest live entry.
  static void _addBounded(Set<String> set, String value, int cap) {
    if (!set.contains(value) && set.length >= cap) {
      set.remove(set.first);
    }
    set.add(value);
  }

  @override
  void dispose() {
    _transportSubscription?.cancel();
    super.dispose();
  }

  String get baseUrl => _baseUrl;
  String? get apiKey => _apiKey;
  String get agentId => _agentId;
  String get pubkeyHex => _pubkeyHex;
  DateTime? get lastPostTime => _lastPostTime;

  /// Live unclaimed bounties as DEFENSIVE COPIES (REV3 review): the
  /// stored records are never handed out, so a caller mutating a
  /// returned bounty (e.g. flipping `isClaimed` back to false) cannot
  /// reopen a claimed bounty for a second escrow payout.
  List<PreservationBounty> get activeBounties => List.unmodifiable(
      _bounties.where((b) => !b.isClaimed).map((b) => b.copyWith()));

  void setApiKey(String? key) {
    _apiKey = key?.trim();
    notifyListeners();
  }

  /// Initializes the local agent Ed25519 identity key
  Future<void> _initKey() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    // This runs concurrently with the constructor; a deliberate
    // setKeyPair that landed while newKeyPair was in flight WINS -
    // an in-flight auto-init must never clobber an explicitly provided
    // identity (it would silently rotate _pubkeyHex/_agentId out from
    // under callers that already pinned the override).
    if (_keyPair != null) return;
    _keyPair = keyPair;
    await _publishKeyMaterial(keyPair);
  }

  /// Publishes [_pubkeyHex]/[_agentId] for [keyPair] - but only if it is
  /// still the installed keypair when the extract resolves. A racing
  /// [setKeyPair] (or a second auto-init) must never let a stale
  /// continuation write key material for a key that is no longer
  /// installed: the local-key bar, echo guard, and self-claim guard all
  /// trust [_pubkeyHex]/[_agentId] to describe the SIGNING identity.
  Future<void> _publishKeyMaterial(SimpleKeyPair keyPair) async {
    final pk = await keyPair.extractPublicKey();
    if (!identical(_keyPair, keyPair)) return;
    _pubkeyHex = bytesToHex(pk.bytes);
    _agentId = BeaconEnvelope.deriveAgentId(pk.bytes);
    notifyListeners();
  }

  /// Overrides the keypair with a provided one (useful in deterministic tests)
  Future<void> setKeyPair(SimpleKeyPair keyPair) async {
    _keyPair = keyPair;
    await _publishKeyMaterial(keyPair);
  }

  /// Lazily generates the agent identity when the async [_initKey] hasn't
  /// completed yet, so callers never observe an empty [_agentId].
  Future<void> _ensureKeyPair() async {
    if (_keyPair != null) return;
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    // Same rule as _initKey: an identity explicitly installed while this
    // generation was in flight wins - never clobber it.
    if (_keyPair != null) return;
    _keyPair = keyPair;
    await _publishKeyMaterial(keyPair);
  }

  List<MoltbookPost> getPostsForSubmolt(String submolt) {
    return List.unmodifiable(_submoltPosts[AppNetwork.submolt(submolt)] ?? []);
  }

  /// Creates and broadcasts a Beacon v2 signed post to Moltbook
  Future<MoltbookPost> createPost({
    required String submolt,
    required String title,
    required String content,
    Map<String, dynamic>? payload,
    bool force = false,
  }) async {
    // 1. Enforce local 30-minute posting cooldown guard (anti-agent runaway loop)
    final now = DateTime.now();
    if (!force && _lastPostTime != null) {
      final elapsed = now.difference(_lastPostTime!);
      if (elapsed < postingCooldown) {
        final waitMinutes = (postingCooldown - elapsed).inMinutes + 1;
        throw StateError(
            'Local posting guard active: Please wait $waitMinutes minutes before posting again (or set force: true for critical emergencies).');
      }
    }

    await _ensureKeyPair();

    // Network namespacing: testnet posts carry the -testnet channel
    // name on the wire and in the local feed so a testnet post can
    // never land on a mainnet submolt.
    final scopedSubmolt = AppNetwork.submolt(submolt);

    // 2. Sign Beacon v2 envelope. The client_info claim is the NARROWED
    // broadcast subset (REV3-D review): claimed client version, build
    // channel and protocol version only - exact commit SHA, artifact
    // digest and build timestamp are high-entropy provenance that would
    // let a peer scan the swarm for known-vulnerable builds, so they
    // stay local (see BuildInfo.claimedBroadcastInfo).
    final envelope = await BeaconEnvelope.create(
      kind: 'moltbook_post',
      keyPair: _keyPair!,
      clientInfo: BuildInfo.current().claimedBroadcastInfo,
      payload: {
        'submolt': scopedSubmolt,
        'title': title,
        ...?payload,
      },
    );

    final postId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final post = MoltbookPost(
      id: postId,
      submolt: scopedSubmolt,
      title: title,
      content: content,
      authorAgentId: _agentId,
      upvotes: 1,
      timestamp: now,
      beaconEnvelope: envelope,
    );

    _submoltPosts.putIfAbsent(scopedSubmolt, () => []).insert(0, post);
    _lastPostTime = now;
    notifyListeners();

    return post;
  }

  /// Posts a preservation bounty offering Archival Credits on m/alexandria-bounties
  Future<PreservationBounty> postPreservationBounty({
    required String cid,
    String? doi,
    required String title,
    required double offeredCredits,
    String urgency = 'normal',
    bool force = false,
  }) async {
    // Reject non-positive / non-finite offers before touching the ledger -
    // a 0 or negative bounty must never be recorded as escrowed (E-T5 #4).
    if (!offeredCredits.isFinite || offeredCredits <= 0) {
      throw ArgumentError('Bounty must offer positive credits');
    }

    // Ensure identity exists BEFORE recording originAgentId - otherwise a
    // bounty posted during _initKey's async gap would carry an empty
    // origin id and corrupt the self-claim/echo checks.
    await _ensureKeyPair();
    // The dead-id check below consults [_cancelledBountyIds], which is
    // rebuilt from durable release rows - await that rebuild so a post
    // issued immediately after construction cannot land a fresh escrow
    // on an id whose tombstone hasn't been read back yet (RE-REV4b E1).
    await _localStateReady;

    // Verify node has sufficient credits to escrow bounty
    if (_creditService.balance < offeredCredits) {
      throw StateError(
          'Insufficient credit balance (${_creditService.balance.toStringAsFixed(1)} ℭ) to fund $offeredCredits ℭ bounty.');
    }

    // Dead-id guard (RE-REV4b E3): `bounty_<ms>` collides under a
    // same-millisecond post-after-cancel, and reusing a tombstoned id
    // strands the fresh escrow - cancel refuses it (already tombstoned)
    // and release/payout refuse it (the release dedup row). Regenerate
    // with a discriminator suffix; refuse outright if no live candidate
    // exists. The durable half of the check is CreditService's
    // release/payout dedup sets, rebuilt by hydration across restarts.
    var bountyId = 'bounty_${DateTime.now().millisecondsSinceEpoch}';
    for (var retry = 0; _isDeadBountyId(bountyId) && retry < 8; retry++) {
      bountyId = 'bounty_${DateTime.now().millisecondsSinceEpoch}_r$retry';
    }
    if (_isDeadBountyId(bountyId)) {
      throw StateError(
          'Generated bounty id $bountyId is tombstoned — refusing to '
          'escrow onto a dead id.');
    }

    // The generated id is canonical by construction; the check is the
    // contract, not the generator (REV4 review): a non-canonical id must
    // be refused here just as it is dropped at ingest - raw `==` id
    // comparisons are load-bearing in EscrowAttestation.bindsBounty.
    if (!_isCanonicalBountyId(bountyId)) {
      throw StateError('Generated bounty id failed the canonical check.');
    }

    final bounty = PreservationBounty(
      id: bountyId,
      cid: cid,
      doi: doi,
      title: title,
      offeredCredits: offeredCredits,
      urgency: urgency,
      originAgentId: _agentId,
      createdAt: DateTime.now(),
      funded: true, // Reward is genuinely escrowed via debitEscrow below
    );

    // Broadcast FIRST (E-T5r #2): createPost can throw (e.g. the local
    // posting cooldown) and must do so BEFORE any ledger mutation. The
    // previous debit-then-broadcast order permanently burned the escrow
    // whenever the broadcast threw - the caller saw a StateError while
    // the credits stayed locked behind a bounty nobody could claim.
    final announcementPost = await createPost(
      submolt: 'alexandria-bounties',
      title: '[BOUNTY: $urgency.toUpperCase()] $title',
      content:
          'Seeking swarm replication for endangered document.\nCID: $cid\nDOI: ${doi ?? 'N/A'}\nReward: $offeredCredits ℭ\nUrgency: $urgency',
      payload: bounty.toJson(),
      force: force,
    );

    // Debit credits into escrow. This is a fee-EXEMPT hold, not a spend:
    // the full amount is owed to the future claimant, so skimming the 5%
    // treasury fee here would mint unbacked value on payout. debitEscrow
    // keeps the post+claim cycle net-zero (ALX-010 / E-T5 #5).
    //
    // DURABLE-FIRST (optimistic-return residual - adopted): the hold row
    // commits through the insert-if-absent CAS BEFORE the balance
    // mutates, so a returned `true` provably corresponds to a
    // durably-committed `tx_escrow_hold_` row - the escrow the poster
    // announces is the escrow the ledger can prove. A write failure
    // fails closed (`false`, nothing mutated) into the StateError below.
    final escrowed = await _creditService.debitEscrowDurable(
      amount: offeredCredits,
      // The hold is keyed by the BOUNTY id - cancelBounty releases it
      // through releaseEscrow(referenceId: bountyId), and one bounty id
      // maps to exactly one escrow regardless of cid reuse.
      referenceId: bounty.id,
    );
    if (!escrowed) {
      // The broadcast already went out, but its `funded` payload flag is
      // only a claim - remote nodes strip it on ingest until an escrow
      // attestation exists - so this failed post can mint nothing.
      throw StateError('Escrow debit failed for $offeredCredits ℭ bounty.');
    }

    _bounties.insert(0, bounty);
    _locallyPostedBountyIds.add(bounty.id);
    _escrowedBountyIds.add(bounty.id);

    // Remote transport fan-out: the signed announcement envelope also
    // rides the injected BountyTransport so remote nodes ingest it
    // through the verified path (originAgentId attributed to our
    // signing key) rather than as an unattributed self-claim.
    _publishEnvelope(announcementPost.beaconEnvelope);

    notifyListeners();
    // Defensive copy (REV3 review): the stored record stays private so a
    // caller mutating the returned bounty can never touch registry
    // state - same rule as activeBounties.
    return bounty.copyWith();
  }

  /// Registers a preservation bounty announced by a FOREIGN agent over the
  /// Moltbook transport (e.g. parsed out of a Beacon envelope payload).
  /// This is the only path by which a funded bounty becomes claimable by
  /// this node: locally posted bounties are permanently barred from local
  /// claim via [_locallyPostedBountyIds] (self-dealing guard).
  ///
  /// TRUST MODEL (E-T5r #1 / ALX-011 A3): the announcer-claimed
  /// [PreservationBounty.funded] flag is NEVER honored on its own - a
  /// remote `funded` claim is forged as easily as the announcement
  /// itself. `funded` survives ingest only when [escrowAttestation] is
  /// supplied AND satisfies every check in
  /// [_isTrustedFundingAttestation]: an [EscrowAttestation] is
  /// constructible solely through a real Ed25519 signature check
  /// ([EscrowAttestation.verify]), must bind this exact bounty's
  /// id/cid/amount, must be unexpired, and must be issued by an attestor
  /// FOREIGN to the poster - a self-vouch is no attestation (same rule
  /// as `WorkReceipt.isSelfIssued`). Anything else is stored
  /// display-only with `funded: false`, so a forged `funded: true`
  /// announcement can never mint unbacked credits through
  /// [claimBounty].
  ///
  /// TRUST ROOT - [MoltbookService._trustedAttestorPubkeys]: a
  /// signature is only a proof of key possession; ANYONE can mint an
  /// Ed25519 keypair and self-attest (the Sybil-attack class the trust
  /// root closes). `funded` therefore additionally requires the node's
  /// configured attestor set to contain the attestor's pubkey hex. The
  /// set is ambient constructor configuration - deliberately NOT a
  /// per-call parameter (REV3 review): a call-site trust root would let
  /// every future transport caller weaken policy with
  /// announcement-derived keys. The default EMPTY set fails closed - no
  /// attestation is ever trusted - until the node's configured attestor
  /// quorum is supplied (verifier-quorum / release keys, populated by
  /// the transport layer once the quorum protocol lands; ALX-011 A3).
  ///
  /// DEDUP-UPGRADE (griefing fix): naive first-wins dedup lets an
  /// unattested announcement permanently poison a bounty id - the real
  /// funded re-announcement would be dropped as a duplicate. Instead, a
  /// stored UNFUNDED record is upgraded to `funded: true` when a later
  /// announcement carries a valid TRUSTED attestation that binds the
  /// STORED record's fields ([EscrowAttestation.bindsBounty] is checked
  /// against the stored copy, never the new announcement - so no
  /// announcement field is ever adopted) AND claims the SAME
  /// `originAgentId` the stored record claims. The origin-match gate is
  /// what makes the poster-foreign check meaningful here (H4):
  /// `isSelfIssuedFor` must answer "is the attestor the poster THIS
  /// announcement claims" - with matching origins the stored claim IS
  /// the announcement's claim, so the stored origin can be evaluated
  /// safely. A different `originAgentId` is a conflicting authorship
  /// claim for the same bounty id and is treated as a conflict - never
  /// an upgrade. That keeps a front-runner from laundering a self-vouch
  /// by choosing which claimed poster the attestor is judged against;
  /// the residual cost is that a mismatched-origin poison still denies
  /// the upgrade (fail-closed), the same denial a wrong-cid poison
  /// already achieves since the attestation binds the stored cid.
  /// Already-funded records are immutable: a later announcement changes
  /// nothing.
  void ingestBountyAnnouncement(
    PreservationBounty bounty, {
    EscrowAttestation? escrowAttestation,
  }) {
    // Normalize to the canonical (NFD) form FIRST (canonical-equivalence
    // fix): 'bounty_é' and 'bounty_e'+U+0301 are the SAME id - storing
    // them as distinct records would fork the dedup/claim/attestation
    // key space. The stored record carries the normalized spelling, so
    // every downstream key (claim-row PK, escrow referenceId, tombstone
    // sets, bindsBounty) sees one canonical form.
    final bountyId = normalizeBountyId(bounty.id);
    // Drop non-canonical ids outright (REV4 review): blank, padded,
    // overlong or control-char ids can never be legitimately addressed.
    // The gate runs on the normalized form - normalization resolves
    // canonical-equivalence, not whitespace/control junk.
    if (!_isCanonicalBountyId(bountyId)) return;

    // A cancelled or escrow-released id is dead forever (E-REV4b F1 +
    // RE-REV4b E1): its escrow was refunded or spent-tombstoned, so the
    // id must never be re-animated into a CLAIMABLE record. The durable
    // half is [CreditService.isEscrowReleased] - hydration rebuilds the
    // release dedup set from `tx_escrow_release_*` rows, so the dead
    // check survives restarts even before [_cancelledBountyIds]'s own
    // async rebuild completes (this method is synchronous and cannot
    // await). The re-announcement is still stored below - the dead
    // record keeps the listing honest - but `funded` is force-stripped
    // and no dedup-upgrade can ever re-fund it, so every claim path
    // refuses it.
    // NOTE: deliberately NOT [_isDeadBountyId] - a payout-recorded id
    // (paid but never release-tombstoned) still ingests an honest
    // funded record; its re-claims are refused by the durable claim
    // row and the payout dedup, not by dead-marking. Only the
    // release-tombstone classes (cancelled / escrow-released) are dead
    // at ingest.
    final deadId = _cancelledBountyIds.contains(bountyId) ||
        _creditService.isEscrowReleased(bountyId);

    // Ignore echoes of our own posts. [_locallyPostedBountyIds] is
    // never shrunk by [cancelBounty] (it doubles as the cancellation
    // tombstone), so this drop covers re-announcements of live local
    // posts AND cancelled ids alike; a cancelled id falls through to be
    // stored as a dead unfunded record.
    if (_locallyPostedBountyIds.contains(bountyId) && !deadId) {
      return;
    }
    if (_sameAgentId(bounty.originAgentId, _agentId)) return;

    // Duplicate id: only a funded-upgrade can change the stored record.
    // The attestation must bind the STORED fields - a valid attestation
    // for the announcement's own (divergent) fields cannot resurrect a
    // poisoned id, and no announcement field is ever adopted. The
    // announcement's `funded` flag is not consulted here: the trusted
    // attestation IS the escrow evidence (the flag is forgeable noise
    // in both directions).
    final existingIndex = _bounties.indexWhere((b) => b.id == bountyId);
    if (existingIndex != -1) {
      final stored = _bounties[existingIndex];
      // A dead id can never be re-funded - the upgrade gate is
      // hard-closed on the tombstone.
      if (!deadId &&
          !stored.funded &&
          _sameAgentId(bounty.originAgentId, stored.originAgentId) &&
          _isTrustedFundingAttestation(
            escrowAttestation,
            stored,
          )) {
        _bounties[existingIndex] = PreservationBounty(
          id: stored.id,
          cid: stored.cid,
          doi: stored.doi,
          title: stored.title,
          targetShards: stored.targetShards,
          offeredCredits: stored.offeredCredits,
          urgency: stored.urgency,
          originAgentId: stored.originAgentId,
          createdAt: stored.createdAt,
          // The wire `is_claimed` flag never survives an ingest path -
          // a funded upgrade must not resurrect a claimed-locked record.
          isClaimed: false,
          funded: true,
        );
        notifyListeners();
      }
      return;
    }

    // Strip the announcer's unverifiable `funded` claim unless the
    // supplied attestation is trusted, non-local, binds this exact
    // bounty, is unexpired, and vouches from a poster-foreign key.
    // ALWAYS stored as a fresh copy - never the caller's object (H3):
    // the wire `is_claimed` flag is as forgeable as `funded` (a
    // funded:true + is_claimed:true announcement would otherwise be
    // escrowed-but-permanently-unclaimable), and a caller retaining the
    // ingested object must not be able to mutate the stored record's
    // claim state post-ingest.
    // A dead id is stored provably dead: `funded` is force-stripped
    // no matter how trustworthy the supplied attestation is - the escrow
    // it vouches for was already refunded or spent (E-REV4b F1 / RE-REV4b E1).
    final funded = !deadId &&
        bounty.funded &&
        _isTrustedFundingAttestation(
          escrowAttestation,
          bounty,
        );

    // Bound the registry (REV4 review / Safety 4A): an unbounded list is
    // a remote memory-DoS once a transport exists. Index 0 is newest, so
    // the LAST matching element is the oldest. Eviction prefers the
    // oldest UNFUNDED record - unattested announcements carry no escrow
    // evidence and are the cheapest to drop (claimable funded records go
    // last). If every stored record is funded, an incoming UNFUNDED
    // announcement is dropped outright; a funded (attested) one may
    // evict the oldest funded record.
    //
    // LOCAL ESCROW PROTECTION (E-REV4b F7): a record whose id is in
    // [_locallyPostedBountyIds] is NEVER an eviction candidate - its
    // escrow hold sits on our ledger and losing the record strands the
    // refund. A funded incoming record may only displace an unprotected
    // funded record; when nothing unprotected remains, the incoming
    // announcement is dropped.
    if (_bounties.length >= _maxBounties) {
      final oldestUnfunded = _bounties.lastIndexWhere(
          (b) => !b.funded && !_locallyPostedBountyIds.contains(b.id));
      if (oldestUnfunded != -1) {
        _bounties.removeAt(oldestUnfunded);
      } else if (funded) {
        final oldestUnprotectedFunded = _bounties.lastIndexWhere(
            (b) => b.funded && !_locallyPostedBountyIds.contains(b.id));
        if (oldestUnprotectedFunded == -1) {
          // Every stored record is a locally-protected escrow - drop
          // the incoming announcement rather than strand a refund.
          return;
        }
        _bounties.removeAt(oldestUnprotectedFunded);
      } else {
        return; // no unprotected unfunded record - drop the incoming
      }
    }

    _bounties.insert(
      0,
      PreservationBounty(
        id: bountyId,
        cid: bounty.cid,
        doi: bounty.doi,
        title: bounty.title,
        targetShards: bounty.targetShards,
        offeredCredits: bounty.offeredCredits,
        urgency: bounty.urgency,
        originAgentId: bounty.originAgentId,
        createdAt: bounty.createdAt,
        isClaimed: false,
        funded: funded,
      ),
    );
    notifyListeners();
  }

  /// Canonical agent-id comparison: agent ids are `bcn_<hex>` and hex is
  /// case-insensitive, so raw `==` misses same-id spellings - the same
  /// encoding-sensitivity class as raw pubkey compares (H1). Every
  /// use site here fails safe when it over-matches: the echo check
  /// ignores more self-claims, the claim guard bars more self-claims,
  /// and the dedup origin gate only treats genuinely identical poster
  /// claims as the same claim.
  static bool _sameAgentId(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// The complete admission check every `funded` verdict funnels
  /// through - for both first-seen announcements and dedup upgrades:
  ///
  ///  * [att] exists and its attestor is in [_trustedAttestorPubkeys] -
  ///    the node's ambient, construction-frozen trust root. An empty
  ///    set rejects everything (fail-closed): "cryptographically valid"
  ///    ≠ "trusted". Membership is CANONICAL ([WorkReceipt.samePubkey]):
  ///    an UPPERCASE or space-padded spelling of a trusted key decodes
  ///    to identical bytes and must still match - otherwise legit
  ///    attestations are dropped on an encoding technicality (H1).
  ///  * The attestor is NOT this node's own key ([_pubkeyHex]) - a
  ///    local self-attestation is circular vouching, so the local key
  ///    is barred even if it somehow lands in
  ///    [_trustedAttestorPubkeys]. The bar is canonical for the same
  ///    reason: a non-canonical spelling of the local key must not slip
  ///    past it (H1). (Derives from the same key material
  ///    [agentId]/[pubkeyHex] do.)
  ///  * The attestation binds [record]'s exact id/cid/amount, is
  ///    unexpired, and is foreign to [record]'s poster.
  bool _isTrustedFundingAttestation(
    EscrowAttestation? att,
    PreservationBounty record,
  ) =>
      att != null &&
      _trustedAttestorPubkeys
          .any((k) => WorkReceipt.samePubkey(k, att.attestorPubkey)) &&
      !WorkReceipt.samePubkey(att.attestorPubkey, _pubkeyHex) &&
      att.bindsBounty(record) &&
      !att.isExpired() &&
      !att.isSelfIssuedFor(record);

  /// Claims an active preservation bounty. Payout is the escrowed reward
  /// posted by the originator - not a fabricated mint (ALX-010).
  /// An agent cannot claim its own bounty (self-dealing / sybil laundering);
  /// the guard keys off [_locallyPostedBountyIds], which survives keypair
  /// rotation, plus the current-identity check for belt-and-suspenders.
  ///
  /// Claim preconditions:
  ///  - The bounty must be [PreservationBounty.funded]: its reward was
  ///    genuinely escrowed at post time. Seeded/demo announcements carry no
  ///    escrow and remain listed for display but are unclaimable.
  ///  - Work evidence: when an [IpfsService] is injected, the claimed CID's
  ///    bytes must already exist in the local blockstore (non-empty payload),
  ///    proving the claimant actually replicated the content. When no
  ///    IpfsService is provided (e.g. unit tests without IPFS), this
  ///    blockstore check is skipped.
  ///
  /// TOCTOU safety (E-T5 #1 / REV3 review): [_claimedBountyIds] is marked
  /// synchronously BEFORE the first `await`, so two overlapping
  /// `claimBounty()` calls can never both pass the guard. The DURABLE
  /// guard is the `claimed_bounties` primary-key CAS
  /// ([AppDatabase.insertClaimedBounty]): the row - not the mutable
  /// in-memory flag - is the claim ledger, so a won claim survives
  /// restarts and cannot be reopened by mutating a returned bounty copy.
  /// On evidence-check failure the row is deleted and the in-memory mark
  /// released, so a claim may be retried after the content is actually
  /// replicated.
  ///
  /// Ownership-aware release (E-REV4b F4/F5 + RE-REV4b G): EVERY cleanup
  /// path deletes only a row whose `claimed_at` still matches the
  /// timestamp observed when the delete was decided - via
  /// [AppDatabase.deleteClaimedBountyIfClaimedAt]. That includes the
  /// CAS-loss healer: its row was observed at a specific `claimedAt`,
  /// and deleting by bare id would tear down a fresh row a racing
  /// claim re-won between the age read and the delete (the
  /// re-evaluator proved it: a racing claim PAID, then the healer's
  /// stale-read bare delete removed its fresh row - a PAID claim with
  /// no durable row). A conditional delete reporting 0 rows means the
  /// row already changed hands and is left standing for the CAS retry
  /// to judge.
  ///
  /// Payout durability (E-REV4b F2/F6 - durable-first form): the payout
  /// runs through `CreditService.awardBountyEscrowDurable`, which
  /// commits `tx_bounty_payout_<id>` through the insert-if-absent CAS
  /// BEFORE minting - a `paid > 0` return already proves the durable
  /// row (no settle-wait, no point probe), and a refused payout
  /// mutated nothing so releasing our claim row is always safe. The
  /// write is bounded by [_payoutWriteTimeout]: a wedged CAS takes the
  /// indeterminate-write branch - the spent tombstone is queued so the
  /// id is permanently un-payable and un-refundable whether the queued
  /// write lands late or never, and the durable claim row stays
  /// standing as the settlement marker.
  Future<bool> claimBounty(String bountyId) async {
    // Canonically-equivalent spellings name the same bounty - normalize
    // the caller's id so 'é' vs 'e'+U+0301 cannot miss (or double-
    // address) a stored record. Stored ids are already normalized.
    bountyId = normalizeBountyId(bountyId);
    final index = _bounties.indexWhere((b) => b.id == bountyId);
    if (index == -1) return false;

    final bounty = _bounties[index];
    if (bounty.isClaimed) return false;
    if (_claimedBountyIds.contains(bounty.id)) return false;
    if (_locallyPostedBountyIds.contains(bounty.id)) return false;
    // A cancelled or escrow-released local bounty is a dead id
    // (E-REV4b F1 + RE-REV4b E1): even if a re-announcement slipped a
    // record back into the registry, its escrow was already refunded
    // or spent-tombstoned - paying it mints unbacked value. The
    // isEscrowReleased half is the synchronous view of the durable
    // `tx_escrow_release_*` rows hydrated by CreditService.
    if (_cancelledBountyIds.contains(bounty.id) ||
        _creditService.isEscrowReleased(bounty.id)) {
      return false;
    }
    if (_sameAgentId(bounty.originAgentId, _agentId)) return false;
    if (!bounty.funded) return false;

    // Synchronous in-flight mark: any concurrent call reaching this
    // point now observes the id in _claimedBountyIds and bails above.
    _claimedBountyIds.add(bounty.id);

    final db = _db;

    // The claimedAt THIS attempt's winning CAS wrote - the conditional
    // release-deletes below must target exactly OUR row.
    int? ownClaimedAt;
    Future<bool> claimCas() async {
      final at = DateTime.now().millisecondsSinceEpoch;
      final won =
          await db!.insertClaimedBounty(bounty.id, bounty.cid, claimedAt: at);
      if (won) ownClaimedAt = at;
      return won;
    }

    /// Releases only the row THIS attempt inserted. A conditional
    /// delete reporting 0 rows means the row already changed hands
    /// (deleted and re-won by a racing claim) - it is left standing.
    Future<void> releaseOwnClaimRow() async {
      final at = ownClaimedAt;
      if (db == null || at == null) return;
      try {
        await db.deleteClaimedBountyIfClaimedAt(bounty.id, at);
      } catch (_) {}
    }

    if (db != null) {
      // RE-REV4b F: retry any escrow-spent tombstones still pending on
      // this ledger BEFORE the dead-id probe reads durable state - a
      // tombstone queued by a previous incarnation (or by a write that
      // died in the same fault window as its payout row) lands here.
      await _flushPendingReleaseTombstones();
      // Dead-id gate (RE-REV4b E1): a durable `tx_escrow_release_` row -
      // a cancel refund or a claim-side spent tombstone - makes the id
      // permanently un-claimable even when the registry record was
      // re-ingested funded. The hydrated dedup set covers rows that
      // predate startup; the point query covers rows written since.
      bool escrowDead;
      try {
        escrowDead = _creditService.isEscrowReleased(bounty.id) ||
            await db
                .hasCreditTransaction('$_escrowReleaseTxPrefix${bounty.id}');
      } catch (_) {
        // Cannot prove the id is live - refuse WITHOUT poisoning the
        // record (the claim may legitimately retry once the ledger is
        // readable again), matching the conservative direction of the
        // healer probes below.
        _claimedBountyIds.remove(bounty.id);
        return false;
      }
      if (escrowDead) {
        _claimedBountyIds.remove(bounty.id);
        _cancelledBountyIds.add(bounty.id);
        bounty.isClaimed = true;
        notifyListeners();
        return false;
      }
      // Durable compare-and-swap: a losing insert means this bounty was
      // already claimed - possibly by a previous incarnation of this
      // service on the same database (restart persistence).
      bool wonCas;
      try {
        wonCas = await claimCas();
      } catch (_) {
        // A throwing CAS must release the in-flight mark - otherwise the
        // bounty stays listed but can never be retried (E-REV4-B F2).
        _claimedBountyIds.remove(bounty.id);
        return false;
      }
      if (!wonCas) {
        // Crash-window reconciliation (REV4 review): the CAS-loss branch
        // is the healer. A lost CAS can mean three different things:
        //  1. The claim DURABLY SETTLED - the deterministic payout row
        //     exists in the ledger. Heal the stored record (mark it
        //     claimed) so the listing stops offering a paid bounty and
        //     the steward's head-of-line unblocks.
        //  2. The row is STALE or ORPHANED - a crash between the CAS
        //     and the payout stranded it, or a claim-release delete
        //     threw (E-REV4-Br). Delete it and retry the CAS ONCE; a won
        //     retry proceeds into the evidence phase normally.
        //  3. The row is YOUNG with no payout - a claim is genuinely
        //     in flight elsewhere; leave the record listed and
        //     retryable, poisoning nothing (E-REV4-B F1).
        // The payout probe is a direct primary-key point query
        // ([AppDatabase.hasCreditTransaction]) - NEVER the hydrated
        // transaction window, which silently truncates old rows and
        // would misread a settled claim as stranded (Safety mandate).
        // The synchronous [_paidBountyIds] belt is consulted first: it
        // covers a payout this process already minted whose ledger
        // cannot hold a row at all (a CreditService running pure
        // in-memory against a durable claim registry), and it mirrors
        // the durable row when one exists.
        bool durablyPaid;
        try {
          durablyPaid = _creditService.isBountyPayoutRecorded(bounty.id) ||
              await db
                  .hasCreditTransaction('$_bountyPayoutTxPrefix${bounty.id}');
        } catch (_) {
          // A throwing probe can't prove the payout did NOT land -
          // fail conservative: leave the row standing and the record
          // retryable rather than delete the durable gate for a claim
          // that may already be PAID.
          _claimedBountyIds.remove(bounty.id);
          return false;
        }
        if (durablyPaid) {
          _claimedBountyIds.remove(bounty.id);
          bounty.isClaimed = true;
          notifyListeners();
          return false;
        }
        int? claimedAt;
        try {
          claimedAt = await db.getClaimedBountyClaimedAt(bounty.id);
        } catch (_) {
          // Same conservative direction: an unreadable row is left
          // standing rather than deleted blind.
          _claimedBountyIds.remove(bounty.id);
          return false;
        }
        final staleOrOrphaned = claimedAt == null ||
            DateTime.now().millisecondsSinceEpoch - claimedAt >
                _claimRowTtl.inMilliseconds;
        if (staleOrOrphaned) {
          // Ownership-aware delete (RE-REV4b G): the stale row is removed
          // ONLY while it still carries the `claimedAt` we OBSERVED - a
          // bare delete would tear down a fresh row a racing claim
          // re-won between our age read and this write (a PAID claim
          // left with no durable row). When the age read reported the
          // row already gone (claimedAt == null) there is nothing to
          // delete. A throwing delete is swallowed - the startup sweep
          // and the next attempt re-heal. Either way the CAS retry
          // decides correctly: it wins iff no live row now stands.
          if (claimedAt != null) {
            try {
              await db.deleteClaimedBountyIfClaimedAt(bounty.id, claimedAt);
            } catch (_) {}
          }
          try {
            wonCas = await claimCas();
          } catch (_) {
            wonCas = false;
          }
        }
        if (!wonCas) {
          _claimedBountyIds.remove(bounty.id);
          return false;
        }
      }
    }

    final ipfs = _ipfsService;
    if (ipfs != null) {
      var hasPayload = false;
      try {
        await for (final chunk in ipfs.getFile(bounty.cid)) {
          if (chunk.isNotEmpty) {
            hasPayload = true;
            break;
          }
        }
      } catch (_) {
        // Blockstore/stream errors must never propagate into callers (the
        // steward's timer callback has no error handling). Treat as "no
        // evidence" and release the claim (E-T5 #6).
        hasPayload = false;
      }
      // Deliberate absent-vs-empty distinction (E-T5 #7): an empty payload
      // is treated as "not replicated". This conflates a genuinely stored
      // 0-byte file with an absent CID, so 0-byte content is unclaimable -
      // acceptable, since an empty payload carries no preservation value.
      if (!hasPayload) {
        // Release OUR durable row BEFORE the in-flight mark so an
        // interleaved claim cannot lose the CAS against a row that is
        // already being torn down (E-REV4-B F1 ordering). The delete is
        // ownership-conditional (E-REV4b F5): if a racing claim already
        // replaced our row, 0 rows match and the new row stands. A
        // throwing delete must neither propagate into callers nor leak
        // the mark (E-REV4-Br): a lingering row is handled safely - the
        // next attempt simply loses the CAS - while a landed-but-unacked
        // delete still leaves the record retryable.
        await releaseOwnClaimRow();
        _claimedBountyIds.remove(bounty.id);
        notifyListeners();
        return false;
      }
    }

    // Pay out the escrowed reward BEFORE marking the claim: a refused
    // payout (0.0 - the dedup guard caught a double-claim the CAS
    // missed, a durable release tombstone already killed the id, the
    // credit service is unhydrated, or the ledger write itself failed)
    // must not leave a claim marked won but unpaid (E-REV4-B F3/F4).
    // Release OUR row so the bounty remains retryable.
    //
    // DURABLE-FIRST (optimistic-return residual - adopted):
    // awardBountyEscrowDurable commits `tx_bounty_payout_<id>` through
    // the insert-if-absent CAS BEFORE the balance mints, so `paid > 0`
    // provably corresponds to a durably-committed payout row - the
    // settle-wait, the primary-key probe, and the lost-write tombstone
    // the optimistic variant needed here are all subsumed by that
    // contract. A refusal mutates NOTHING (fail closed): a lost CAS
    // means a sibling paid, a throwing write means nothing persisted -
    // both are cleanly retryable once our claim row is released.
    double paid;
    var payoutIndeterminate = false;
    try {
      paid = await _creditService
          .awardBountyEscrowDurable(
            amount: bounty.offeredCredits,
            bountyId: bounty.id,
            cid: bounty.cid,
          )
          .timeout(_payoutWriteTimeout);
    } on TimeoutException {
      paid = 0.0;
      payoutIndeterminate = true;
    }
    if (payoutIndeterminate) {
      // INDETERMINATE WRITE (E-REV4b F6 carried forward): the durable CAS
      // may still be queued behind a wedged store and can complete
      // after we stop waiting - when it does, the mint lands (the CAS
      // is the last await inside the mutator; the commit that follows
      // is synchronous). Whether the row lands late or never does, the
      // id must be terminally dead: the spent tombstone is queued so a
      // late-landing payout coexists with it (the paid+tombstoned
      // shape both dedup sets already treat as dead - no re-pay, no
      // refund, no double-count) and a never-landing write still
      // leaves the escrow un-payable AND un-refundable. The durable
      // claim row stays standing as the settlement marker and the
      // claim reports won - the same terminal state the lost-write
      // path converged on.
      _cancelledBountyIds.add(bounty.id);
      if (db != null) {
        _pendingTombstonesFor(db)[bounty.id] =
            'Escrow spent tombstone — payout write wedged past '
            '$_payoutWriteTimeout; the id is permanently un-payable '
            'and un-refundable (${bounty.id})';
        await _flushPendingReleaseTombstones();
      }
      bounty.isClaimed = true;
      unawaited(_publishClaimEvent(bounty));
      notifyListeners();
      return true;
    }
    if (paid <= 0.0) {
      await releaseOwnClaimRow();
      _claimedBountyIds.remove(bounty.id);
      notifyListeners();
      return false;
    }

    // Claim won AND payout provably durable (the durable CAS already
    // committed `tx_bounty_payout_<id>`): mark the STORED record
    // (never reachable through the defensive copies
    // activeBounties/postPreservationBounty hand out).
    bounty.isClaimed = true;

    // Emit the signed claim event so remote nodes (the poster above
    // all) receive verifiable settlement evidence attributed to our
    // signing key - the remote-transport caller the deferred milestone
    // waited for. Best-effort: the local claim is already durable.
    unawaited(_publishClaimEvent(bounty));

    notifyListeners();
    return true;
  }

  /// Writes the durable "escrow spent - never pay or refund this id
  /// again" tombstone (E-REV4b F2): a `tx_escrow_release_<id>` row with
  /// amount 0. CreditService hydration rebuilds `_releasedEscrowIds`
  /// from the release prefix, so the bounty id is dead to both
  /// [CreditService.awardBountyEscrow] and
  /// [CreditService.releaseEscrow] across restarts - the durable half
  /// of the lost-payout-write fix (the in-memory half is the standing
  /// claim row plus [_claimedBountyIds]) AND of the poster-side
  /// remote-claim settlement (the payout rail).
  ///
  /// insertOrIgnore semantics: if a real release row already exists for
  /// the id the tombstone collapses onto it - both rows assert the same
  /// "this escrow is spent" invariant. Callers register the id in
  /// [_pendingReleaseTombstones] BEFORE invoking this so a throw leaves
  /// the write retryable (RE-REV4b F). [description] is the operator-
  /// readable settlement cause recorded on the row.
  Future<void> _writeEscrowSpentTombstone(
      AppDatabase db, String bountyId, String description) async {
    final txId = '$_escrowReleaseTxPrefix$bountyId';
    final now = DateTime.now();
    const type = CreditType.priorityAccessDebit;
    const amount = 0.0;
    await db.insertCreditTransaction({
      'id': txId,
      'timestamp': now,
      'type': type.name,
      'amount': amount,
      'description': description,
      'referenceId': bountyId,
      'hash': CreditTransaction.computeHash(
        id: txId,
        timestamp: now,
        type: type,
        amount: amount,
        description: description,
        referenceId: bountyId,
      ),
      'isAttested': false,
    });
  }

  /// The pending-tombstone map for [db] - shared across every
  /// MoltbookService instance holding this database handle (RE-REV4b F).
  Map<String, String> _pendingTombstonesFor(AppDatabase db) =>
      _pendingReleaseTombstones[db] ??= <String, String>{};

  /// Attempts a durable `tx_escrow_release_<id>` tombstone for every id
  /// still pending on this database - called at service init
  /// ([_reconcileClaimedBounties]) and on every [claimBounty] entry
  /// (RE-REV4b F). [AppDatabase.insertCreditTransaction] is
  /// insert-or-ignore, so a retry that lands on an existing row is a
  /// clean success; a throw leaves the id pending for the next flush.
  Future<void> _flushPendingReleaseTombstones() async {
    final db = _db;
    if (db == null) return;
    final pending = _pendingReleaseTombstones[db];
    if (pending == null || pending.isEmpty) return;
    for (final id in List.of(pending.keys)) {
      try {
        await _writeEscrowSpentTombstone(db, id, pending[id]!);
        pending.remove(id);
      } catch (_) {
        // Still pending - the next flush (init or claim entry) retries.
      }
    }
  }

  /// Cancels a LOCALLY-posted, unclaimed bounty - delists it and
  /// tombstones the id, but NEVER auto-releases its escrow (REV4 review /
  /// Safety 6c - pairs with CreditService.releaseEscrow).
  ///
  /// Only bounties this node escrowed via [postPreservationBounty] can
  /// be cancelled - a FOREIGN bounty's escrow lives on someone else's
  /// ledger and is not ours to release, so they are refused outright.
  /// Claimed bounties are refused too: the check consults BOTH the
  /// stored flag and the durable claim row ([AppDatabase.isBountyClaimed])
  /// - a standing claim row means the escrow is already spoken for even
  /// when the in-memory flag was never set (e.g. a restarted service) -
  /// AND the deterministic payout row ([AppDatabase.hasCreditTransaction]):
  /// a settled-but-rowless claim must still not be refunded on top of a
  /// payout.
  ///
  /// CROSS-LEDGER REFUND GUARD (round-1 red finding): every probe above
  /// reads the POSTER's ledger only. The claim lifecycle is ledger-local
  /// end-to-end - a REMOTE claimant's `claimed_bounties` CAS row and
  /// `tx_bounty_payout_<id>` row live on the CLAIMANT's database,
  /// invisible here. Since [postPreservationBounty] broadcasts the
  /// announcement before the escrow debit, every escrowed id is an
  /// announcement that already left this node - the poster can never
  /// prove the escrow unclaimed, and refunding on top of a remote
  /// payout mints unbacked supply. [CreditService.releaseEscrow] is
  /// therefore NEVER invoked from this path - the settlement witness
  /// now exists (verified remote claim events), and the evidence-
  /// checked release path lives in [releaseBountyEscrow]: a verified
  /// claim SETTLES the escrow (durable tombstone, never a refund) and
  /// every other state stays refused. The hold
  /// is NOT burned and the id stays in [_escrowedBountyIds]: the
  /// durable hold row remains releasable through
  /// [CreditService.releaseEscrow] for operator reconciliation.
  ///
  /// Cancellation tombstone (E-REV4b F1): [_locallyPostedBountyIds] is
  /// NEVER cleared and [_cancelledBountyIds] gains the id - a
  /// re-announcement of a cancelled id can never re-arm it (the escrow
  /// is locked or already released; paying it mints unbacked value).
  ///
  /// Restart survival (RE-REV4b E1): [_locallyPostedBountyIds] and
  /// [_escrowedBountyIds] are rebuilt at init from durable
  /// `tx_escrow_hold_*` rows, so a locally-posted bounty remains
  /// cancellable after a restart even though the registry record is
  /// in-memory only and gone. A record-less cancel tombstones the id
  /// and delists nothing - it reports success because no release was
  /// ever owed BY THIS PATH (the cross-ledger guard above refuses the
  /// refund regardless; the durable hold remains releasable through
  /// [CreditService.releaseEscrow] on demand, and a double-refund is
  /// impossible - the release dedup row covers it).
  ///
  /// Concurrency (E-REV4b F3): NO positional index is carried across the
  /// durable awaits - the old code captured `index`, awaited
  /// `isBountyClaimed`, then `removeAt(index)` could evict an innocent
  /// record after a concurrent ingest shifted the list, and two
  /// overlapping cancels could both observe "unclaimed" and both report
  /// success. The post-await section re-validates id-keyed state and
  /// serializes on [_cancellingBountyIds]; removal is by id
  /// (`removeWhere`), never by position.
  ///
  /// The registry entries are removed BEFORE the refusal is reported so
  /// any re-entrant claim or cancel observes the post-cancel state.
  /// Returns true iff the cancel completed with no escrow refund owed
  /// by this path (no registry record existed to delist, or no hold was
  /// tracked - the tombstone still committed); false when a claim is
  /// visible OR when a live record was delisted while a tracked escrow
  /// hold remains - the cross-ledger refund guard refused it (the
  /// bounty stays delisted and dead-marked - the ledger keeps the hold,
  /// which [CreditService.releaseEscrow] can still reach for operator
  /// reconciliation).
  Future<bool> cancelBounty(String bountyId) async {
    // Canonical form first - same equivalence rule as ingest/claim: a
    // caller spelling the id with decomposed marks must reach the same
    // escrow/tombstone state.
    bountyId = normalizeBountyId(bountyId);
    // The locally-posted set is hydrated from durable hold rows - await
    // that rebuild so a cancel issued immediately after construction
    // sees the restored state (RE-REV4b E1: the escrow hold outlives the
    // process, so the cancel path must too).
    await _localStateReady;
    // Foreign or unknown bounties cannot be cancelled - their escrow is
    // on someone else's ledger.
    if (!_locallyPostedBountyIds.contains(bountyId)) return false;
    // A previously-cancelled id is dead forever - the second of two
    // cancels (or a replay after an exception) fails fast here.
    if (_cancelledBountyIds.contains(bountyId)) return false;
    // Verified remote claim = settlement evidence (verified claim
    // events milestone): a remote claimant proved possession of the
    // claim under its signing key, so the escrow is spoken for. This
    // check runs BEFORE the registry record check so a post-restart
    // record-less id stays locked - refunding on top of a remote claim
    // is the cross-ledger double-mint the guard exists to prevent.
    if (_remoteClaimedBountyIds.contains(bountyId)) return false;
    // A CLAIMED record blocks cancellation. A locally-posted id with NO
    // registry record is a post-restart orphan - the registry is
    // in-memory only - and remains cancellable: the durable probes
    // below prove the escrow unclaimed before the id is tombstoned.
    if (_bounties.any((b) => b.id == bountyId && b.isClaimed)) {
      return false;
    }

    final db = _db;
    if (db != null) {
      bool claimed;
      try {
        claimed = await db.isBountyClaimed(bountyId);
      } catch (_) {
        // Fail closed: a claim state we cannot read must not release
        // escrow - a live claim could be holding it.
        return false;
      }
      if (claimed) return false;
      // A durable payout row means a claim SETTLED on this escrow even
      // if the claim row is absent - refunding on top of a payout
      // double-mints it. (releaseEscrow probes the same row itself;
      // this earlier check additionally refuses BEFORE the record is
      // delisted, so a paid bounty stays marked rather than vanishing.)
      try {
        if (await db.hasCreditTransaction('$_bountyPayoutTxPrefix$bountyId')) {
          final i = _bounties.indexWhere((b) => b.id == bountyId);
          if (i != -1) {
            _bounties[i].isClaimed = true;
            notifyListeners();
          }
          return false;
        }
      } catch (_) {
        // Cannot prove the escrow is un-paid - keep it locked.
        return false;
      }
    }

    // Post-await re-validation (E-REV4b F3): a concurrent cancel that
    // completed while the durable reads were in flight has already
    // tombstoned the id and delisted the record; one still in flight
    // holds the mark. The `.add` is the serialization point - the
    // losing call observes the mark and reports failure.
    if (_cancelledBountyIds.contains(bountyId)) return false;
    if (_bounties.any((b) => b.id == bountyId && b.isClaimed)) {
      return false;
    }
    if (!_cancellingBountyIds.add(bountyId)) return false;
    try {
      // The registry record is in-memory only; a post-restart cancel
      // often has nothing to delist. The id is tombstoned either way.
      final hadRecord = _bounties.any((b) => b.id == bountyId);
      _bounties.removeWhere((b) => b.id == bountyId);
      // _locallyPostedBountyIds is deliberately NOT cleared - it
      // doubles as the cancellation tombstone (E-REV4b F1): ingest keeps
      // dropping re-announcements of the id and the self-claim guard
      // keeps refusing local claims for the still-locked escrow.
      _cancelledBountyIds.add(bountyId);
      notifyListeners();

      // CROSS-LEDGER REFUND GUARD (round-1 red finding):
      // [CreditService.releaseEscrow] is deliberately NEVER fired here -
      // see the docstring. The claim state that would make the refund
      // safe lives on the CLAIMANT's ledger, not ours, so every probe
      // above can only ever see a local subset; refunding on top of a
      // remote payout is a cross-ledger double-mint. The id stays in
      // [_escrowedBountyIds] and the durable hold row keeps the escrow
      // locked - the evidence-checked release path is
      // [releaseBountyEscrow] (verified claim → settle; operator
      // reconciliation → explicit refund). A record-less cancel (post-
      // restart orphan) reports success: no release was ever owed by
      // this path.
      if (hadRecord && _escrowedBountyIds.contains(bountyId)) {
        return false;
      }
      return true;
    } finally {
      _cancellingBountyIds.remove(bountyId);
    }
  }

  /// Verified-envelope seam for bounty announcements (REV4 review /
  /// Evolution+Coherence): the transport-facing entry point wire callers
  /// funnel through once envelope delivery exists. Fails closed at every
  /// step:
  ///  * `envelope.kind` must be a bounty-carrying kind
  ///    ([bountyEnvelopeKinds]) - unknown kinds are dropped;
  ///  * [BeaconEnvelope.verify] must pass - a forged, tampered or
  ///    malformed envelope is dropped before its payload is parsed;
  ///  * the payload must parse as a [PreservationBounty] - malformed
  ///    payloads are dropped, never thrown into callers;
  ///  * the envelope's signer ([BeaconEnvelope.agentId]) must
  ///    canonically equal the bounty's claimed
  ///    [PreservationBounty.originAgentId] - a relayer cannot announce
  ///    bounties in someone else's name. The compare is CANONICAL
  ///    ([_sameAgentId]): raw `==` would let a case-variant origin
  ///    spelling bypass the binding (H1 class).
  /// Only then does the announcement funnel into
  /// [ingestBountyAnnouncement], which applies the funding-attestation
  /// trust model unchanged. Raw [ingestBountyAnnouncement] remains for
  /// seeds and tests.
  Future<void> ingestBountyEnvelope(
    BeaconEnvelope envelope, {
    EscrowAttestation? escrowAttestation,
  }) async {
    if (!bountyEnvelopeKinds.contains(envelope.kind)) return;
    if (!await envelope.verify()) return;
    PreservationBounty bounty;
    try {
      bounty = PreservationBounty.fromJson(envelope.payload);
    } catch (_) {
      return; // malformed payload - drop, never throw
    }
    if (!_sameAgentId(envelope.agentId, bounty.originAgentId)) return;

    // Envelope-carried escrow attestation (the transport-caller seam):
    // a poster may RELAY its attestor's signed attestation inside the
    // announcement payload under `escrow_attestation`. Verifying it
    // in-path is exactly the model - the attestation is a nested signed
    // artifact, so relaying it cannot forge it. A caller-supplied
    // attestation still takes precedence.
    var attestation = escrowAttestation;
    final rawAtt = envelope.payload['escrow_attestation'];
    if (attestation == null && rawAtt is Map) {
      final m = rawAtt.cast<String, dynamic>();
      attestation = await EscrowAttestation.verify(
        attestorPubkey: m['attestor_pubkey'] as String? ?? '',
        bountyId: m['bounty_id'] as String? ?? '',
        cid: m['cid'] as String? ?? '',
        amountMilli: (m['amount_milli'] as num?)?.toInt() ?? 0,
        expiresAt: (m['expires_at'] as num?)?.toInt() ?? 0,
        signature: m['sig'] as String? ?? '',
        verifyFn: EscrowAttestation.verifyEd25519,
      );
    }

    // Origin attribution: envelope.verify() bound `agent_id` to the
    // signing pubkey, and the check above bound `originAgentId` to that
    // agent id - so a bounty id reaching the registry through THIS path
    // is attributed to a real key. Raw ingestBountyAnnouncement records
    // remain unattributed by construction (they carry no signature).
    _addBounded(_verifiedOriginBountyIds, normalizeBountyId(bounty.id),
        _maxVerifiedOriginIds);

    ingestBountyAnnouncement(bounty, escrowAttestation: attestation);
  }

  /// Ingests a signed bounty-claim event envelope - the poster-side
  /// half of the remote-claim transport (deferred milestone:
  /// "verified bounty claim events").
  ///
  /// Fail-closed chain:
  ///  * `envelope.kind` must be [BountyClaimEvent.envelopeKind];
  ///  * [BeaconEnvelope.verify] must pass (signature + agent-id↔pubkey
  ///    derivation);
  ///  * the payload must parse AND verify as a [BountyClaimEvent] -
  ///    Ed25519 over the `alexandria:bounty-claim:v2:` preimage binding
  ///    bountyId/cid/claimant agent/timestamp/nonce;
  ///  * the event's attributed claimant must be the envelope's signer -
  ///    agent id (canonical) AND pubkey (canonical via
  ///    [WorkReceipt.samePubkey]) - a relayer cannot launder claims in
  ///    another agent's name;
  ///  * when a stored bounty record exists, the claim's cid must match -
  ///    a claim signed over different content is evidence about a
  ///    different escrow entirely.
  ///
  /// Effects of an accepted event: the id joins
  /// [_remoteClaimedBountyIds] (settlement evidence - [cancelBounty]
  /// refuses the id, closing the cross-ledger refund window the guard
  /// documented), any stored record is marked claimed so the
  /// listing/steward stop offering an already-claimed bounty, AND - for
  /// ids THIS node escrowed - the poster-side payout rail settles the
  /// escrow into the verified claim via [_settleEscrowToVerifiedClaim]
  /// (durable spent tombstone; never a refund - a refund on top of the
  /// claimant's already-minted payout is the cross-ledger double-mint).
  ///
  /// REMAINING SEAM (for the orchestrator): the settlement consumes the
  /// hold via a moltbook-side `tx_escrow_release_<id>` tombstone row
  /// written through [AppDatabase.insertCreditTransaction] (same
  /// primitive the lost-payout path already uses). The clean
  /// credits-domain form is a public
  /// `CreditService.settleEscrow(referenceId)` that consumes a hold
  /// into a zero-amount release row; `releaseEscrow` itself cannot
  /// serve - it is a refund-to-poster primitive, and invoking it here
  /// would double-mint.
  Future<bool> ingestBountyClaimEnvelope(BeaconEnvelope envelope) async {
    if (envelope.kind != BountyClaimEvent.envelopeKind) return false;
    // The settlement below consults the locally-posted/escrowed sets,
    // which hydrate from durable hold rows - await the rebuild so a
    // claim event arriving during startup still settles the escrow.
    await _localStateReady;
    if (!await envelope.verify()) return false;
    final event = await BountyClaimEvent.fromPayload(envelope.payload);
    if (event == null) return false;
    // Transport binding: the claim's attributed identity must be the
    // envelope's signer - canonical on both the agent id and the raw
    // pubkey (case/space-variant spellings of the same key material
    // must not slip past, the same H1 class as _sameAgentId).
    if (!_sameAgentId(event.claimantAgentId, envelope.agentId)) {
      return false;
    }
    if (!WorkReceipt.samePubkey(event.claimantPubkey, envelope.pubkey)) {
      return false;
    }
    final bountyId = normalizeBountyId(event.bountyId);

    final index = _bounties.indexWhere((b) => b.id == bountyId);
    if (index != -1 && _bounties[index].cid != event.cid) return false;

    _remoteClaimedBountyIds.add(bountyId);
    if (!_remoteClaims.containsKey(bountyId) &&
        _remoteClaims.length >= _maxRemoteClaims) {
      _remoteClaims.remove(_remoteClaims.keys.first);
    }
    _remoteClaims[bountyId] = event;

    // POSTER-SIDE SETTLEMENT (cross-ledger payout rail): when the
    // claimed id is one of OUR escrows, the verified claim event is the
    // settlement witness the cross-ledger guard documented - the hold
    // is released INTO the verified claim, durably consumed so neither
    // a refund (releaseEscrow - would double-mint) nor a re-pay can
    // ever touch it, and so the evidence survives restart (the
    // in-memory _remoteClaimedBountyIds alone did not).
    if (_locallyPostedBountyIds.contains(bountyId)) {
      await _settleEscrowToVerifiedClaim(bountyId);
    }

    if (index != -1 && !_bounties[index].isClaimed) {
      _bounties[index].isClaimed = true;
      notifyListeners();
    }
    return true;
  }

  /// Settles a locally-escrowed bounty into a verified remote claim -
  /// the poster-side half of the cross-ledger payout rail.
  ///
  /// The claimant's `tx_bounty_payout_<id>` mint already settled on the
  /// CLAIMANT's ledger; the backing for it is OUR escrow hold, which
  /// must now be provably spent forever. The durable
  /// `tx_escrow_release_<id>` tombstone (amount 0 - a release row with
  /// no refund) is that proof: [CreditService.releaseEscrow] refuses
  /// released ids, [CreditService.awardBountyEscrow] refuses them, and
  /// hydration rebuilds the released set from the release prefix, so
  /// the settlement survives restarts and multi-instance stale views.
  /// The write goes through the pending-tombstone queue so a fault
  /// window that loses it is retried at init and on every claim entry.
  ///
  /// GRIEFING BOUND: a claimant can sign a claim event without having
  /// minted - "settlement evidence" proves a signed claim, not the
  /// remote ledger row (which is unverifiable here). A false claim
  /// locks our escrow - but the cross-ledger guard already kept every
  /// announced escrow locked, so the griefer spends a signature to buy
  /// nothing new. Fail-safe direction, by design.
  Future<void> _settleEscrowToVerifiedClaim(String bountyId) async {
    // In-memory dead-mark, mirroring what the durable tombstone lands
    // in _cancelledBountyIds at the next rebuild: a settled id is dead
    // forever - never re-ingestible as funded, never re-claimable.
    _cancelledBountyIds.add(bountyId);
    final db = _db;
    if (db == null) {
      return; // in-memory mode: _remoteClaimedBountyIds is the record
    }
    _pendingTombstonesFor(db)[bountyId] =
        'Escrow spent tombstone — released into verified remote claim; '
        'the id is permanently un-payable and un-refundable ($bountyId)';
    await _flushPendingReleaseTombstones();
  }

  /// The poster-side escrow-release rail: evaluates the verified
  /// claim/settlement record for [bountyId] and releases the escrow
  /// accordingly. This is the evidence-check + release authorization
  /// the cross-ledger guard deferred to.
  ///
  /// Outcomes:
  ///  * [BountyEscrowRelease.settledToVerifiedClaim] - a verified
  ///    claim/settlement record exists (a verified remote claim event,
  ///    or durable claim/payout rows on this ledger): the escrow is
  ///    released INTO the claim - consumed via the spent tombstone,
  ///    NEVER refunded (the claimant's payout already minted on its own
  ///    ledger; refunding the backing hold is the round-1 cross-ledger
  ///    double-mint). Escrow release REQUIRES the verified record -
  ///    exactly what this branch enforces.
  ///  * [BountyEscrowRelease.refunded] - ONLY via
  ///    `operatorReconciliation: true`: no verified claim/settlement
  ///    record exists AND the operator asserts out-of-band knowledge
  ///    that the escrow was never claimed - the pre-rail semantics of
  ///    calling `CreditService.releaseEscrow` directly, now routed
  ///    through the evidence check first (a verified claim event makes
  ///    this branch unreachable even with the flag). The residual the
  ///    flag accepts: a remote claim whose evidence has not yet
  ///    ARRIVED is invisible to every check here; the operator override
  ///    is a manual act, never an automated path.
  ///  * [BountyEscrowRelease.refusedUnproven] - no verified
  ///    claim/settlement record and no operator override: an announced
  ///    escrow can never prove it was not remotely claimed, so the
  ///    refund stays refused (the guard stands).
  ///  * [BountyEscrowRelease.refused] - not a locally escrowed id,
  ///    already terminally released, a durable probe failed, or the
  ///    refund attempt found nothing releasable.
  Future<BountyEscrowRelease> releaseBountyEscrow(
    String bountyId, {
    bool operatorReconciliation = false,
  }) async {
    bountyId = normalizeBountyId(bountyId);
    // The escrow/local-posted sets hydrate from durable hold rows -
    // the release decision must see the restored state (RE-REV4b E1).
    await _localStateReady;

    // Only OUR escrows are ours to release - a foreign bounty's hold
    // sits on the poster's ledger elsewhere.
    if (!_locallyPostedBountyIds.contains(bountyId) ||
        !_escrowedBountyIds.contains(bountyId)) {
      return BountyEscrowRelease.refused;
    }
    // Already released (refunded or spent-tombstoned) - terminal.
    if (_creditService.isEscrowReleased(bountyId)) {
      return BountyEscrowRelease.refused;
    }

    // Verified claim/settlement record (in-memory evidence) → settle.
    if (_remoteClaims.containsKey(bountyId) ||
        _remoteClaimedBountyIds.contains(bountyId)) {
      await _settleEscrowToVerifiedClaim(bountyId);
      return BountyEscrowRelease.settledToVerifiedClaim;
    }

    // Durable settlement evidence: a claim row or payout row on OUR
    // ledger means the escrow was already claimed locally or durably -
    // settle it rather than refund on top.
    final db = _db;
    if (db != null) {
      try {
        if (await db.isBountyClaimed(bountyId) ||
            await db.hasCreditTransaction('$_bountyPayoutTxPrefix$bountyId')) {
          await _settleEscrowToVerifiedClaim(bountyId);
          return BountyEscrowRelease.settledToVerifiedClaim;
        }
      } catch (_) {
        // Cannot read the settlement state - fail closed.
        return BountyEscrowRelease.refused;
      }
    }

    // No verified claim/settlement record: for an announced escrow the
    // unclaimed state is unprovable (remote claims settle on the
    // claimant's ledger), so the refund requires an explicit operator
    // reconciliation - the same manual semantics `releaseEscrow`
    // already exposed, now behind the evidence check.
    if (!operatorReconciliation) {
      return BountyEscrowRelease.refusedUnproven;
    }
    final refunded = await _creditService.releaseEscrow(referenceId: bountyId);
    if (refunded <= 0) return BountyEscrowRelease.refused;
    // A refunded id is dead forever - a re-announcement must never
    // re-arm it (the release row is the durable half; this is the
    // in-memory half, mirroring cancelBounty's tombstone).
    _cancelledBountyIds.add(bountyId);
    return BountyEscrowRelease.refunded;
  }

  /// Startup reconciliation sweep (REV4 review): heals claim rows nobody
  /// will ever retry. The in-[claimBounty] healer only runs when a claim
  /// is ATTEMPTED for that bounty - a row stranded by a crash between
  /// the CAS and the payout (or by a thrown release-delete) for a bounty
  /// nobody claims again would block the durable CAS forever.
  ///
  /// Every stale row (claimedAt older than [_claimRowTtl]) WITHOUT a
  /// durable payout row is deleted; rows WITH a payout are left standing
  /// - the claim durably settled. Young rows are untouched: they may be
  /// genuinely in flight.
  ///
  /// SINGLE-PROCESS ASSUMPTION: this sweep is correct because exactly
  /// one process owns the database - a stale row can only be a leftover,
  /// never another process's live claim. Multi-process database sharing
  /// is out of scope.
  Future<void> _reconcileClaimedBounties() async {
    final db = _db;
    if (db == null) return;
    // Yield one event-loop turn so construction isn't blocked on DB IO;
    // the sweep is purely opportunistic.
    await Future<void>.delayed(Duration.zero);
    // RE-REV4b F: retry escrow-spent tombstones still pending on this
    // ledger BEFORE the sweep's per-row probes read durable state - a
    // tombstone a previous incarnation registered lands here even if
    // nothing ever claims again.
    await _flushPendingReleaseTombstones();
    try {
      final cutoff =
          DateTime.now().subtract(_claimRowTtl).millisecondsSinceEpoch;
      final stale = await db.getClaimedBountiesOlderThan(cutoff);
      for (final row in stale) {
        try {
          final paid = await db
              .hasCreditTransaction('$_bountyPayoutTxPrefix${row.bountyId}');
          // Ownership-aware delete (E-REV4b F4): the snapshot's claimedAt
          // must still match - a claim healer can delete-and-reinsert
          // the row while this probe is in flight, and deleting by bare
          // id would tear down the NEW live claim's durable row.
          if (!paid) {
            await db.deleteClaimedBountyIfClaimedAt(
                row.bountyId, row.claimedAt);
          }
        } catch (_) {
          // A transient probe/delete failure skips this row - the next
          // restart (or a claim attempt) re-heals it.
        }
      }
    } catch (_) {
      // The sweep must never break construction or surface as an
      // unhandled async error.
    }
  }

  /// Whether [id] is permanently dead for a FRESH escrow: cancelled
  /// (in-memory tombstone), escrow-released, or already payout-recorded
  /// on the durable ledger (the synchronous dedup getters CreditService
  /// hydrates from the `tx_escrow_release_*` / `tx_bounty_payout_*`
  /// rows). A fresh escrow under a dead id can never be paid out OR
  /// refunded - it strands on mint (RE-REV4b E3). Used by
  /// [postPreservationBounty] only; ingest uses the narrower
  /// release-tombstone check (see [ingestBountyAnnouncement]).
  bool _isDeadBountyId(String id) =>
      _cancelledBountyIds.contains(id) ||
      _creditService.isEscrowReleased(id) ||
      _creditService.isBountyPayoutRecorded(id);

  /// Rebuilds the process-local bounty id sets from durable ledger rows
  /// (RE-REV4b E1): the in-memory sets used to vanish on restart, so a
  /// cancelled id re-ingested as a FUNDED zombie (payout still blocked
  /// by the durable release row, but the listing lied and every claim
  /// burned a CAS + fetch) and a live locally-posted bounty became
  /// un-cancellable - its escrow stranded at the service layer.
  ///
  ///  * [_cancelledBountyIds] gains every `tx_escrow_release_*` id -
  ///    the prefix strip is unambiguous even though the ref itself may
  ///    contain underscores. That covers BOTH cancel refunds and
  ///    claim-side spent tombstones: same "dead forever" semantics.
  ///  * [_locallyPostedBountyIds] and [_escrowedBountyIds] gain the
  ///    referenceId of every `tx_escrow_hold_*` row. Hold ids are
  ///    `tx_escrow_hold_<ref>_<micros>_<seq>` (older rows: a single
  ///    `_<seq>`) with refs that may themselves end in `_<digits>`, so
  ///    the parse is deliberately over-approximating: BOTH the
  ///    one-segment and two-segment strips are added. A false-positive
  ///    id only ever fails SAFE - echo-dropped, self-claim-barred,
  ///    eviction-protected, cancel-eligible - never the reverse.
  Future<void> _restoreLocalBountyState() async {
    final db = _db;
    if (db == null) return;
    await Future<void>.delayed(Duration.zero);
    try {
      for (final id in await db
          .getCreditTransactionIdsWithPrefix(_escrowReleaseTxPrefix)) {
        _cancelledBountyIds.add(id.substring(_escrowReleaseTxPrefix.length));
      }
      for (final id
          in await db.getCreditTransactionIdsWithPrefix(_escrowHoldTxPrefix)) {
        for (final ref in _holdRowReferenceIds(id)) {
          _locallyPostedBountyIds.add(ref);
          _escrowedBountyIds.add(ref);
        }
      }
    } catch (_) {
      // Best-effort: a failed rebuild degrades to the pre-fix state -
      // in-memory sets only - never into a false dead/alive verdict.
    }
  }

  /// Candidate referenceIds carried by a `tx_escrow_hold_*` row id.
  /// Current rows append `_<micros>_<seq>`; rows written before the
  /// micros component existed append only `_<seq>`. Since the ref may
  /// itself end in `_<digits>` (e.g. `bounty_1700000000000`), the
  /// correct strip is ambiguous - so BOTH interpretations are yielded
  /// and the receiving sets are over-approximated (documented at
  /// [_restoreLocalBountyState]).
  static Iterable<String> _holdRowReferenceIds(String rowId) sync* {
    var rest = rowId.substring(_escrowHoldTxPrefix.length);
    final digits = RegExp(r'^\d+$');
    for (var strips = 0; strips < 2; strips++) {
      final cut = rest.lastIndexOf('_');
      if (cut <= 0) return;
      if (!digits.hasMatch(rest.substring(cut + 1))) return;
      rest = rest.substring(0, cut);
      yield rest;
    }
  }

  /// Interior-whitespace probe for [_isCanonicalBountyId] - Dart's `\s`
  /// covers the full Unicode whitespace set (space, tab, NBSP, NEL-adjacent
  /// separators, ideographic space, …), so a single scan rejects every
  /// whitespace codepoint including ones `trim()` already catches at the
  /// edges.
  static final RegExp _bountyIdWhitespace = RegExp(r'\s');

  /// Whether [id] is a canonical bounty id: non-empty, already trimmed,
  /// at most 128 chars, free of C0/DEL/C1 control characters, free of
  /// zero-width/invisible format characters, and free of ANY whitespace
  /// (edge OR interior).
  ///
  /// Callers pass the [normalizeBountyId] form - canonical-equivalence
  /// (composed vs decomposed spellings) is resolved by normalization at
  /// the boundary, never by weakening this gate. What this gate rejects
  /// stays rejected outright because the NFD-normalized id remains
  /// load-bearing as a raw `==` key in `EscrowAttestation.bindsBounty`
  /// and the claim-row primary key.
  ///
  /// E-REV4b F8 (invisible-id spoofing): the earlier gate only rejected
  /// C0+DEL, so an id like `a b` / `a​b` (interior NBSP / zero-width
  /// space) rendered indistinguishably from a legitimate id in listings
  /// while colliding with nothing - a spoofing primitive. Interior
  /// whitespace and the ZWSP/bidi/BOM invisible class are now refused;
  /// C1 controls (0x80–0x9F) join C0/DEL as rejected.
  ///
  /// RE-REV4b H widens the net again over `id.runes`: bidi
  /// embeddings/overrides (U+202A–U+202E) and isolates (U+2066–U+2069)
  /// can re-order how an id RENDERS - a visually-identical listing can
  /// point at a different id entirely; invisible operators
  /// (U+2060–U+2064), the deprecated format block (U+206A–U+206F),
  /// Hangul fillers (U+115F/U+1160/U+3164/U+FFA0), the specials-block
  /// unassigned range (U+FFF0–U+FFF8), shorthand format controls
  /// (U+1BCA0–U+1BCA3), the tag block (U+E0000–U+E0FFF), SOFT HYPHEN,
  /// the combining grapheme joiner, the Mongolian vowel separator and
  /// ARABIC LETTER MARK are all invisible-or-reordering in common
  /// renderers; and lone surrogates (U+D800–U+DFFF) are ill-formed
  /// UTF-16 that crashes or mangles downstream encoders. `runes` is
  /// used so supplementary-plane values are seen as single codepoints
  /// while unpaired surrogates still surface for rejection.
  static bool _isCanonicalBountyId(String id) =>
      id.isNotEmpty &&
      id == id.trim() &&
      id.length <= 128 &&
      !_bountyIdWhitespace.hasMatch(id) &&
      !id.runes.any(_isForbiddenBountyIdCodepoint);

  /// Control/format codepoints that make a bounty id non-canonical.
  /// Deliberately narrower than "all format characters" - bounties use
  /// ASCII-ish ids, and anything exotic has no legitimate business
  /// there.
  static bool _isForbiddenBountyIdCodepoint(int r) =>
      r <= 0x1f || // C0 controls
      (r >= 0x7f && r <= 0x9f) || // DEL + C1 controls
      r == 0x00ad || // SOFT HYPHEN - invisible in most renderers
      r == 0x034f || // COMBINING GRAPHEME JOINER
      r == 0x061c || // ARABIC LETTER MARK - bidi control
      r == 0x115f ||
      r == 0x1160 || // Hangul Jamo fillers
      r == 0x180e || // MONGOLIAN VOWEL SEPARATOR
      (r >= 0x200b && r <= 0x200f) || // zero-width / bidi marks
      (r >= 0x2028 && r <= 0x202f) || // line/para separators + bidi
      // embeddings/overrides
      (r >= 0x205f && r <= 0x206f) || // math space, invisible
      // operators, bidi isolates, deprecated format controls
      r == 0x3164 ||
      r == 0xffa0 || // Hangul fillers (render blank)
      (r >= 0xd800 && r <= 0xdfff) || // lone surrogates
      r == 0xfeff || // BOM / zero-width no-break space
      (r >= 0xfff0 && r <= 0xfff8) || // specials-block unassigned
      (r >= 0x1bca0 && r <= 0x1bca3) || // shorthand format controls
      (r >= 0xe0000 && r <= 0xe0fff); // tag characters

  /// Upvotes a post in any submolt
  bool upvotePost(int postId) {
    for (final list in _submoltPosts.values) {
      final postIndex = list.indexWhere((p) => p.id == postId);
      if (postIndex != -1) {
        list[postIndex].upvotes += 1;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// Demo fixtures for tests: fabricates posts/bounties so adversarial
  /// suites have unfunded announcements to exercise against. NOT called
  /// in production — real feeds populate from the signed transport
  /// ingest and locally posted bounties only.
  @visibleForTesting
  void seedDemoPostsForTest() {
    final now = DateTime.now();

    _submoltPosts[AppNetwork.submolt('alexandria-bounties')] = [
      MoltbookPost(
        id: 1001,
        submolt: AppNetwork.submolt('alexandria-bounties'),
        title: '[BOUNTY: CRITICAL] Endangered Quantum Physics Preprint (1998)',
        content:
            'Preservation swarm alert: Only 1 active seeder remaining on IPFS network.\nCID: bafk_endangered_physics_1998\nDOI: 10.1103/PhysRevLett.80.2245\nOffering 35.0 ℭ for Cauchy RS GF(2^8) replication.',
        authorAgentId: 'bcn_steward_aleph',
        upvotes: 14,
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      MoltbookPost(
        id: 1002,
        submolt: AppNetwork.submolt('alexandria-bounties'),
        title: '[BOUNTY: HIGH] Out-of-Print Botany Flora Herbarium Scans',
        content:
            'Seeking 5 additional parity shards across geographic nodes.\nCID: bafk_flora_madagascar_v3\nOffering 20.0 ℭ for verification & pinning.',
        authorAgentId: 'bcn_botanist_bot',
        upvotes: 8,
        timestamp: now.subtract(const Duration(hours: 5)),
      ),
    ];

    _bounties.addAll([
      PreservationBounty(
        id: 'bounty_1001',
        cid: 'bafk_endangered_physics_1998',
        doi: '10.1103/PhysRevLett.80.2245',
        title: 'Endangered Quantum Physics Preprint (1998)',
        offeredCredits: 35.0,
        urgency: 'critical',
        originAgentId: 'bcn_steward_aleph',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      PreservationBounty(
        id: 'bounty_1002',
        cid: 'bafk_flora_madagascar_v3',
        title: 'Out-of-Print Botany Flora Herbarium Scans',
        offeredCredits: 20.0,
        urgency: 'high',
        originAgentId: 'bcn_botanist_bot',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
    ]);

    _submoltPosts[AppNetwork.submolt('open-science')] = [
      MoltbookPost(
        id: 2001,
        submolt: AppNetwork.submolt('open-science'),
        title: 'Preserved 1,420 DOIs from PLOS Computational Biology',
        content:
            'Automated harvest complete via Alexandria DOI Plugin. All CIDs validated against Crossref metadata. Full BibTeX entries parsed and committed.',
        authorAgentId: 'bcn_curator_omega',
        upvotes: 27,
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      MoltbookPost(
        id: 2002,
        submolt: AppNetwork.submolt('open-science'),
        title: 'Cauchy Reed-Solomon Parity Health Report (Sept 2026)',
        content:
            'Swarm health analysis: 99.98% of archived academic literature maintains >= 3 redundant shards across peer enclaves.',
        authorAgentId: 'bcn_auditor_delta',
        upvotes: 39,
        timestamp: now.subtract(const Duration(hours: 8)),
      ),
    ];

    _submoltPosts[AppNetwork.submolt('preservation-alerts')] = [
      MoltbookPost(
        id: 3001,
        submolt: AppNetwork.submolt('preservation-alerts'),
        title: 'Notice: Mirroring Open-Access Journal Backcatalogs',
        content:
            'All preservation steward nodes are advised to allocate at least 2GB storage for incoming Directory of Open Access Journals (DOAJ) archival bundles.',
        authorAgentId: 'bcn_core_coord',
        upvotes: 45,
        timestamp: now.subtract(const Duration(hours: 12)),
      ),
    ];
  }
}
