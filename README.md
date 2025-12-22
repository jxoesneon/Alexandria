# Alexandria 🏛️

> "To preserve human knowledge is to preserve humanity itself."

A decentralized, censorship-resistant digital library built with Flutter and IPFS. Alexandria empowers users to permanently archive content, resist censorship through anonymous routing, and participate in a reputation-based curation economy.

## 🌟 Features

- **Unstoppable Content**: Files are stored and distributed via the **IPFS** P2P network.
- **The Veil (Privacy)**: Optional **Tor** anonymous routing for metadata and content.
- **The Archive**: Automatic "Endangered Content" detection and pinning.
- **Encryption**: Client-side **AES-256-GCM** encryption (The Wrapper) for all uploads.
- **Honor System**: A rigorous reputation economy without tokens (`Reputation = Σ Work`).
- **Offline First**: Built on **Drift** (SQLite) for full offline functionality.
- **Cross-Platform**: Optimized for macOS, iOS, and Android.

## 🛠️ Tech Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **UI Toolkit** | Flutter | Native performance, multi-platform |
| **State** | Riverpod | Compile-safe dependency injection |
| **Database** | Drift (SQLite) | Type-safe, offline-capable, relational |
| **Network** | Dart IPFS | Embedded P2P node |
| **Privacy** | Tor (SOCKS5) | Anonymity layer (The Veil) |
| **Security** | Cryptography | Authenticated AES-GCM & Ed25519 |

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.10+)
- CocoaPods (for macOS/iOS)
- Rust (optional, for some crypto bindings)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/alexandria.git
   cd alexandria
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   - **macOS** (Recommended for development):
     ```bash
     flutter run -d macos
     ```
   - **Mobile**: Connect device and run `flutter run`.

## 📖 Documentation

- [**User Guide**](docs/USER_GUIDE.md): Comprehensive manual for Librarians.
- [**Contributing**](CONTRIBUTING.md): Code of Conduct and PR guidelines.
- [**The Vision**](docs/VISION.md): The philosophical mandate of the project.

## 📜 License

MIT License. See `LICENSE` for details.
