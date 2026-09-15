# ALX-012: Version Enforcement at the Proof Layer — Receipt Wire Versions, Epoch Domain Separation, and the Claim-Time Floor

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-012 |
| **Title** | Version Enforcement at the Proof Layer: Receipt Wire Versions, Epoch Domain Separation, and the Claim-Time Floor |
| **Author** | Alexandria Core Team & Governance Review |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-11-22 |
| **Depends On** | ALX-005, ALX-006, ALX-010, ALX-011 |

---

## 1. Abstract

This specification canonizes the Review-of-Five decision on protocol version enforcement. Its single organizing result:

> **Version enforcement binds only at the proof layer** — at the point where a party the attacker does not control applies the check.

Every mechanism that tries to enforce a version against a *self-declared* value fails, because the declaration itself is attacker-controlled. Enforcement therefore lives where Alexandria's only trust primitive already lives: inside verifier-signed artifacts, checked at claim time by the verifier's own policy. This RFC formalizes:

1. **A per-receipt wire-version field `v`** carried inside the signed body (already present as `v = 1` in ALX-011 §4.1; here made load-bearing).
2. **Epoch-domain separation**: a version-bound `alexandria:receipt:v{v}:` prefix in the signing preimage, so artifacts from one wire epoch can never be replayed or forged into another.
3. **The claim-time floor** `minClaimableWireVersion`: a per-verifier policy constant — explicitly *not* a central kill switch (Safety B4) — with a grace window of `{current−1, current}` bounded by the receipt 24 h TTL.
4. **Emergency retirement** of a wire epoch = bumping the floor constant.
5. **Parse tolerance**: receipts with unknown `v` are representable but unclaimable below the floor — the anti-ossification lesson of RFC 9170.
6. **`claimed_client_version`** (Review B3-lite): an advisory, self-declared semver injected via `--dart-define=ALX_CLIENT_VERSION`, riding the existing `claimed_*` provenance channel with zero trust weight.

Deferred with spec: the TUF-style review-signed release manifest that graduates the floor's authority (§5.1, now with a trigger condition), the real MCP stdio runner's mandatory safety conditions (§5.2, refined §5.6), and the vetoed `measuredLatencyMs` field (§5.3). Resolved in Review REV3: possession-proof claim binding (§5.4), durable bounty-claim dedup, ambient `trustedAttestorPubkeys`, narrowed `client_info` broadcast, and the `claimed_protocol_version` rename (§5.5). Resolved in Review REV4: crash-window claim reconciliation, CAS-loser lazy sync, identity-rotation self-vouch guard, bounded `_bounties`/`_pendingChallenges`, escrow release, envelope-aware ingest, and the wire-bump checklist (§5.7).

---

## 2. Core Theorem: Enforcement Binds Only at the Proof Layer

**Theorem (Review research synthesis).** A version gate is effective iff it is evaluated by a party whose behavior the attacker cannot dictate, over evidence the attacker cannot fabricate. Equivalently: enforcement binds only where the check is applied *to* the attacker's artifact *by* someone else's rules engine — the proof layer.

Three corollaries:

- **Self-declared versions bind nobody.** A field the emitter controls (`User-Agent`, `agentVersion`, `claimed_client_version`) can be set to whatever the gate wants. Gating on it is security theater.
- **Negotiation is not enforcement.** Protocol negotiation selects a mutually intelligible encoding; it cannot compel an upgrade, because both endpoints agree to whatever they both speak.
- **Proof-carrying artifacts bind.** When validity of a *signed, content-committed artifact* is conditional on rules the verifier controls, the attacker cannot satisfy the new ruleset without actually implementing it.

### 2.1 Evidence

