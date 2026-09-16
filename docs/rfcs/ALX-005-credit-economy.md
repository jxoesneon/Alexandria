# ALX-005: Tokenless Resource-Sharing Economics, Proof of Common Heritage, and Ethical Micro-Sponsorships

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-005 |
| **Title** | Tokenless Resource-Sharing Economics, Proof of Common Heritage, and Ethical Micro-Sponsorships Specification |
| **Author** | Alexandria Core Team |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-09-13 |
| **Depends On** | ALX-001, ALX-002, ALX-003, ALX-004 |

---

## 1. Abstract
This specification defines the economic engine of Alexandria. It formalizes:
1. **Proof of Common Heritage (PoCH)**: A mandatory baseline resource commitment (storage, trickle seeding, validation) enforcing reciprocal altruism across swarm participants.
2. **Dual-Layer Honor & Credit Accounting**: Distinct separation between non-transferable, soulbound **Reputation Points** ($\mathcal{R}$, ALX-004) and spendable internal **Archival Credits** ($\mathcal{C}$).
3. **Tri-Pillar Resource Minting**: Dynamic, rarity-weighted rewards for:
   - **Storage**: Rarity-weighted Proof of Retrievability (PoR Lite) challenges.
   - **Compute**: Cauchy Reed-Solomon $\text{GF}(2^8)$ parity encoding and text extraction.
   - **Information Verification**: Crossref/OpenAlex DOI resolution and consensus auditing.
4. **Privacy-Preserving Micro-Sponsorships**: A zero-tracker, client-matched sponsorship slot rental protocol with an **85% client kickback**, **10% Archival Commons seeder pool**, and **5% Protocol Treasury fee**.

---

## 2. Statutory Safe Harbor & Economic Invariants

Alexandria operates strictly as a permanent, non-profit digital preservation commons under international library exceptions (US Copyright Act §108, Marrakesh Treaty, and UNESCO Memory of the World).

### 2.1 The Tokenless Mandate
- Archival Credits ($\mathcal{C}$) are **internal utility units**, not speculative financial securities or tradeable cryptocurrencies.
- Credits cannot be traded between arbitrary external parties or cashed out through centralized protocol custodial balances.
- All economic transactions settle via authenticated local hash-chains and peer attestations.

---

## 3. Proof of Common Heritage (PoCH)

To eradicate the free-rider problem while preserving universal open access, every active node maintains a dynamic Proof of Common Heritage score evaluated over a rolling 24-hour epoch.

### 3.1 PoCH Mathematical Formulation
$$\text{PoCH}_i(t) = \min\left(1.0, \, \alpha \cdot \frac{S_i(t)}{S_{\text{min}}} + \beta \cdot \frac{B_i(t)}{B_{\text{min}}} + \gamma \cdot \frac{V_i(t)}{V_{\text{min}}}\right)$$

Where:
- $S_i$: Allocated and pinned archival block storage (Baseline $S_{\text{min}} = 1000\text{ MB} = 1\text{ GB}$).
- $B_i$: 24-hour outbound and inbound seeding volume (Baseline $B_{\text{min}} = 500\text{ MB}$).
- $V_i$: Proof of Retrievability challenges answered or metadata audits verified (Baseline $V_{\text{min}} = 12\text{ challenges}$).
- Normalized Weights: $\alpha = 0.4$, $\beta = 0.4$, $\gamma = 0.2$ ($\alpha + \beta + \gamma = 1.0$).

### 3.2 Adaptive Bandwidth Scheduling
Nodes with low PoCH scores are never disconnected, but their Bitswap ingress priority degrades gracefully:

$$\mu_{\text{bw}}(\text{PoCH}_i) = \begin{cases} 
\mu_{\text{floor}} \cdot \left(\frac{\text{PoCH}_i}{\theta_{\text{threshold}}}\right)^2 & \text{if } \text{PoCH}_i < \theta_{\text{threshold}} \\
1.0 + \psi \cdot \log_{10}(1.0 + \text{PoCH}_i - \theta_{\text{threshold}}) & \text{if } \text{PoCH}_i \ge \theta_{\text{threshold}}
\end{cases}$$

- $\theta_{\text{threshold}} = 0.5$
- $\mu_{\text{floor}} = 0.10$ (10% base trickle bandwidth)
- $\psi = 0.50$ (bonus unchoking factor for high contributors)

