# Working On — Known Residuals & Deferred Work

This file tracks the honest residuals carried forward from the ALX-010–012
security rounds (review board + adversarial evaluation loops) and the
deferred milestones with their trigger conditions. Everything listed here is
*deliberately* open — each item has a reason it isn't done yet, not just an
oversight. See `docs/rfcs/ALX-012-version-enforcement.md` §5 for the full
reasoning.

## Open residuals (known limitations, documented bounds)

- **Beyond-window hold rows are unreachable by `releaseEscrow`'s in-memory
  scan.** Dedup sets (`_paidBountyIds`, `_releasedEscrowIds`) hydrate from
  targeted prefix listings (`getCreditTransactionIdsWithPrefix`), but the
  hold-amount scan still iterates the 100k-row replay window. An escrow hold
  older than the window can't be refunded at the service layer. Close with a
  hold-listing DAO (prefix + `referenceId` match returning amounts) — small,
  unscheduled until escrow volume makes the window a real bound.
- **Multi-instance stale-view artifacts.** Two `CreditService` instances on one
  database can hold divergent dedup sets (e.g. a stale-view instance may
  re-refund in memory while the canonical ledger keeps one row). Documented
  single-process db-ownership assumption; if multi-process access is ever
  supported, reconciliation must be redesigned around the SQLite connection,
  not the in-memory sets.
- **Combining-mark / NFC spoofing of bounty ids** (`e` + U+0301 vs `é`) is out
  of scope for `_isCanonicalBountyId` — the gate now covers C0/C1/DEL,
  whitespace, bidi overrides, isolates, tag chars, and invisible format
  codepoints, but not canonical-equivalence attacks. Raw `==` is load-bearing
  (`bindsBounty`); revisit only if a transport makes ids adversary-chosen at
  scale.
- **`insertWorkReceipt` first-insert-wins** — a trust-free `insertOrIgnore`
  write means an earlier unsigned row blocks a later signed redelivery of the
  same `receiptId` (availability quirk, not exploitable). Any remote ingest
  path must route through `claimVerifiedReceipt`'s guards.
- **`attestedBalance` is wallet-scoped, not prover-key-scoped** — correct under
  single-identity; if multi-identity lands, `credit_transactions` gains
  `attested_pubkey` and the egress gate sums over currently-held keys
  (`LocalProverPubkeyResolver`'s single-`String` signature is the forcing
  point).
- **MCP `receipt_attested` is a syntactic read** — `isSelfIssued` composes a
  literal `==`; a case-variant self-issued receipt can *report*
  `attested_claim: true`. Misreporting only: the claim path re-evaluates via
  `samePubkey` and refuses.

## Deferred milestones (with trigger conditions)

- **MCP stdio runner** — deferred pending: session-scoped auth token,
  per-tool rate budgets, spend/escrow ceilings with human consent, and an
  authenticated local control socket (thin-shim design preferred over a second
  ProviderContainer). Read-only allowlist first; no financial tools initially;
  receipt ingest excluded until signed-claim verification is wired. Refined
  spec: RFC §5.2 + §5.6.
- **`proverSig` issuance acknowledgment** — artifact-carried sig is provenance,
  not anti-theft. Wire bump defines `alexandria:receipt-ack:v{v}:` domain +
  issue→ack flow. Checklist: RFC §5.8.
- **DPoP-style freshness for remote claims** — claim preimage gains
  `{verifierNonce, expiry}` (RFC 9449 template) when claims are presented to
  other nodes; the CAS handles replay locally today.
- **TUF-style threshold-signed release manifest** — ships only when (i) an
  attestor quorum of ≥3 independent keys is configured in production, (ii) a
  signed-manifest transport exists (the Beacon-envelope channel; timestamp
  role maps to an online review key), and (iii) the first wire-floor bump is
  socially required. Until then the floor stays a per-verifier compile-time
  constant — no central kill switch. RFC §5.1.
- **Multi-identity attested-balance sharding** — per the residual above.
- **Full remote transport + verified bounty claim events** — the
  `ingestBountyEnvelope` seam is built and waits for the transport caller;
  every `originAgentId` is unattributed self-claim until then.

## Protocol state snapshot (post-REV4)

- Schema v5; durable CAS registries: `claimed_bounties`, `awarded_dois`.
- Deterministic ledger ids: `tx_bounty_payout_<id>` (payout proof + dedup),
  `tx_escrow_hold_<ref>_<micros>_<seq>` (non-forgeable hold),
  `tx_escrow_release_<id>` (release dedup + spent tombstone).
- `claimVerifiedReceipt` = possession-bound (claim-time signature over
  `alexandria:receipt-claim:v{v}:{receiptId}`) + version floor/ceiling +
  known-local-key self-vouch guard (covers retired rotation keys).
- Bounty lifecycle: claim CAS → evidence → payout → settle-probe → mark; all
  cleanup deletes are `claimedAt`-conditional; tombstones and local sets
  rebuild from durable rows at init.
- Verified baseline: `flutter analyze` 0 issues, 1215 tests green, macOS
  build clean (commit `c736185`).