| System | Enforcement Locus | Mechanism | Lesson |
| :--- | :--- | :--- | :--- |
| **Bitcoin** | Consensus rules on block content, applied by every full node | Blocks are valid or not under the node's own ruleset; the `/Satoshi:x.y.z/` subver user-agent is never consulted. BIP148's UASF was a flag day on *block content* (rejecting non-segwit-signaling blocks after 2017-08-01), not on peer strings | Enforcement = validation refusal by independent verifiers of attacker-submitted artifacts |
| **libp2p multistream-select** | Negotiation only | Peers agree a protocol id; the identify `agentVersion` field is informational dead weight — no implementation gates on it | Negotiation picks an encoding; it is structurally incapable of compelling upgrades |
| **Matrix room versions** | Server-side validation refusal + tombstone | Homeservers refuse events non-conformant to the room's version; `m.room.tombstone` repoints the room to a replacement under a new version | The *room* (shared object) carries the version; every server independently validates against it, and migration is an explicit, signed-over artifact |
| **Ethereum `forkId` (EIP-2124)** | Proof-of-ruleset in the handshake | `forkId = {hash of fork blocks, next fork}` commits a node to the exact fork history it validates; peers reject incompatible rulesets. Grace via accepting `{current, previous}` fork digests during a transition window | A compact digest *proves* which ruleset you run — claiming a fork you don't validate is detectable, not just dishonest |
| **Signal 499** | Claimed-version gate | The enforcement attempt was bypassed by editing a user-agent string | The canonical counterexample: a gate reading attacker-controlled strings binds nobody and teaches the network to lie |
| **Tor dirauths** | Consensus vote + de-listing | Directory authorities vote `required-protocols`/`recommended-protocols` lines into the consensus; relays failing required protocols lose their listing | Version policy is decided by an independent quorum and enforced by omission from the directory — a floor, not a negotiation |

The pattern is uniform: **Bitcoin, Matrix, Ethereum, and Tor all enforce by having parties the attacker doesn't control apply rules to artifacts the attacker must produce. libp2p doesn't enforce at all. Signal 499 enforced on a claimed string and was routed around trivially.**

---

## 3. Design: Wire Versions on the Receipt Artifact

The receipt is Alexandria's proof-carrying artifact (ALX-011 §4): content-addressed, verifier-signed, single-claim, 24 h-lived. Version enforcement attaches there — never to Beacon `client_info`, user-agent strings, or handshake metadata.

### 3.1 `v` as a Per-Receipt Signed Field

`v` is a field of the signed body (ALX-011 §4.1, `v: int = 1`). Because it is inside the canonical body, it is committed by `receiptId = sha256(utf8(canonical_json))` and by `verifierSig` — the verifier declares, under its own key, which wire epoch it issued the artifact under. A prover or relay cannot rewrite `v` without invalidating both the content hash and the signature.

### 3.2 Epoch-Domain Separation

For wire versions `v ≥ 2`, the signing preimage is domain-prefixed:

$$\text{preimage}(v) = \texttt{utf8}\big(\texttt{'alexandria:receipt:v'} \;\Vert\; v \;\Vert\; \texttt{':'} \;\Vert\; \text{canonical\_json}(\text{body})\big)$$

Consequences:

- **No cross-epoch replay.** A v1-era artifact (bare `utf8(canonical_json)` preimage) can never verify under the v2 domain, and vice versa. The version is bound into the signature scheme itself, not just a checkable integer.
- **Old clients structurally cannot forge new-epoch artifacts.** A client whose signer only emits the v{n} preimage scheme cannot produce a valid v{n+1} receipt — producing one requires implementing the new epoch's scheme, at which point the emitter *is* a new-epoch client subject to the new rules. This is the constructive half of the core theorem: the upgrade is enforced by cryptographic impossibility, not by inspecting claims.
- **Receipts in flight at the v1→v2 boundary** verify under the legacy (unprefixed) scheme only, and only until the floor in §3.3 closes the grace window.

### 3.3 The Claim-Time Floor

Each verifier (and each claim path evaluating a receipt) holds a policy constant:

$$\texttt{minClaimableWireVersion} \in \mathbb{N}$$

A receipt is claimable at wire version `v` iff:

$$\texttt{claimable}(r) \iff r.\texttt{v} \ge \texttt{minClaimableWireVersion} \;\wedge\; \text{verify}(r) \;\wedge\; \neg\,\texttt{spent} \;\wedge\; \texttt{now} \le r.\texttt{expiresAt}$$

Policy properties:

- **Evaluated at claim time, not ingest time.** Below-floor receipts may be received, stored, and displayed; they simply cannot mint. This keeps the floor a *value* gate — the only place where a version must bind — and keeps parsing forward-compatible (§3.5).
- **Per-verifier, per-node policy constant.** There is deliberately **no central kill switch** (Safety B4): no key, endpoint, or broadcast that can remotely disable a wire version across the network. Each verifier's floor is its own; the network's effective floor is the emergent minimum across verifiers whose attestations carry economic weight.
- **Grace window = `{current−1, current}`.** During a transition, verifiers issue at `current` while the floor sits at `current−1`. Because receipts expire 24 h after issuance (ALX-011 §4.3), the overlap is self-bounding: after a floor bump, stale-epoch receipts drain within one TTL and cannot be renewed at the old epoch (issuance has moved on). No permanent multi-version drift, no abrupt flag-day invalidation of receipts already in flight — the Ethereum `{current, previous}` fork-digest grace applied to a TTL'd artifact.

### 3.4 Emergency Retirement

Retiring a compromised or deprecated wire epoch is the single operation:

$$\texttt{minClaimableWireVersion} \leftarrow \texttt{current}$$

—a constant bump shipped in a client release. Old-epoch receipts stop being claimable at upgraded verifiers immediately and become universally unclaimable within 24 h as they expire. Because the floor is per-verifier, retirement is a *socially coordinated, cryptographically enforced* act — the Tor dirauth model (a floor decided by independent policy, enforced by refusal) rather than a remote kill switch.

### 3.5 Parse Tolerance (Anti-Ossification)

Parsers MUST represent receipts with `v` greater than any epoch they implement: the field is an integer, the body is canonical JSON, and unknown-version receipts are well-formed data. They are simply unclaimable while `v < minClaimableWireVersion` — i.e., unknown-`v` receipts are *representable but unclaimable below the floor*. This is the RFC 9170 lesson (*Long-Term Viability of Protocol Extension Mechanisms*): extension points that hard-fail on unrecognized values ossify the protocol and strand future migrations. A node that can *parse* a v3 receipt today can be patched to *claim* it tomorrow without a wire-breaking change.

---

## 4. `claimed_client_version` — Advisory Only (Review B3-lite)

`BuildInfo` gains a self-declared client semver, injected at compile time:

```
flutter build --dart-define=ALX_CLIENT_VERSION=1.4.2
```

surfacing as `claimed_client_version` inside `claimedBuildInfo` (the `client_info` block of signed Beacon envelopes). It follows the existing `claimed_` contract exactly: clearly-non-official default `'dev'`, signed *as content* so post-hoc tampering is detectable, and **zero trust weight by invariant (ALX-010 / ALX-011 §8)**.