---

## 4. Tri-Pillar Credit Accrual

Nodes earn spendable Archival Credits ($\mathcal{C}$) through three verifiable physical actions:

### 4.1 Pillar 1: Storage (Proof of Retrievability)
Storage rewards scale with document rarity to incentivize pinning endangered knowledge:

$$\Delta \mathcal{C}_{\text{storage}} = \text{SizeBytes} \times \omega_{\text{rarity}}(N) \times \left(\frac{\text{PoR\_Passed}}{\max(1, \text{PoR\_Total})}\right) \times \kappa_s$$

Where $\omega_{\text{rarity}}(N)$ is determined by DHT provider density $N$:
- $N = 1$ (Critically Endangered): $\omega_{\text{rarity}} = 5.0$
- $N = 2$ (Vulnerable): $\omega_{\text{rarity}} = 3.0$
- $3 \le N < 5$ (Near-Safe): $\omega_{\text{rarity}} = 1.5$
- $N \ge 5$ (Healthy): $\omega_{\text{rarity}} = 1.0$

Base credit factor: $\kappa_s = 1.0 \times 10^{-6} \text{ Credits/MB-day}$.

### 4.2 Pillar 2: Compute (Cauchy Parity Encoding & Extraction)
$$\Delta \mathcal{C}_{\text{compute}} = (2.0 \cdot M_{\text{CRS}} + 0.5 \cdot M_{\text{CDC}} + 5.0 \cdot P_{\text{OCR}}) \times \Psi_{\text{audit}}$$

- $M_{\text{CRS}}$: Megabytes of Cauchy $\text{GF}(2^8)$ parity shards encoded (ALX-003).
- $M_{\text{CDC}}$: Megabytes of FastCDC chunking and BLAKE3 hashing.
- $P_{\text{OCR}}$: High-confidence document pages extracted.
- $\Psi_{\text{audit}}$: Spot-check audit verification factor (1 on success, -10 on fraud).

### 4.3 Pillar 3: Information Verification
- Resolving and cross-verifying an orphaned CID to Crossref/OpenAlex: $+5.0\ \mathcal{C}$.
- Attesting to duplicate text layers between preprints and published journals: $+3.0\ \mathcal{C}$.
- Participating in consensus governance votes: $+1.0\ \mathcal{C}$.
- Identifying and quarantining corrupted/tampered multihashes: $+10.0\ \mathcal{C}$.

---

## 5. Privacy-Preserving Opt-In Micro-Sponsorships

### 5.1 Principles
1. **Disabled by Default**: Clients only display sponsorships if explicitly enabled in Settings.
2. **Zero Telemetry**: All catalog matching is executed in-memory on the local device. No browsing history, search terms, or IP addresses ever leave the client.
3. **Verified Attention**: Impressions require continuous on-screen dwell time $\ge 5.0\text{ seconds}$ with active viewport visibility $\ge 80\%$.

### 5.2 The 85 / 10 / 5 Economic Settlement
For every verified sponsorship display with nominal value $V_{\text{gross}}$:
- **85% Viewer Kickback**: Credited directly to the user's local wallet balance.
- **10% Archival Commons Pool**: Distributed to nodes pinning critically endangered ($N < 3$) historical items.
- **5% Protocol Treasury Micro-Fee**: Reserved in cold multi-signature escrow strictly to finance bootstrap DHT seeders, Tor relay nodes, and preservation infrastructure.

```
+-------------------------------------------------------------------+
|               VERIFIED SPONSORSHIP TRANSACTION                    |
+-------------------------------------------------------------------+
|  Total Value: V_gross                                             |
|  ├── Viewer Kickback:         0.85 × V_gross  (Instant Credit)    |
|  ├── Archival Commons Pool:   0.10 × V_gross  (Endangered Seeders)|
|  └── Protocol Treasury Fee:   0.05 × V_gross  (Bootstrap Infra)   |
+-------------------------------------------------------------------+
```

---

## 6. Sybil & Anti-Gaming Invariants
1. **Rate Limiting**: Daily credit accrual caps per action type prevent bot farming.
2. **Timed PoR Challenges**: Responses exceeding $1500\text{ ms}$ are rejected to prevent generation-on-demand attacks.
3. **Merkle-Linked Audit Ledger**: All credit changes are recorded in an append-only, signed Merkle hash chain with cryptographic cross-signing.
