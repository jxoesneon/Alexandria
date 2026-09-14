# ALX-011: Persistent Receipt Economy — Attested Value, Work Receipts, and Egress Lockdown

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-011 |
| **Title** | Persistent Receipt Economy: Attested/Unattested Credit Split, Verifier-Signed Work Receipts, and Egress Lockdown |
| **Author** | Alexandria Core Team & Governance Review |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-11-21 |
| **Depends On** | ALX-004, ALX-005, ALX-006, ALX-010 |

---

## 1. Abstract

This specification canonizes the persistence and attestation layer shipped in commit `ffcdf21`. It formalizes:

1. **A persistent SQLite ledger** as the production substrate for the credit economy — balances, daily mint caps, DOI reward dedupe, and work receipts survive restarts.
2. **The attested/unattested credit split**: only value backed by a *foreign* verifier's signature may ever egress; self-certified value is internal-only.
3. **The `WorkReceipt` artifact**: a content-addressed, verifier-signed claim instrument with canonical JSON, sha256 identity, spend-dedup, and 24h expiry.
4. **The egress lockdown**: every ℭ→external-value path is gated on `attestedBalance`, and the gate is closed until the foreign-verifier attestation transport lands.
5. **Escrow integrity** for Moltbook bounties: net-zero post+claim cycles, funded-flag stripping, and rotation-proof self-claim guards.

---

## 2. Persistent Ledger Substrate

### 2.1 Storage

Production state lives in a single SQLite database at:

```
<application-support-directory>/alexandria.sqlite
```

opened lazily (`LazyDatabase` → `NativeDatabase.createInBackground`) so provider reads never block and unit tests never touch `path_provider`. First boot runs Drift's default `onCreate`; upgrades run the `schemaVersion = 3` migration. The `AppDatabase` constructor retains `NativeDatabase.memory()` as its default executor — only `databaseProvider` wires the file-backed executor, keeping tests hermetic.

### 2.2 ALX-011 Tables (schema v3)

| Table | Primary Key | Purpose |
| :--- | :--- | :--- |
| `credit_transactions` | `id` | Append-only ledger of every mint/debit, with `is_attested` flag and content hash |
| `daily_minted` | `(day_key, credit_type)` | Persisted daily mint-cap counters keyed by UTC day |
| `awarded_dois` | `doi` | Permanent dedupe registry — one ingest reward per DOI, ever |
| `work_receipts` | `receipt_id` | Verifier-signed work receipts with `spent` claim flag |

### 2.3 Hydration Semantics

On construction with a database attached, `CreditService` hydrates before any mutation is permitted:

1. **Mint-cap restore**: today's `daily_minted` rows merge with in-memory counters taking the **maximum** of either, so a counter can never be clobbered into under-recording (no restart-farming of the ~600 ℭ/day cap).
2. **Ledger replay**: the balance and attested balance are rebuilt by replaying `credit_transactions` chronologically — the ledger is the source of truth, so a restart can neither reset the balance nor re-grant genesis.
3. **Single genesis**: the welcome allocation uses the deterministic id `tx_genesis`; racing instances collapse onto one primary-key row. A ledger with activity but no genesis row receives exactly one.
4. **Unhydrated refusal**: in persistent mode, mutating entry points refuse to run until hydration completes — acting on phantom counters would bypass the daily cap and overspend the ledger.
5. **Best-effort write-through**: persistence failures are swallowed and logged; a broken database must never break a mint, but `settled` exposes write completion for shutdown paths.

---

## 3. Attested / Unattested Value Split

Every ledger row carries `is_attested`. The running attested balance is **net**, not gross:

$$\mathcal{C}_{\text{attested}}(t) = \max\!\Big(0,\; \sum \mathcal{C}^{+}_{\text{attested}} - \sum \text{burns}(t)\Big)$$

- **Mint**: `is_attested = true` only when the credit derives from a verifier-signed work receipt whose verifier pubkey differs from the claiming node's identity. All local mint paths (PoR self-check, compute, verification, sponsorship, genesis, escrow payout) write `is_attested = false`.
- **Debit**: every spend burns the *unattested* portion first, then attested (`_burnForDebit`). Attestation already consumed internally can never back a second egress.
- **Clamps**: `attestedBalance` is clamped to `[0, balance]`; `unattestedBalance = balance − attestedBalance` is clamped at zero so a partial ledger can never report negative internal value.

**Invariant**: the self-PoR loop is closed — a node can only ever sign receipts as its own identity key, and a receipt signed by the claimer carries zero attestation weight. Attested value requires a *foreign* verifier.