**Invariant (restated).** `claimed_client_version` MUST never feed admission, rewards, verification, the §3.3 floor, or any gate. Its only lawful uses are debugging, protocol-compat display (e.g., the Agent Network dialog's claimed-build line), and quarantine heuristics for known-bad builds. The Signal 499 evidence (§2.1) is the reason this clause exists: the moment a claimed string gates anything, rational adversaries lie, and the gate becomes a loyalty test for cheaters.

---

## 5. Deferred Work (with Spec)

### 5.1 TUF-Style Review-Signed Release Manifest

The floor's authority graduates in three stages:

$$\texttt{constant} \;\rightarrow\; \texttt{verifier policy} \;\rightarrow\; \texttt{threshold-signed manifest}$$

The terminal stage is a release manifest signed by a review threshold:

| Field | Type | Notes |
| :--- | :--- | :--- |
| `min_wire_version` | int | The floor this manifest asserts |
| `sequence` | int | Monotonic; a manifest only supersedes strictly-lower sequences (rollback resistance) |
| `expiry` | int | Epoch milliseconds after which the manifest is stale and ignored (prevents indefinite pinning by an abandoned manifest) |
| `signatures` | sig[] | Threshold *t-of-n* over review verifier keys, TUF-style |

Until the manifest transport lands, the floor remains a per-verifier compile-time/policy constant — which is safe by construction because no manifest mechanism means no central lever exists to abuse.

**Trigger condition (Review REV4):** the manifest ships when (i) an attestor quorum of ≥3 independent keys is configured in production, (ii) a signed-manifest transport exists (the same Beacon-envelope channel that carries bounty announcements; TUF's timestamp/freshness role maps to an online review key), and (iii) the first wire-floor bump has been socially required. Earlier construction adds a central lever before anything needs governing.

### 5.2 Real MCP stdio Runner — Mandatory Preconditions

A production stdio runner for `AlexandriaMcpServer` is gated on ALL of:

1. **Session-scoped auth** — the runner authenticates the controlling session; tools are not ambiently invocable.
2. **Per-tool rate budgets** — independent budgets per tool, not a single global cap.
3. **Spend/escrow ceilings with human consent** — any tool path that can debit or escrow ℭ requires an explicit human-consent surface with bounded ceilings.
4. **Receipt ingest OFF the tool surface** until in-path signature verification exists — an agent must never be able to feed a receipt into the claim path through a tool call before the verification seam (ALX-011 `claimVerifiedReceipt`) is real.

### 5.3 `measuredLatencyMs` — VETOED

A4's `measuredLatencyMs` is **vetoed as caller-supplied**: a self-declared latency is a `claimed_*` value wearing a numeric costume and carries zero trust weight (same failure as Signal 499). A *verifier-measured* RTT — stamped by the verifier inside the signed body at issuance — MAY ride the receipt at the next wire bump (`v = 2`), where it becomes evidence the verifier attests, not a claim the prover makes.

### 5.4 Possession-Proof Binding for `claimVerifiedReceipt` — RESOLVED (Review REV3)

~~`CreditService.claimVerifiedReceipt` takes `localPubkeyHex` as a **caller-supplied string**.~~ **Implemented.** Two changes landed per the REV3 verdict:

1. **Injected identity resolver** — `CreditService` takes a `localProverPubkeyHex` resolver callback wired to `IdentityService` in the provider (ambient authority, matching the `ReceiptSignatureVerifier` idiom). The call site can no longer assert a prover key.
2. **Claim-time possession signature** — `claimVerifiedReceipt` requires `claimSignatureB64`: an Ed25519 signature, verified in-path under `receipt.proverPubkey`, over the domain-separated preimage `alexandria:receipt-claim:v{v}:{receiptId}`. `receiptId` is the SHA-256 of the canonical body, so the signature binds every field; the CAS (`UPDATE … WHERE spent=0`) already enforces single-consumption, so replaying a claim signature is harmless (no nonce needed until *remote* claims exist — see below).

**Review correction to the earlier draft:** artifact-carried `proverSig` is **not** the anti-theft mechanism — a stored signature travels with a copied artifact, so verifying it preserves bearer-ness. Its real value is *issuance-time provenance* (a verifier cannot mint a claimable receipt naming prover P without P's counter-signature). `proverSig` therefore stays optional and unverified until a wire bump defines its domain (`alexandria:receipt-ack:v{v}:`) and an issue→ack flow; the claim-time signature is the possession proof.

**Residuals:** `attestedBalance` is wallet-scoped, not `proverPubkey`-scoped — correct under the single-identity model; if multi-identity lands, `credit_transactions` gains `attested_pubkey` and the egress gate sums only over currently-held keys (`LocalProverPubkeyResolver`'s single-`String` signature is the forcing point). Identity **rotation** is now guarded: `IdentityService` keeps a persistent `knownLocalPubkeys` history, and `claimVerifiedReceipt` refuses any verifier key the node has ever held — a receipt signed by a retired local key can no longer self-vouch as "foreign". Rotation also orphans unclaimed receipts naming the retired prover key — expected consequence of possession binding, not a bug. When claims become *remote* (presented to another node), freshness needs a DPoP-style nonce/expiry in the claim preimage — the current static claim signature relies on the CAS for replay safety.

Related cosmetic note — **the MCP `receipt_attested` report is a syntactic read.** `AlexandriaMcpServer` surfaces `receipt.isAttestedClaim`, which composes the *syntactic* `isSelfIssued` (literal `==`). A case-variant self-issued receipt can therefore *report* `attested_claim: true` — misreporting only: the claim path re-evaluates all identity compares through the canonical `WorkReceipt.samePubkey` and refuses regardless. (The analogous Moltbook self-claim guards were canonicalized to `_sameAgentId` in REV3 — this class is closed there.)

### 5.5 Review REV3 Resolutions — Bounty Integrity, Trust Roots, Broadcast Metadata

Third-round caveats adjudicated by the review board; implementation landed alongside this RFC:

- **Bounty claim durability (Safety veto, resolved):** `PreservationBounty.isClaimed` was a public mutable field and `activeBounties` returned the live stored records — a retained reference could flip `isClaimed=false` post-claim and `awardBountyEscrow` (which deduplicated nothing) paid again: unbounded re-mint from one funded announcement. Fix: a persisted `claimed_bounties` registry (insert-or-ignore CAS, mirroring `awarded_dois`) is the authoritative claim gate — restart + re-announcement cannot double-pay; evidence-failure deletes the row to preserve retry semantics. `activeBounties`/`postPreservationBounty` return defensive copies, and `awardBountyEscrow` additionally dedups on `bountyId` so the payout primitive is safe even if the claim layer is bypassed.
- **`trustedAttestors` is ambient config, not a call parameter.** The per-call trust root was a footgun — every future transport call site would be one mistake away from passing announcement-derived data (the full Sybil surface). `MoltbookService` now takes `trustedAttestorPubkeys` at construction (default empty → fail-closed). When the transport lands it supplies *attestations*; the trust root graduates operator pin → threshold-signed manifest (§5.1 machinery, same TUF shape as the version floor). Wire data must never populate it.
- **`client_info` now broadcasts a narrowed subset.** `createPost` embeds `BuildInfo.claimedBroadcastInfo` — `claimed_client_version`, `claimed_build_channel`, `claimed_protocol_version` only. Exact commit SHA, artifact digest and build timestamp stay local: broadcasting them would let a peer scan the swarm for known-vulnerable builds and correlate `bcn_*` agent ids with developer commit activity. Advisory forever — never admission, rewards, or gates.
- **`protocol_version` → `claimed_protocol_version`.** The last unprefixed key violated the `claimed_` contract it documented; renamed before any consumer existed.
- **`PreservationBounty.fromJson` stays faithful.** Sanitizing the decoder would split the trust boundary `ingestBountyAnnouncement` deliberately concentrates (fresh copies, `isClaimed:false`, `funded` only via trusted attestation) and would silently drop legitimate claim state when local persistence lands. Deferred idea: an envelope-aware `ingestBountyEnvelope` that verifies the signed envelope and requires `envelope.agentId == bounty.originAgentId` before deriving internal state.

### 5.6 Real MCP stdio Runner — Refined Spec (still gated)

§5.2's four preconditions stand; Review REV3 refined the shape for when it ships:

- **Start read-only.** An allowlist of non-economic tools (`search_archive`, `get_wallet_balance`, `request_por_challenge`) makes conditions 3–4 near-vacuous; minting/spending tools stay off until budgets and ceilings exist.
- **Session credential, not process existence.** A per-process generated token (never stored in exported config) gates every request; `initialize`/stdio-open is not a session boundary.
- **Known residual surface if tools widen later:** regex-only DOI validation farms to the daily cap; `post_moltbook_bounty(force:true)` escrows real balance (REV4 added `releaseEscrow`/`cancelBounty` for locally-posted unclaimed bounties — the *agent-driven* post path still needs consent ceilings); `replicate_cid` spends; `_pendingChallenges` is now bounded (REV4).
- Prefer a thin stdio shim to an authenticated local control socket of the running node over a second ProviderContainer instance.

### 5.7 Review REV4 Resolutions — Reconciliation, Rotation Guard, Bounded Surfaces

- **Crash-window reconciliation.** The durable `claimed_bounties` CAS row could outlive a crashed process with no payout (claim locked forever, escrow stranded). Three layers closed it: (a) `claimBounty` bounds the settle wait (16 event-loop turns / 30 s) then probes `hasCreditTransaction('tx_bounty_payout_<id>')` — a returned-`true` claim provably has its payout row or a durable zero-amount `tx_escrow_release_<id>` tombstone making the id permanently un-payable/un-refundable; (b) pending tombstones retry at init and each claim entry (a `static Expando` keyed on the shared `AppDatabase` lets a fresh service finish a crashed predecessor's tombstone); (c) a startup sweep plus lazy reclaim in the CAS-loss branch delete claim rows lacking a payout row **via direct `credit_transactions` queries** — never the hydration-windowed `_paidBountyIds`. Dedup sets themselves hydrate from targeted prefix listings (`getCreditTransactionIdsWithPrefix`), so rows beyond the 100k replay window can no longer re-mint or strand.
- **CAS-loser lazy sync + ownership-safe deletes.** On CAS loss, an existing payout row means the claim durably settled → mark claimed; a stale (>15 min) row with no payout row is deleted via `deleteClaimedBountyIfClaimedAt` (the observed `claimedAt` is the ownership guard — a racing claim's fresh row survives) and the CAS retried once; a fresh row means a claim is in flight. NO bare `deleteClaimedBounty` remains on any self-cleanup, sweep, or healer path.
- **Identity-rotation self-vouch guard.** `IdentityService` persists `knownLocalPubkeys` — every key ever installed, recorded on install, on served read, AND on the outgoing key before replacement/deletion (a never-read retired key still can't self-vouch). `claimVerifiedReceipt` refuses receipts verifier-signed by ANY known-local key.
- **Bounded surfaces.** `_pendingChallenges` (PoR, cap 256) and `_bounties` (Moltbook, cap 512) purge-expired-then-evict-oldest; locally-posted records are eviction-immune so their escrow stays reachable. The duplicate unbounded challenge map in `SecurityOverviewService` was deleted (delegates to the PoR service).
- **Escrow release.** `releaseEscrow(referenceId)` refunds a locally-posted, still-unclaimed bounty hold. Hold rows carry non-forgeable ids `tx_escrow_hold_<ref>_<micros>_<seq>` (pre-REV4a rows match via exact `Bounty Escrow Hold (<ref>)` description — unforgeable since `spendCredits` always appends its fee suffix). Release refuses when the id is paid (`_paidBountyIds` + durable probe, re-checked inside the atomic region) or already released (`tx_escrow_release_<id>` dedup); `awardBountyEscrow` refuses released ids. `cancelBounty` releases local unclaimed bounties; cancel/post/claim/ingest all consult the cancelled∪released tombstone, and `_locallyPostedBountyIds`/`_cancelledBountyIds`/`_escrowedBountyIds` are rebuilt from durable hold/release rows at init — cancels and tombstones survive restart.
- **Envelope-aware ingest.** `ingestBountyEnvelope` verifies the signed `BeaconEnvelope`, checks the kind allowlist, and canonically binds `envelope.agentId == bounty.originAgentId` before deriving internal state — the funnel the future transport drops into. Until a transport exists, **every `originAgentId` is unattributed self-claim** and must be treated as decorative.
- **Wire-hygiene rejection.** Bounty ids rejecting empty, whitespace anywhere, >128 chars, C0/C1/DEL, and the invisible/format class: 00AD, 034F, 061C, 115F–1160, 180E, 200B–200F, 2028–202F, 205F–206F (bidi overrides, isolates, invisible operators), 3164, FFA0, D800–DFFF, FEFF, FFF0–FFF8, 1BCA0–1BCA3, E0000–E0FFF. Raw `==` semantics are load-bearing (`bindsBounty`); nothing is normalized.
- **Non-finite amount guards.** Every credit entry point refuses `!amount.isFinite` — NaN previously defeated all comparison guards and cascaded to unbounded drain.

### 5.8 Wire-Bump Checklist (v3+ — spec only)

The procedure for the next wire-version change, so it isn't re-derived under pressure:

1. New domain constants: `alexandria:receipt-ack:v{v}:` (issuance-time prover counter-signature giving `proverSig` its semantics) and the extended claim preimage `alexandria:receipt-claim:v{v}:{receiptId}:{verifierNonce}:{expiry}` (DPoP-style freshness for *remote* claims — RFC 9449 `jti`/`iat`/`nonce` template).
2. Canonical-body field additions ⇒ bump `wireVersion` and coordinate `minClaimableWireVersion` per §3.3–3.4 (grace = {previous, current}).
3. The issue→ack flow: verifier issues → prover counter-signs → claim becomes possible. Outstanding unsigned receipts ride out the 24 h TTL.
4. Verifier-challenge nonce issuance for remote claims (server-chosen, per RFC 9449 `DPoP-Nonce`).
5. Parse-tolerance tests for unknown `v` (§3.5) must accompany every bump.
6. `insertWorkReceipt` caveat for the transport milestone: it is a trust-free `insertOrIgnore` write — first-insert-wins means an earlier unsigned row blocks a later signed redelivery of the same `receiptId` (availability quirk, not exploitable); any remote ingest path must route through `claimVerifiedReceipt`'s guards rather than pre-digesting `spent` state.

## 6. Deviations

| Proposal / Prior Clause | ALX-012 Decision | Rationale |
| :--- | :--- | :--- |
| Gate on client-reported version / user-agent (Signal-499-style) | Rejected outright; `claimed_client_version` is display/quarantine-only (§4) | Claimed strings bind nobody; gating on them teaches the network to lie |
| Central kill switch for wire epochs | Rejected; floor is a per-verifier policy constant (§3.3) | Safety B4: no single lever can remotely disable versions network-wide; retirement is coordinated, not dictated |
| Hard flag-day cutover | Grace window `{current−1, current}` at claim time (§3.3) | Ethereum `{current,previous}` fork-digest model; TTL'd artifacts make the overlap self-bounding at 24 h |
| Reject/parse-fail unknown `v` | Representable but unclaimable below floor (§3.5) | RFC 9170 anti-ossification: hard-failing unknown versions strands future migrations |
| ALX-011 §4.1 `v` as passive schema tag | Made load-bearing: committed field + epoch-domain preimage + claim-time floor | The artifact already carries `v`; enforcement attaches where the signature already is |
| `measuredLatencyMs` (A4) | Vetoed as caller-supplied; verifier-measured RTT deferred to next wire bump (§5.3) | Self-declared telemetry is a claimed value; only verifier-stamped evidence carries weight |

---

## 7. Invariants Summary

1. Version enforcement binds only at the proof layer — verifier-checked, artifact-committed, claim-time.
2. `v` is inside the signed body; `alexandria:receipt:v{v}:` binds the epoch into the preimage.
3. The floor is a per-verifier constant. There is no central kill switch.
4. Emergency retirement = bump the floor; stale receipts drain within one 24 h TTL.
5. Unknown-version receipts parse but cannot claim below the floor.
6. `claimed_client_version` is advisory forever: display, debugging, quarantine heuristics — never a gate.
