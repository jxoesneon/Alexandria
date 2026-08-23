# Alexandria

Alexandria is a local-first, decentralized digital library and document repository built with Flutter and IPFS (`dart_ipfs`).

## Overview
The application provides content-addressed storage, optional Tor proxy routing, client-side envelope encryption (AES-256-GCM), and automated background integrity verification.

## Architecture & Subsystems
- **Storage & Transport**: IPFS node with Libp2p, WebRTC-Direct, and Bitswap protocols.
- **Privacy & Routing**: Optional Tor SOCKS5 proxy configuration.
- **Security**: Local master key management and AES-256-GCM data encryption.
- **Durability**: Cauchy Reed-Solomon erasure coding and periodic Merkle integrity checks.
- **Curation**: Work-based reputation scoring and peer-to-peer CRDT collection synchronization.
- **Media Engine**: Format detection and metadata extraction across documents, datasets, audio, 3D models, and web archives.

## Specifications
Formal protocol specifications are documented in `docs/rfcs/`:
- `ALX-001`: Content Manifests & Envelope Encryption
- `ALX-002`: Collection CRDT Sync Protocol
- `ALX-003`: Erasure Coding & Dynamic Parity Healing
- `ALX-004`: Reputation Metrics & Proof of Retrievability