---

## 4. WorkReceipt Schema (v1)

### 4.1 Canonical Body

The signed body is the sorted-key JSON of every consensus field, **excluding** the receipt id, both signatures, and bookkeeping (`spent`, `created_at`). Adding or removing a signature therefore never changes `receiptId`.

| Field | Type | Notes |
| :--- | :--- | :--- |
| `v` | int | Schema version = `1` |
| `workType` | string | `'storage'` \| `'compute'` \| `'verification'` |
| `proverPubkey` | string | Ed25519 pubkey (hex/base58) of the node that performed the work |
| `verifierPubkey` | string | Ed25519 pubkey of the issuing verifier |
| `cid` | string? | Content the work applies to (PoR: challenged CID) |
| `chunkIndices` | int[] | Chunk indexes covered |
| `challengeNonce` | string | Hex-encoded challenge nonce |
| `responseTag` | string | Hex-encoded prover response tag (HMAC-SHA256) |
| `workUnitsMilli` | int | Work proven, in milli-units of the work type's natural unit (integer for JCS canonicalization safety) |
| `amountMilli` | int | Credit value the receipt entitles, in milli-credits |
| `epoch` | string | UTC day `'YYYY-MM-DD'` for daily mint accounting |
| `expiresAt` | int | Epoch milliseconds; claimable window = issuance + 24 h |
| `evidenceHash` | string? | sha256 binding to external evidence (PoR: proven chunk bytes) |

**Conformance note**: the shipped Dart encoder emits `workUnits`/`amount` as JSON numbers and treats `v` as implicit `1`. Emitters conforming to this RFC SHOULD use the integer `*Milli` forms for cross-implementation JCS compatibility; parsers MUST accept both spellings.

### 4.2 Identity & Signatures

- `receiptId = sha256_hex(utf8(canonical_json))` — content-derived, stable across platforms and key order.
- `verifierSig` = base64 Ed25519 signature over the canonical body bytes, attached *outside* the body.
- `proverSig` = optional prover counter-signature (base64).

### 4.3 Claim & Spend-Dedup

- A receipt is claimable once. The `spent` flag transitions `0 → 1` via an atomic compare-and-swap (`UPDATE … WHERE receipt_id = ? AND spent = 0`, checked by rows-affected) — the current build persists the flag via `markReceiptSpent` on the local-claim path; the conditional-update form is REQUIRED at the future `claimVerifiedReceipt` seam where foreign-prover receipts are claimed.
- **Local claim**: when the local node is the prover of record, the receipt's value mints through the normal capped storage path at unattested (1.0×) weight and the receipt is persisted `spent`.
- **Foreign-prover receipt**: persisted `UNSPENT`. It is the prover's claim instrument — minting it locally would pay the verifier for someone else's work.
- **Expiry**: receipts older than `receiptTtl = 24 h` cannot be claimed.

### 4.4 Receipt Amount

The recorded amount is exactly what the capped mint path would grant — a forked client's inflated self-declaration is worthless:

$$\text{amount} = \operatorname{clamp}\!\big(\text{MB}_{\text{proven}} \times 0.1 \times \omega_{\text{rarity}},\; 0.1,\; 50\big)\ \mathcal{C}$$

Locally issued receipts are always drafted at $\omega_{\text{rarity}} = 1.0$; attested rarity can only be baked in by a foreign verifier.

---

## 5. Foreign-Verifier Attestation Formula

A mint qualifies for attested weight iff:

$$\text{attested} \iff \text{isVerifierSigned} \;\wedge\; \texttt{verifierPubkey} \neq \texttt{localPubkey} \;\wedge\; \neg\,\text{isSelfIssued}$$

where `isSelfIssued ⇔ proverPubkey = verifierPubkey`. Consequences:

- Self-signed receipts prove storage integrity but claim only unattested value.
- The rarity multiplier escalator is attestation-gated: $\omega_{\text{rarity}} > 1.0$ requires `rarityAttested` — an independent peer's attestation of under-replication. A claimant's self-reported peer count can never unlock rarity rewards (self-dealing guard).

---

## 6. Egress Gate

Every ℭ→external-value path (Cashu export, simulated sweep, live Lightning melt, voucher redemption) evaluates `egressRejectionReason(credits)`:

$$\text{reject} = \begin{cases}
\text{'Invalid egress amount'} & \neg\,\text{isFinite}(c) \;\vee\; c \le 0 \\
\text{payoutsDisabledReason} & \neg\,\texttt{payoutsEnabled} \\
\text{attested-balance error} & c > \mathcal{C}_{\text{attested}} \\
\varnothing & \text{otherwise}
\end{cases}$$

- `CryptoBridgeService.payoutsEnabled = false` is the load-bearing compile-time gate; `AlexandriaMcpServer.agentPayoutsEnabled = false` is belt. Direct callers (wallet UI) cannot route around the service gate.
- The attested-balance requirement is wired **now**, behind the gate: when payouts open, only foreign-verified value can leave.
- Cashu voucher *redemption* is independently disabled until real mint verification (NUT-03 swap + `/v1/checkstate`) exists — a local spent-set is not proof of mint backing. Submitted secrets are absorbed into the spent-set so vouchers presented while disabled can never be replayed.

---

## 7. Escrow Integrity (Moltbook Bounties)

1. **Net-zero post+claim**: `debitEscrow` is a fee-EXEMPT hold — skimming the 5% treasury fee at post time would mint unbacked value on payout. Claim value = escrowed amount, exactly.
2. **Broadcast-first ordering**: the bounty post is broadcast *before* the escrow debit, so a broadcast failure can never strand credits behind an unclaimable bounty.
3. **Funded-flag stripping**: announcer-claimed `funded` flags are never honored on ingest. Foreign announcements are stored `funded: false` — display-only, unclaimable — unless the transport asserts a verified escrow attestation via the `escrowAttested` seam (never populated from wire data).
4. **Self-claim guard**: locally posted bounty ids are recorded in `locallyPostedBountyIds`, keyed off bounty id rather than the mutable agent identity — keypair rotation cannot launder a self-claim. Echoes of own posts are dropped.
5. **TOCTOU safety**: `isClaimed` is set synchronously before the first `await` and reverted only if the blockstore evidence check fails, so overlapping claims can never double-pay.
6. **Work evidence**: claiming requires the CID's bytes present in the local blockstore (non-empty payload) — proof the claimant actually replicated. Empty payloads are deliberately treated as absent.

---

## 8. Claimed Build Provenance

`BuildInfo.claimedBuildInfo` may be embedded in Beacon envelopes as `client_info`. Every key carries the `claimed_` prefix (`claimed_commit_sha`, `claimed_build_channel`, `claimed_artifact_digest`, `claimed_build_timestamp`) so nothing downstream can mistake self-declared provenance for verified provenance.

**Invariant**: claimed build metadata carries ZERO trust weight. It must never gate admission, rewards, verification, or any security decision. The only enforceable trust primitive remains peer-verified Ed25519 signatures over Beacon envelopes.

---

## 9. Daily Mint Caps

Persisted per UTC day via `daily_minted` (survives restarts):

| CreditType | Cap (ℭ/day) |
| :--- | :--- |
| `storageReward` | 200 |
| `computeReward` | 150 |
| `verificationReward` | 100 |
| `sponsorshipKickback` | 150 |

Escrow payouts (`awardBountyEscrow`) are not mints and bypass caps by design.

---

## 10. Deviations from ALX-005

| ALX-005 Clause | Shipped ALX-011 Behavior | Rationale |
| :--- | :--- | :--- |
| §4.1 base factor $\kappa_s = 10^{-6}$ ℭ/MB-day | Effective factor $0.1$ ℭ/MB per proven challenge, clamped $[0.1, 50]$ | Receipt amounts must match the live mint path; $\kappa_s$ recalibration deferred to the foreign-verifier milestone |
| §6.2 timed responses $>1500\text{ ms}$ rejected | Challenge `TTL = 5` min; no RTT bound enforced | A fixed 1500 ms window is meaningless until challenges are issued by remote verifiers; the verifier-side RTT bound is deferred to the foreign-verifier milestone |
| §4.1 rarity multiplier self-applied | $\omega_{\text{rarity}} > 1$ requires `rarityAttested` | Self-reported peer counts are unverifiable; self-dealing guard |
| §6.1 caps in-memory | Caps persisted to `daily_minted` | Restart-farming of the daily cap is closed |

---

## 11. Deferred Work

- `claimVerifiedReceipt` seam: claiming foreign-prover receipts as attested value, with conditional spent CAS.
- Escrow attestation transport: populating `escrowAttested` after out-of-band verification of the poster's signed escrow attestation.
- Remote-verifier RTT bound for PoR challenge responses.
- Real Cashu mint verification (NUT-03 swap + `/v1/checkstate`) before voucher redemption re-opens.
