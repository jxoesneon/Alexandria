# ALX-003: Autonomous Parity Healing, Cauchy Reed-Solomon Erasure Coding, and Dynamic Density

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-003 |
| **Title** | Autonomous Parity Healing, Cauchy Reed-Solomon Erasure Coding, and Dynamic Density Specification |
| **Author** | Alexandria Core Team |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-08-23 |

---

## 1. Abstract
This specification defines Alexandria's resilient preservation protocol, specifying peer threshold classifications, Galois Field $\text{GF}(2^8)$ Cauchy Reed-Solomon erasure coding, and dynamic replication density scaling to improve content availability under peer churn.

## 2. Health Threshold Taxonomy

Every tracked CID is evaluated periodically (default cadence: 15 minutes) against network DHT provider density:

```
                      Peer Count (N)
              ┌─────────────────────────────┐
              │ N >= 3: HEALTHY             │  (Redundancy stable; no repair required)
              ├─────────────────────────────┤
              │ 1 <= N < 3: ENDANGERED      │  (Elevated risk; auto-pin & repair triggered)
              ├─────────────────────────────┤
              │ N == 0: LOST / UNREACHABLE  │  (Status flagged; search broadcast)
              └─────────────────────────────┘
```

---

## 3. Systematic Cauchy Reed-Solomon Erasure Coding

To improve resilience beyond full-file replication, payloads are partitioned into systematic data and parity shards over Galois Field $\text{GF}(2^8)$ (primitive polynomial $0\text{x}11\text{D}$):

1. **Source Shard Division**:
   - The payload is partitioned into $k$ data shards of size $T$.
2. **Parity Shard Generation**:
   - The encoder computes $m = \lceil k \times 0.5 \rceil$ parity shards using a Cauchy generator matrix.
3. **Reconstruction Threshold**:
   - Any $k$ distinct shards (data or parity) reconstruct 100% of the original payload via Gaussian elimination matrix inversion.

---

## 4. Dynamic Replication Density Algorithm

Nodes dynamically adapt seeding and parity broadcast behavior based on observed provider density:

$$\text{ReplicationFactor}(N) = \max\left(1, \left\lceil \frac{\theta_{\text{healthy}}}{\max(1, N)} \right\rceil\right)$$

Where $\theta_{\text{healthy}} = 3$.

- If $N = 1$ (Endangered): $\text{ReplicationFactor} = 3$. The node pins the content, generates parity shards, and advertises DHT provider records.
- If $N \ge 3$ (Healthy): $\text{ReplicationFactor} = 1$. The node retains standard pinning without emergency parity generation.

---

## 5. Storage Quota Allocation & Healing Daemon

- **Dedicated Healing Quota**: Defaults to 500 MB (user-configurable).
- **Concurrency Limit**: Maximum 2 concurrent repair/download streams to preserve resources.
- **Priority Queue**: Endangered items are sorted by $(\text{TrustScore} / N)$ descending.
