# ALX-002: P2P Collection CRDT Merging and PubSub Protocol

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-002 |
| **Title** | P2P Collection CRDT Merging and PubSub Protocol Specification |
| **Author** | Alexandria Core Team |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-08-23 |

---

## 1. Abstract
This specification describes the real-time, peer-to-peer collection synchronization protocol over IPFS PubSub, utilizing Conflict-Free Replicated Data Types (CRDTs) to ensure convergence across offline, intermittently connected, and concurrent peers.

## 2. Topic Architecture & Wire Protocol

### 2.1 Topic Naming Convention
All synchronization streams must publish and subscribe to deterministic IPFS PubSub topics:
```
/alexandria/sync/v1/{collectionId}
```

### 2.2 Sync Message Wire Envelope
```json
{
  "type": "push",
  "collectionId": "philosophy_classics",
  "senderId": "z6MkmLqgK9v7a4jP5X2h9m8w1y4z7a1b",
  "timestamp": 1787493600000,
  "payload": {
    "op": "add_entry",
    "entryCid": "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku",
    "title": "Meditations",
    "author": "Marcus Aurelius",
    "updatedAt": 1787493600000
  },
  "signature": "<Ed25519_Signature_of_Envelope>"
}
```

### 2.3 Message Types
| Type | Description |
| :--- | :--- |
| `push` | Broadcasts local mutation or newly added items to peers. |
| `pull` | Requests the current state snapshot from active swarm members. |
| `ack` | Acknowledges receipt of remote changes with state sequence timestamp. |
| `state`| Full state dump provided to newly joined or recovering peers. |

---

## 3. CRDT Convergence Semantics

Alexandria collections implement a **Last-Write-Wins Element-Set (LWW-Element-Set)** CRDT:

1. **Add-Set ($A$) & Remove-Set ($R$)**:
   - Each element $e$ has an associated timestamp $t$ and author public key $k$.
2. **Membership Rule**:
   - An item $e$ is in the collection iff:
     $$e \in A \land (e \notin R \lor t_{\text{add}}(e) > t_{\text{remove}}(e))$$
3. **Deterministic Tie-Breaking**:
   - In the event of an exact timestamp collision ($t_{\text{add}} = t_{\text{remove}}$ or $t_1 = t_2$), the entry with the lexicographically higher `senderId` wins.

---

## 4. Offline Queue & Resiliency Mechanics

1. **Queue Bounds**: The offline operation queue enforces a strict maximum bound of 1,000 pending operations.
2. **Compaction**: When the queue overflows, oldest acknowledged operations are pruned (FIFO).
3. **Exponential Backoff**: Unsent operations undergo exponential retry delays ($30\text{s} \times 2^{\text{retries}}$) up to a hard cap of 5 retries before dead-letter quarantine.
