# ALX-001: Content Manifest, Addressing, and Two-Tier Envelope Encryption

| Metadata | Value |
| :--- | :--- |
| **RFC** | ALX-001 |
| **Title** | Content Manifest, Addressing, and Two-Tier Envelope Encryption Specification |
| **Author** | Alexandria Core Team |
| **Status** | Standard / Active |
| **Version** | 1.0.0 |
| **Date** | 2026-08-23 |

---

## 1. Abstract
This specification defines the canonical data schema for content manifests, content-addressable identifiers (CIDv1), and the two-tier envelope encryption pipeline used within the Alexandria decentralized preservation network.

## 2. Content Addressing & Multihash Protocol

All content objects within Alexandria are identified by a deterministic CIDv1 structure complying with Multiformats standards.

### 2.1 Multicodec & Multibase Binary Layout
```
+---------------+----------------+----------------------+-------------------+-----------------------+
| Version (1B)  | Codec (1B)     | Hash Function (1B)   | Digest Length (1B)| Digest (32B)          |
| 0x01          | 0x55 (raw-bin) | 0x12 (SHA2-256)      | 0x20 (32 bytes)   | SHA2-256(Data)        |
+---------------+----------------+----------------------+-------------------+-----------------------+
```

- **Default Multibase Representation**: Lowercase Base32 (prefix `b`).
- **Secondary Multibase Representation**: Bitcoin Base58 (prefix `z`).
- **Legacy Backward Compatibility**: Valid CIDv0 Base58 multihashes (prefix `Qm`, length 46) are parsed and indexed.

---

## 3. Manifest Data Schema

A Content Manifest represents a conceptual intellectual work, holding immutable cryptographic identifiers and mutable metadata.

### 3.1 JSON / Relational Representation
```json
{
  "$schema": "https://alexandria.pub/schemas/v1/manifest.json",
  "uuid": "urn:uuid:f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "title": "Tractatus Logico-Philosophicus",
  "author": "Ludwig Wittgenstein",
  "description": "Historical treatise on logic and language.",
  "category": "philosophy",
  "isEncrypted": true,
  "encryptionKey": "<Base64-Wrapped-DEK>",
  "metadata": {
    "publicationYear": 1921,
    "language": "de",
    "license": "Public Domain",
    "tags": ["logic", "philosophy", "epistemology"]
  },
  "versions": [
    {
      "cid": "bafkreiaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "format": "pdf",
      "language": "de",
      "sizeBytes": 4194304,
      "peerCount": 5,
      "isPinned": true,
      "lastHealthCheck": "2026-08-23T12:00:00Z"
    }
  ],
  "lastUpdated": "2026-08-23T12:00:00Z"
}
```

---

## 4. Two-Tier Envelope Encryption

To ensure client-side confidentiality and zero-knowledge preservation:

```
                      ┌──────────────────────────────────────────────┐
                      │              Plaintext Payload               │
                      └──────────────────────┬───────────────────────┘
                                             │
                       AES-256-GCM Encrypt(Payload, DEK)
                                             │
                      ┌──────────────────────▼───────────────────────┐
                      │         Ciphertext Data (Pinned)             │
                      └──────────────────────────────────────────────┘

                      ┌──────────────────────────────────────────────┐
                      │        Data Encryption Key (DEK)             │
                      └──────────────────────┬───────────────────────┘
                                             │
                       AES-256-GCM Encrypt(DEK, MasterKey)
                                             │
                      ┌──────────────────────▼───────────────────────┐
                      │   Wrapped DEK (Stored in Manifest/Enclave)   │
                      └──────────────────────────────────────────────┘
```

1. **Data Encryption Key (DEK)**:
   - Generated per-manifest using cryptographically secure random bytes (256-bit AES).
   - The plaintext file is encrypted with the DEK using authenticated **AES-256-GCM** (12-byte nonce, 16-byte authentication tag).
2. **Key Wrapping**:
   - The DEK is encrypted using the user's root **Master Key** (`master_key_v1`) stored in the hardware security enclave (`flutter_secure_storage`).
   - The wrapped DEK is encoded in Base64 and stored in the manifest.

---

## 5. Tamper-Evident Audit Trail

Every state-mutating operation appends a signed entry to `audit_trail.log`:

```
<ISO8601_TIMESTAMP>|<ACTION>|<DETAILS>|<HMAC_SHA256_SIGNATURE>
```
- **HMAC Secret**: User's `master_key_v1`.
- **Integrity Guarantee**: Modifications to the log produce an invalid signature verification.
