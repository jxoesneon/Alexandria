# Alexandria User Guide 📚

Welcome to Alexandria! This guide will help you navigate the decentralized library, preserve human knowledge, and participate in the curation economy.

---

## 🔑 Your Identity

Your identity in Alexandria is **cryptographic**. It is not stored on any central server.

### Creating an Identity
1. Launch the app.
2. Select **"Enter The Library"**.
3. Your **Private Key** will be generated on your device's Secure Enclave.
4. **IMPORTANT**: Go to **Settings > Security > Export Private Key**. Write this down securely. If you lose your device, this is the *only* way to recover your reputation and content ownership.

### Burner Mode
If you need to disappear quickly:
1. Go to **Settings > Security**.
2. Tap **Burner Mode**.
3. Confirm with biometrics.
4. This will **permanently wipe**:
   - Your Identity (Keys)
   - Your Local Library Database
   - All connection caches

---

## 🏛️ The Library (Preservation)

### Adding Content
1. Tap the **+ (Add)** button in the bottom navigation.
2. **Select File**: Choose a book, paper, image, or dataset.
3. **Smart Detect**: Alexandria will try to auto-fill metadata (Author, Year, etc.).
4. **Encryption (Optional)**: Toggle "Encrypt Content" if you only want people with the key to read it.
5. **Publish**: The file is hashed, signed, and broadcast to the IPFS network.

### Pinning & "Endangered" Content
Alexandria monitors the health of the network.
- **Healthy**: Content has > 5 peers hosting it.
- **At Risk**: Content has < 3 peers.
- **Endangered**: Content has 1 peer (YOU).

If you see an **Endangered** badge on an item, it means if you go offline, that knowledge might be lost. **Pin it** to help preserve it.

---

## ⚖️ The Honor System (Economy)

Alexandria uses a reputation system to verify truth without central authority.

- **Reputation (R)**: You earn R by doing work.
- **Pinning**: Hosting content for others (+1 R).
- **Curating**: Creating valuable Collections (+5 R).
- **Verifying**: Checking metadata accuracy (+2 R).

### The Ledger
Every action you take is signed and recorded in your local Ledger. You can export this proof to vouch for your trustworthiness to other peers.

---

## 🛡️ Privacy & Security

### The Veil (Tor)
To browse anonymously:
1. Go to **Settings > Security**.
2. Toggle **Tor Anonymous Routing**.
3. Wait for the "Connected" status.
4. All IPFS traffic is now routed through the Tor network.

### Offline Mode
Alexandria caches everything you view. You can use the app completely offline to read books or view saved content.
