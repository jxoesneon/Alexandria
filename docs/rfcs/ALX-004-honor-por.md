# ALX-004: Work-Based Reputation, Proof of Retrievability Challenges, and QoS

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-004 |
| **Title** | Work-Based Reputation, Proof of Retrievability Challenges, and QoS Specification |
| **Author** | Alexandria Core Team |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-08-23 |

---

## 1. Abstract
This specification defines the reputation and verification architecture of Alexandria. It formalizes a work-based reputation metric ($\text{Reputation} = \Sigma \text{Work}$), interactive Proof of Retrievability (PoR Lite) challenge-response checks, and reputation-weighted Quality of Service (QoS) bandwidth scheduling.

## 2. Reputation Metric

Alexandria operates without financial tokens. Reputation is earned through verifiable archival storage, seeding, and peer validation.

### 2.1 Logarithmic Voting Weight Formula
To mitigate Sybil attacks, validator voting power scales logarithmically:

$$W(R) = \begin{cases} 
\log_{10}(R + 10) & \text{if } R \ge 0 \\
0 & \text{if } R < 0 
\end{cases}$$

Where $R$ is the validator's cumulative reputation score.

### 2.2 Content Trust Score
The Trust Score $T$ for a given target CID is the rounded sum of weighted validation votes:

$$T(\text{CID}) = \text{round}\left( \sum_{i=1}^{V} S_i \cdot W(R_i) \right)$$

Where $S_i \in \{-1, +1\}$.

---

## 3. Proof of Retrievability (PoR Lite) Protocol

Nodes periodically challenge peers claiming to store content blocks:

```
   Challenger (Node A)                                    Prover (Node B)
        │                                                       │
        │─── 1. PoR Challenge (CID, BlockIndex, Nonce) ────────>│
        │                                                       │
        │                                             Compute Digest:
        │                                             Tag = HMAC-SHA256(Block[i], Nonce)
        │                                                       │
        │<── 2. PoR Response (Tag, ProofSignature) ─────────────│
        │                                                       │
   Verify Tag == Expected;
   Update Ledger: +1 Rep (Pass) / -5 Rep (Fail)
```

1. **Challenge Generation**: Node A selects a random block index $i$ of the target CID and a 32-byte nonce.
2. **Proof Response**: Node B computes $\text{Tag} = \text{HMAC-SHA256}(\text{BlockData}[i], \text{Nonce})$.
3. **Verification**: If Node A holds or verifies the block, it checks the tag. A valid response earns Node B reputation; a failure reduces Node B's standing on Node A's local ledger.

---

## 4. Reputation-Weighted QoS Bandwidth Allocation

During swarm congestion, Alexandria nodes allocate egress bandwidth using Weighted Fair Queueing (WFQ):

$$\text{BandwidthShare}(P) = \frac{W(R_P)}{\sum_{j \in \text{Peers}} W(R_j)} \times \text{TotalCapacity}$$
