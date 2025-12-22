# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.0-alpha] - 2025-12-16

### 🚀 New Features

*   **P2P Sync Protocol**: Real-time content synchronization between peers using IPFS PubSub (`/alexandria/sync/v1/`).
*   **Tor Integration**: Optional anonymous routing via SOCKS5 proxy (Toggle in Settings).
*   **Settings Surface**:
    *   **Appearance**: System/Light/Dark theme toggle and Reduced Motion preference.
    *   **Storage**: One-tap Cache Clearing and IPFS Repo Garbage Collection.
    *   **Security**: Biometric-gated "Export Private Key" and "Burner Mode" (Emergency Wipe).
*   **Cryptographic Identity**: Ed25519 key generation with platform-secure storage (Secure Enclave/Keystore).
*   **Content Preservation**: Drag-and-drop upload flow with automated metadata extraction and encryption (AES-256-GCM).
*   **Governance**: "The Parliament" proposal and voting system with reputation weighting.
*   **Plugin System**: "The Garden" plugin architecture for extensions and themes.

### 🛠 Improvements

*   **Performance**: Migrated database from Isar to Drift (SQLite) for better stability on Android/iOS.
*   **Networking**: Added `IpfsService` gateway rotation with automatic fallback and CID verification.
*   **Security**: Removed insecure `encrypt` package in favor of `cryptography` (AES-GCM).
*   **UI/UX**: Complete redesign with "Void" and "Nebula" themes, Glassmorphism, and hero animations.

### 🐛 Bug Fixes

*   Fixed race condition in `SettingsLogic` during state updates.
*   Fixed Android build failures related to Kotlin Gradle plugin.
*   Fixed `DefaultCacheManager` initialization crashes in tests.
*   Resolved version conflicts between `dart_ipfs` and crypto libraries.
