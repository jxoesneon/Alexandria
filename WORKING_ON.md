# Working On - Known Residuals & Deferred Work

This file tracks the honest residuals carried forward from the ALX-010–012
security rounds (Protocol Governance + adversarial evaluation loops) and the
deferred milestones with their trigger conditions. Everything listed here is
*deliberately* open - each item has a reason it isn't done yet, not just an
oversight. See `docs/rfcs/ALX-012-version-enforcement.md` §5 for the full
reasoning.

## Open residuals (known limitations, documented bounds)

- **Audit-log tail-rollback against a persistent two-domain attacker
  (needs an external anchor to close).** The redundant head anchors
  added this round (secure-storage head + MAC'd sidecar `.head` file +
  in-file `audit_chain_checkpoint` lines - see Round-8 below) make
  truncation *detectable* for every single-shot adversary, but an
  attacker holding BOTH the log directory and secure storage
  persistently who previously captured an older anchor pair can roll
  all anchors back to a consistent earlier head and truncate to it -
  no purely-local mechanism distinguishes a rolled-back anchor from a
  fresh one. Atomic erasure of the log, sidecar AND storage head also
  leaves nothing to check. Closing this needs an anchor outside the
  compromised domains: remote notarization of the head digest, an
  append-only remote log, or a hardware monotonic counter. Deferred -
  no remote notarization transport exists yet.
- *(The three ledger-domain residuals carried from ALX-010–012 closed
  in an earlier round; their platform-level bounds are documented with
  each closure below.)*

### Closed this round (ALX-012 residual closures)

- **Beyond-window escrow holds are now reachable.** New DAO
  `getEscrowHoldRows(referenceId)` does a targeted `reference_id` read
  returning amount-bearing rows matched by the non-forgeable
  `tx_escrow_hold_` id prefix (plus the exact pre-REV4a description form),
  independent of the ~100k-row hydration window. `releaseEscrow` merges
  durable candidates with the in-memory scan, deduplicated by row id and
  re-filtered through `_isReleasableHold`.
- **Multi-instance stale-view reconciliation.** Durable rows are the
  authority: payout/release/hold writes go through
  `insertCreditTransactionIfAbsent` (`INSERT OR IGNORE` + `changes()`
  inside a transaction), and `releaseEscrow` probes the durable payout
  and release tombstones before refunding - a stale in-memory dedup set
  can no longer mint a second refund. Lost CAS writes reconcile the
  local view to the canonical row's amount; attested egress is gated by
  `insertAttestedDebitIfCovered`, which re-sums the durable scoped pool
  and re-resolves the held-key set at write time.
- **Signed `WorkReceipt` upgrade.** `ingestWorkReceipt` fills an empty
  `verifier_sig`/`prover_sig` column on a stored row after verifying the
  incoming signature in-path; it never overwrites a stored signature
  (first-signed-wins), never touches `spent`, and refuses
  receiptId/body mismatches. Backed by the conditional-update DAO
  `upgradeWorkReceiptSignatures`.
- **Prover-key-scoped attested balances (schema v7).**
  `credit_transactions.attested_pubkey` scopes each attested mint to the
  canonical prover key it was claimed under; `attestedBalance` sums the
  shards of currently-held keys plus the unscoped (NULL) legacy bucket.
  `LocalProverPubkeyResolver` now resolves a `Set<String>?`; the legacy
  single-key `localProverPubkeyHex` spelling still wraps into it.
- **`proverSig` issuance acknowledgment (wire v3).** v3 receipts require
  a prover counter-signature over `alexandria:receipt-ack:v{v}:{id}` -
  provenance/delivery proof; the claim-time possession signature remains
  the anti-theft mechanism. v1/v2 artifacts stay claimable within their
  TTL window.
- **Freshness-bound remote claims.** `claimVerifiedReceipt` accepts
  `verifierNonce`/`expiryMillis` together (either alone is malformed and
  refuses); the claim signature must cover
  `alexandria:receipt-claim:v{v}:{id}:{nonce}:{expiry}` with a future
  expiry. Expired, mismatched or replayed proofs fail closed and leave
  the row unspent; local claims keep the static preimage + CAS.
### Round-5 additions

- **6rd nibble-boundary / partial-v4 embeds remain in `UrlSafety`** -
  CLOSED this round: ISATAP (`0000:5EFE:` / `0200:5EFE:` IIDs) re-gates
  the embedded v4 through the full IPv4 table; 6rd byte-aligned FULL
  32-bit embeds (prefix /0–/32, offsets 0–4) are scanned against the
  dangerous-v4 ranges; and non-global-unicast v6 (outside 2000::/3,
  non-v4-mapped) is refused outright. NARROWED this round: shifted
  embeds are now scanned at EVERY bit offset 0..32 - but only for an
  exact-match denylist of the cloud metadata endpoints
  (169.254.169.254/253, 169.254.170.2), so nibble-boundary (/28, /36)
  and arbitrary-prefix (/29…) full-32-bit embeds of THE canonical
  SSRF target are refused while range checks at shifted offsets stay
  off (they collide with ordinary global unicast - the offset-12
  window of 2606:4700:4700::1111 decodes to 100.112.4.116 ∈
  100.64.0.0/10, a real Cloudflare literal). PUSHED further this
  round: (i) PARTIAL embeds are now scanned too - the largest
  enumerable hostile-relay shape, `IPv4PrefixLen = 8`, leaves the
  low-24 of the target in the literal, so 24-bit windows at every bit
  offset 0..40 are matched against the low-24 fingerprints of the
  same three metadata endpoints; (ii) the byte-aligned protected-space
  scan was narrowed to ranges a tunnel can actually REACH (loopback,
  RFC-1918, link-local, CGNAT, benchmarking) - the documentation-only
  ranges (192.0.0.0/24, TEST-NET-1/2/3, MCAST-TEST-NET) were removed
  because a 6rd tunnel can never deliver a packet into documentation
  space and matching them false-positived a REAL resolver
  (dns0.eu's 2a10:50c0::ad1 carries a c0:00:00 window at offset 3).
  STILL OPEN: (a) shifted embeds of any OTHER protected target - no
  exact list can enumerate private space, and a coincidental
  full-32-bit collision on the denylist patterns is possible in a
  crafted (but improbable) global unicast literal, failing closed on
  that one address; (b) partial embeds of ≤16 bits (v4PrefixLen ≥ 16)
  carry too few discriminating bits to match without colliding
  constantly with ordinary literals - reachable only via a
  hostile/misconfigured relay; (c) the 24-bit scan is structurally
  ambiguous with the low-24 of a PUBLIC full-32 embed (e.g. a
  168.254.169.254 embed presents the fea9fe window) - the gate
  cannot see the relay's configured v4 prefix, so it fails closed on
  that one literal by design; (d) 0/8, multicast and reserved embeds
  are deliberately not flagged (unroutable to protected targets, and
  matching them false-positives on `::`-compressed zero windows).
  True closure needs a kernel-level egress policy; the DNS-answer
  path was already gated.
- **Mesh mutual auth + wire dispatch** - CLOSED this round on top of
  the earlier channel binding: the ALX-MESH/1 handshake now supports a
  MUTUAL (7-field) HELLO carrying the dialer's self-certifying peerId
  plus an Ed25519 signature over
  `ALX-MESH/1|DIALER|nonce‖dialerPeerId‖multiaddr‖dialerEph`; the
  responder verifies it against the key the peerId encodes BEFORE the
  ephemeral exchange (forged/anonymous-claimed identities refused; a
  6-field claimed-identity HELLO is malformed), the responder's ACK
  signature additionally covers the verified dialerPeerId, and both
  wire lines - BOTH signatures - feed the HKDF transcript. Frame MACs
  carry an implicit direction byte so a relay cannot reflect one
  side's frames back at it. `MeshTransportService` accepts
  `localPeerId`/`localPeerIdResolver` + `identitySigner` (the provider
  wires `IdentityService`); anonymous dials remain backward
  compatible. The handshake socket is RETAINED as the frame
  transport: `sendPayload` writes `len(4 BE) ‖ frame`, the receive
  pump reassembles/verifies/surfaces payloads, an oversized declared
  length tears the link down, and socket close demotes the peer under
  the round-6 TOCTOU rules (re-read the row; demote only the failed
  address/channel instance - stale sockets of replaced channels
  cannot demote). Injected-probe channels (no socket) keep
  routing-stub dispatch semantics. OPEN bound: `sendPayload: true`
  means "MAC'd frame handed to the wire", not transport-ACKed;
  anonymous-dialer sessions still leave the responder unable to
  attribute a channel to a dialer identity (by design - caller's
  choice); and `sendPayload`'s frame cap is 1 MiB with no
  application-level chunking yet.
- Closed this round: **`Vote.isHuman` is no longer caller-declared on
  attested ballots.** `ConsensusService` accepts a `HumanAttestationClock`
  (wired to `BiometricService.lastAuthenticatedAt`, which is set only by a
  genuine `LocalAuthentication.authenticate` success - the fail-open
  bypasses never record). `castVote` honours a caller's `isHuman` claim
  only when the clock reports a device-credential authentication inside
  `humanAttestationWindow` (default 5 min, future timestamps excluded);
  otherwise the ballot is minted `isHuman == false`, which both excludes
  it from `humanApprovalCount` and prices its weight at the AI factor.
  Residual bound: the binding is temporal (recency), not per-vote - a
  stronger design would sign the biometric event into the ballot itself.
- Also closed this round (defense-in-depth hardening, not residuals):
  **`SecurityOverviewService.exportPrivateKey`** now wraps the private key
  under an Argon2id key (m=19 MiB, t=2, p=1, 16-byte random salt, OWASP
  minimum) inside a versioned JSON envelope carrying KDF params - replacing
  single-round unsalted SHA-256(password). Deliberate format break: no
  in-app importer exists. **`HeadlessSdk`**'s RPC bearer-token check is now
  a constant-time XOR-fold (was short-circuiting `==`). **`AddContentScreen`**
  enforces a 512 MiB per-file ingest cap before any byte buffer is touched
  (bounds the scrubber's 32-bit PNG chunk walk and picker memory) and
  ingests EVERY selected file with per-file error isolation (was
  first-file-only). **`AuditLogService.getRecentLogs`** clamps
  non-positive limits; **access-policy reads** fail closed on a corrupt
  store and `grantAccess`/`revokeAccess` validate peer DIDs;
  **`HonorSystem.recordVote`** dedups per (validator, target);
  **`HonorBandwidthService`** clamps `maxConcurrent >= 1`; and
  **`readingProgressProvider`** fails closed on non-map/malformed persisted
  JSON instead of trusting it; and **`CryptoBridgeService.setCashuMint`**
  now gates `mintUrl` through `UrlSafety.requirePublicFetchUri` at set
  time (orchestrator seam - closed), matching the client's onion-http
  policy.
- Closed in-tree this round: **`ChangeRequest.status`** is no longer a public
  mutable field (private `_status`, transitions only via `resolve()` pending→
  terminal); **`SyncService._loadQueue`** no longer throws on corrupt persisted
  JSON (skips undecodable payloads and malformed entries); the Tor
  proxy-address `split(':')` in `NetworkOverviewService` no longer mangles
  `[v6]:port` (uses the structured `proxyHost`/`proxyPort` accessors).

### Round-6 additions (agent-domain residual closures)

- Closed: **combining-mark / canonical-equivalence spoofing of bounty ids.**
  `bounty_id_canonicalization.dart` implements NFD normalization over a
  generated table (`unicode_canonical_tables.dart`: 13,253 canonical
  decompositions + 934 combining-class entries covering the full Unicode
  range, Hangul algorithmic). `MoltbookService` normalizes at bounty ingest,
  claim lookup, and cancellation; `EscrowAttestation.bindsBounty` compares
  canonical-equivalent ids while CID/amount stay exact. Verified
  byte-identical to `unicodedata.normalize('NFD')` over 19,677 vectors.
  Bounds: NFC is not produced - output is NFD, so keys are stable and
  equivalent inputs converge; rendering-form differences are irrelevant
  since ids never display raw.
- Closed: **MCP `receipt_attested` misreporting** - `isSelfIssued` now uses
  the canonical `WorkReceipt.samePubkey` comparison, so case-variant key
  spellings report `attested_claim: false` consistently with the claim path.
- Closed: **MCP stdio runner** (`mcp_stdio_runner.dart`) - thin shim over
  injected service interfaces (no second ProviderContainer). Session-scoped
  auth token (crypto-random, constant-time compare, `token` field or
  `_meta.session_token`), per-tool sliding-window rate budgets,
  spend/escrow ceilings with a mandatory human-consent hook, and an
  authenticated loopback control socket (`McpControlSocket`: auth handshake
  + per-request token, serialized writes). Read-only allowlist only;
  financial and receipt-ingest tools are refused outright.
- Closed: **verified bounty claim events** - `BountyClaimEvent` is an
  Ed25519 signature over a canonical preimage binding
  bountyId/cid/claimant/agent, carried in signed Beacon envelopes.
  `MoltbookService` ingests them via `ingestBountyClaimEnvelope`
  (attributing `originAgentId` to the signing key), publishes signed claim
  events after local claims, blocks cancellation after verified remote
  settlement evidence, and marks matching local records claimed.
  `BountyTransport` is an injectable interface (in-memory impl for tests).
  Remaining seam: a production network transport impl and a credits-domain
  cross-ledger payout rail - verified events are currently settlement
  *evidence* exposed via `remoteClaimFor`/`isRemotelyClaimed`, not a
  payment mechanism.

### Round-7 additions (credits/database residual closures)

- Closed: **optimistic-return window on trust-bearing credit
  mutators.** Durable variants now exist and are the forms the trust
  paths call: `CreditService.spendCreditsDurable`,
  `debitEscrowDurable`, `awardBountyEscrowDurable`, plus
  `CryptoBridgeService.exportCreditsAsCashuTokenDurable`,
  `sweepToLightningAddressDurable`, and the live Lightning sweep
  (which debits through `spendCreditsDurable` before the payout
  fires). Each commits the ledger row through its CAS
  (`insertCreditTransactionIfAbsent` /
  `insertAttestedDebitIfCovered`) BEFORE the in-memory view mutates -
  a returned success provably corresponds to a durably-committed row.
  `releaseEscrow` and `claimVerifiedReceipt` were reordered the same
  way (durable write first, in-memory mutation second).
  WRITE-FAILURE POLICY: durable debit/release/payout paths fail
  CLOSED (returned `0.0`/`false`, nothing mutates - a retryable
  refusal beats an unprovable mutation); the receipt-claim mint fails
  OPEN on a write error (a lost mint row under-reports on the next
  hydration replay - the conservative direction - never over-reports,
  and a broken store must not void value the receipt CAS already
  consumed). The synchronous `spendCredits`/`debitEscrow`/
  `awardBountyEscrow`/`exportCreditsAsCashuToken`/
  `sweepToLightningAddress` remain as documented UI-convenience
  (optimistic) forms: their doc comments state the returned value
  precedes the durable settle and reconciles asynchronously via
  `_reconcileMintedCredit`/`_rollbackAttestedDebit`. SEAMs (agent/UI
  domains) - BOTH ADOPTED in Round-9: `MoltbookService` now calls
  `debitEscrowDurable` (posting) and `awardBountyEscrowDurable`
  (payout, bounded `payoutWriteTimeout` + indeterminate-write
  tombstone), and `alexandria_mcp_server`'s `_replicateCid` /
  `_exportCashuVoucher` go async through `spendCreditsDurable` /
  `exportCreditsAsCashuTokenDurable`. The wallet dialog keeps the
  sync spellings as the documented UI-convenience forms.
- Closed: **`insertAttestedDebitIfCovered` is now a SUFFICIENT gate
  (schema v8).** `credit_transactions.burned_attested` (REAL,
  default 0) records how much of each debit consumed the attested
  pool, computed by the same unattested-first rule at write time:
  ordinary debits persist the attested share they burn, attested
  egress debits persist their full amount, mints and PoR/storage
  penalty debits persist 0. The v7→v8 migration replays legacy rows
  in chronological order (`timestamp`, `rowid`) through the same burn
  rules and backfills the column; hydration derives identical values
  and `_attestedBurned` remains only an in-memory cache. The durable
  gate now computes held-key-scoped attested mints MINUS every
  durable attested burn, clamped by the durable ledger net - a
  stale-view sibling can no longer pass the gate with attested value
  an ordinary debit already consumed.
- Closed: **multi-PROCESS single-writer enforcement at the database
  layer.** `DatabaseFileGuard` acquires an OS advisory exclusive lock
  (`RandomAccessFile.lock(FileLock.exclusive)` - the non-blocking
  mode in this SDK) on `alexandria.sqlite.lock` BEFORE the
  file-backed executor opens and holds it for the process lifetime.
  Contention policy: FAIL LOUD - a `StateError` propagates out of
  `databaseProvider` rather than silently running a second writer.
  Re-acquiring the same path in-process returns the same handle (a
  static registry prevents false self-contention); process death
  releases the lock, so a crashed holder never strands the database.
  The guard is injectable via `databaseFileGuardProvider`, and
  contention is verified with a REAL second OS process in
  `test/data/single_writer_lock_test.dart` (dart:io file locks are
  per-process - two handles in one isolate can never conflict).
  PLATFORM BOUNDS: the lock is advisory - it coordinates
  cooperating Alexandria processes only; a foreign tool (sqlite3
  CLI, a non-Alexandria build) can still open and write the file.
  Network filesystems (NFS/SMB) may not honour local lock semantics -
  same-host multi-process is the covered threat. The FLUTTER_TEST
  in-memory executor path takes no lock (no file exists to contend
  for).

### Round-8 additions (consensus / scrubber / audit-log campaign-2 hardening)

- Closed: **per-vote signed biometric binding for `isHuman` ballots.**
  `BiometricService.attestVoteIntent` prompts for a REAL
  device-credential authentication (no fail-open escapes - unlike
  `authenticate`, biometrics-unavailable/dismissed/error all yield
  null) and mints a short-lived (2 min) HMAC-SHA256 token over
  `alexandria:vote-attestation:v1|voterKey|changeId|choice|issuedAt|nonce`,
  keyed by a 256-bit secret in secure storage
  (`vote_attestation_key_v1`, lazily created; ephemeral in-process key
  when no storage is wired). `ConsensusService.castVote` accepts
  `humanAttestationToken` and verifies it through the injected
  `VoteAttestationVerifier` (wired to
  `BiometricService.consumeVoteAttestation`) against THIS ballot's
  voter key, request id and choice: a forged, stale, future-dated,
  wrong-field or cross-changeId token REFUSES THE CAST outright - no
  silent downgrade to an AI-priced ballot, which would hide the
  forgery inside an ordinary vote. Verification consumes the token
  (single-use burn, pruned at TTL) so a copied token never attests a
  second ballot; consumption runs only after the
  pending/identity/duplicate checks so a rejected cast cannot burn an
  honest token. A verified token is pinned onto the minted ballot
  (`Vote.humanAttestation`, mintable only via the private
  `Vote._attested` constructor) and folded into the signed ballot data
  (`att:<token>` / `att:window` / `att:none`), so the ballot signature
  commits to WHICH evidence authorized it. The temporal
  `HumanAttestationClock` window remains as the compat fallback when
  no token is supplied - the token path dominates whenever available.
  Tests: `test/services/vote_attestation_test.dart` (forged /
  malformed / stale / future-dated / wrong-voter / wrong-choice /
  cross-changeId replay / single-use / unavailabile-biometrics all
  refuse; clock fallback still works when no token is presented).
- Closed: **scrubber-side input ceiling.** `MetadataScrubbingService`
  gained `maxInputBytes` (default `defaultMaxInputBytes` = 512 MiB -
  the same bound as the AddContentScreen ingest cap and the PNG
  chunk-walk safety margin: the walk trusts a 32-bit declared length
  per chunk, so inputs approaching 4 GiB turn that arithmetic into the
  steering surface; 512 MiB stays far under the ~2 GiB mark where
  declared lengths start steering reads, and bounds the two-buffer
  memory cost of parse+scrub). `scrubMetadata` throws `ArgumentError`
  BEFORE any parse or buffer copy - explicit refusal, never silent
  partial processing of a truncated view. Injectable for tests; all
  133 redteam scrubber contracts still green.
- Closed: **redundant audit-log head anchors (checkpoint
  anchoring).** The single secure-storage chain head could be deleted
  together with a file truncation, leaving a perfectly-verifying
  prefix. Three cooperating anchors now shrink what that adversary can
  do silently: (i) the secure-storage head
  (`audit_chain_head_v1`), (ii) a MAC'd sidecar head file
  (`<log>.head`, `v1|<seq>|<digest>|<hmac>` over
  `audit-head:v1|<seq>|<digest>`, rewritten on every signed write) -
  the reader takes the HIGHER-seq anchor so a rolled-back single
  anchor can never lower the expectation, and a
  same-seq/different-digest disagreement surfaces
  `audit_log_anchor_conflict`; (iii) in-file
  `audit_chain_checkpoint` lines every `checkpointEvery` (default 16)
  signed entries - chain members whose details record the predecessor
  head, verified on read like any line, so deleting one breaks the
  next line's prev link. Deleting every anchor while signed lines
  remain is itself surfaced (`audit_log_head_anchor_missing`), and
  with no external anchor the reader falls back to the last VERIFIED
  in-file checkpoint as a conservative head. RESIDUAL: tail-rollback
  by a persistent two-domain attacker holding a captured anchor pair
  cannot close without an external anchor - see Open residuals above.
  Tests: `test/services/audit_log_anchors_test.dart` (10 cases:
  sidecar persistence, checkpoint cadence, lying checkpoint flagged,
  storage-head deletion no longer blinds truncation, all-anchor
  deletion flagged, corrupted sidecar degrades, anchor conflict,
  unsigned files raise no flags, checkpoint-head recovery).

### Round-9 additions (agent-domain milestone closures)

- Closed: **production `BountyTransport` + cross-ledger bounty payout
  rail.** `MeshBountyTransport`
  (`lib/services/agent/mesh_bounty_transport.dart`) binds the transport
  seam to the real MAC'd mesh channel layer (`MeshTransportService` -
  unmodified): outbound Beacon envelopes are UTF-8 JSON fanned out only
  to reachable, channel-bound peers with per-peer dispatch failure
  isolation (`lastFanout` counts dispatches - "published" means handed
  to a proven mesh route, not remotely ACKed); inbound frames are
  size-capped, parsed, and surfaced through the same signature-checked
  ingest gates - the transport is never trusted. `releaseBountyEscrow`
  on the poster side treats a verified `BountyClaimEvent`
  (envelope-signer == claimant key, exact bountyId+CID binding) as
  settlement evidence and CONSUMES the escrow via a durable
  `tx_escrow_release_` tombstone - never a refund - so a remote claim
  cannot double-mint on both ledgers. Unproven escrows refuse
  (`refusedUnproven`); `operatorReconciliation: true` is the only
  refund path and goes through the public durable
  `CreditService.releaseEscrow`; verified evidence beats the operator
  flag. The production provider wires `MeshBountyTransport` into
  `moltbookServiceProvider`. Tests:
  `test/agent/mesh_bounty_transport_test.dart` (real cross-wired mesh
  instances - handshake → channel keys → sequenced HMAC frames →
  replay) and `test/agent/bounty_payout_rail_test.dart` (settlement
  tombstone, restart survival, duplicate idempotency, wrong-CID /
  wrong-signer / foreign-id refusal, no-evidence refusal, operator
  refund, verified-beats-operator, durable-evidence-only settle,
  supply conservation).
- Closed: **TUF-style threshold-signed release manifests (RFC §5.1
  machinery).** `lib/services/release/` implements the full verify
  chain: `ReleaseManifest` (min_wire_version, sequence, issued/expiry),
  `ManifestTimestamp` (manifest-hash + sequence bound,
  freshness-gated), canonical domain-separated preimages
  (`alexandria:release-manifest:v1:` /
  `alexandria:manifest-timestamp:v1:`), m-of-n Ed25519 threshold over
  DISTINCT keyIds (a signature flood is one vote), role separation
  (release keys cannot timestamp and vice versa), strict sequence
  advancement, raise-only floor ratchet (never lowers below the
  baseline or the last accepted floor), expiry + staleness refusal, a
  persisted-sequence injection seam, and a quorum-signer gate on the
  carrying Beacon envelope. `ReleaseKeyRegistry` is the injected trust
  root: `StaticReleaseKeyRegistry` defensively copies configuration;
  `EmptyReleaseKeyRegistry` - the production default via
  `releaseKeyRegistryProvider` - fails closed because wire data must
  never populate the signer quorum (Sybil-bootstrapping the trust root is
  the exact attack this prevents). `releaseManifestAuthorityProvider`
  is wired into `moltbookServiceProvider`, so `release_manifest`
  envelopes already route through the real ingest path; the remaining
  trigger is purely the operator quorum configuration (see Deferred
  milestones). Tests: `test/agent/release_manifest_test.dart` (20
  cases: forged / insufficient / duplicate / wrong-role signatures,
  floor lowering, rollback, stale timestamp, hash/sequence binding
  mismatch, persisted-sequence seam, empty registry, non-quorum
  envelope signer, malformed payloads).
- Adopted: **durable mutators on the remaining agent trust paths**
  (Round-7 SEAMs closed). `MoltbookService` bounty posting now debits
  through `debitEscrowDurable` and claim payouts through
  `awardBountyEscrowDurable` with a bounded `payoutWriteTimeout`; an
  indeterminate payout write dead-marks the bounty (tombstone +
  cancel set) rather than minting an unprovable claim.
  `alexandria_mcp_server`'s `_replicateCid` debits via
  `spendCreditsDurable` and `_exportCashuVoucher` via
  `exportCreditsAsCashuTokenDurable` - the sync optimistic spellings
  are no longer reachable from any trust-bearing agent path.
  Semantic changes this implies: a claim inside the credit-hydration
  window now PARKS on the durable mutator and pays after hydration
  completes (was: fast refusal - waiting is strictly better, the
  escrow still pays and never mints against a phantom ledger); and a
  CAS-lost claim row heals against the in-process `_paidBountyIds`
  belt as well as the durable payout row (covers a pure in-memory
  CreditService whose ledger cannot hold rows at all).

## Deferred milestones (with trigger conditions)

- **Release-manifest quorum configuration** - the RFC §5.1 machinery
  is implemented, wired and verified (Round-9), but the production
  registry defaults to `EmptyReleaseKeyRegistry`: no manifest can
  verify until an operator configures a ≥3-key signer quorum via
  `releaseKeyRegistryProvider` - from node configuration, NEVER wire
  data. Until then the floor stays the per-verifier compile-time
  constant; no central kill switch exists. This is the RFC's intended
  graduation step, not missing code.
- **Application-level bounty-delivery receipts** -
  `MeshBountyTransport` dispatch is best-effort by design:
  `lastFanout` counts frames handed to proven mesh routes, not remote
  acknowledgements. A remote-ACK receipt layer remains an open seam
  (the same bound `MeshTransportService.sendPayload` documents at the
  frame layer).

## Protocol state snapshot (post-residual-closure)

- Schema v8; durable CAS registries: `claimed_bounties`, `awarded_dois`;
  ledger CAS writes: `insertCreditTransactionIfAbsent`,
  `insertAttestedDebitIfCovered` (write-time held-key coverage gate -
  sufficient since v8: scoped mints minus every durable burn).
- `credit_transactions.attested_pubkey` scopes attested mints to the
  claiming prover key; NULL = unscoped legacy bucket.
  `credit_transactions.burned_attested` (v8) records each debit row's
  attested burn share; `alexandria.sqlite.lock` is the advisory
  single-writer lockfile (`DatabaseFileGuard`, fail-loud on
  contention).
- Trust-path mutators are durable-first: `spendCreditsDurable`,
  `debitEscrowDurable`, `awardBountyEscrowDurable`,
  `exportCreditsAsCashuTokenDurable`, `sweepToLightningAddressDurable`,
  the live sweep, `releaseEscrow`, `claimVerifiedReceipt` - returned
  success ⇒ a durably-committed row. The sync spellings remain
  documented optimistic UI-convenience forms.
- Deterministic ledger ids: `tx_bounty_payout_<id>` (payout proof + dedup),
  `tx_escrow_hold_<ref>_<micros>_<seq>` (non-forgeable hold),
  `tx_escrow_release_<id>` (release dedup + spent tombstone).
- `claimVerifiedReceipt` = possession-bound (claim-time signature over
  `alexandria:receipt-claim:v{v}:{receiptId}`, remote freshness form
  `...:{verifierNonce}:{expiry}`) + v3 issuance ack
  (`alexandria:receipt-ack:v{v}:{id}`) + version floor/ceiling +
  known-local-key self-vouch guard (covers retired rotation keys).
- `ingestWorkReceipt` = verified signature upgrade on unsigned rows;
  `upgradeWorkReceiptSignatures` = the conditional-write primitive.
- Bounty lifecycle: claim CAS → evidence → DURABLE payout
  (`awardBountyEscrowDurable`, bounded `payoutWriteTimeout`;
  indeterminate writes tombstone instead of minting unprovable
  claims) → mark; all cleanup deletes are `claimedAt`-conditional;
  tombstones and local sets rebuild from durable rows at init.
  Cross-ledger settlement: a verified `BountyClaimEvent` consumes the
  poster-side escrow via `tx_escrow_release_` tombstone (never a
  refund); only `operatorReconciliation: true` refunds, through
  `CreditService.releaseEscrow`.
- Verified baseline (post-campaign-2 refresh): `flutter analyze` 0
  issues repo-wide; `flutter test` **1876 green / 1 skipped / 0
  failures** (includes all 133 redteam adversarial PoCs and the
  312-test coverage suite); non-generated executable coverage
  **95.73%** (15237/15916 lines). Residual uncovered lines are
  platform-conditional branches (macOS/Windows-only), defensive
  fallbacks unreachable via public API, and fault-injection-only
  error paths - itemized in the coverage agent's final report.
