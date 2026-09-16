# Alexandria Backend Mapping

This document maps the 16 professional UI screens across the four core pillars of Alexandria (Library, Workspace, Network, Security) to their respective backend Dart services, methods, streams, and Riverpod providers.

## 1. Library Pillar

### 1.1 Library Dashboard
Provides an overview of the user's collections, recent reads, and library statistics.
*   **Target Services:** `library_service.dart`, `metadata_service.dart`
*   **Providers:** `libraryDashboardProvider`, `recentItemsProvider`
*   **Methods/Streams:**
    *   `LibraryService.getLibraryStats()`: `Future<LibraryStats>`
    *   `LibraryService.watchRecentItems()`: `Stream<List<LibraryItem>>`
    *   `MetadataService.fetchItemMetadata(String cid)`: `Future<ItemMetadata>`

### 1.2 Document Viewer/Reader
The core reading experience for EPUBs, PDFs, and Markdown files.
*   **Target Services:** `reader_service.dart`, `annotation_service.dart`
*   **Providers:** `currentDocumentProvider`, `annotationsProvider(docId)`
*   **Methods/Streams:**
    *   `ReaderService.openDocument(String cid)`: `Future<DocumentStream>`
    *   `ReaderService.updateProgress(String cid, double progress)`: `Future<void>`
    *   `AnnotationService.watchAnnotations(String cid)`: `Stream<List<Annotation>>`
    *   `AnnotationService.addAnnotation(Annotation annotation)`: `Future<void>`

### 1.3 Ingestion & Import Screen
Handles the import of new documents, metadata extraction, and initial IPFS pinning.
*   **Target Services:** `ingestion_service.dart`, `preservation_service.dart`
*   **Providers:** `ingestionQueueProvider`
*   **Methods/Streams:**
    *   `IngestionService.addToQueue(List<File> files)`: `Future<void>`
    *   `IngestionService.watchIngestionStatus()`: `Stream<IngestionState>`
    *   `PreservationService.pinToLocalNode(String cid)`: `Future<PinResult>`

### 1.4 Search & Discovery
Full-text search, tag filtering, and content discovery.
*   **Target Services:** `search_service.dart`
*   **Providers:** `searchResultsProvider(query)`
*   **Methods/Streams:**
    *   `SearchService.performFullTextSearch(String query)`: `Future<List<SearchResult>>`
    *   `SearchService.getAvailableTags()`: `Future<List<String>>`

## 2. Workspace Pillar

### 2.1 Workspace Dashboard
Overview of active projects, AI contexts, and recent notes.
*   **Target Services:** `workspace_service.dart`
*   **Providers:** `activeWorkspacesProvider`
*   **Methods/Streams:**
    *   `WorkspaceService.watchActiveWorkspaces()`: `Stream<List<Workspace>>`
    *   `WorkspaceService.createWorkspace(String name)`: `Future<Workspace>`

### 2.2 Alexandria Agent Interface
The conversational interface for interacting with the Alexandria AI.
*   **Target Services:** `alexandria_ai_service.dart`
*   **Providers:** `alexandriaChatProvider(sessionId)`
*   **Methods/Streams:**
    *   `AlexandriaAiService.sendMessage(String sessionId, String message)`: `Future<void>`
    *   `AlexandriaAiService.watchChatStream(String sessionId)`: `Stream<ChatMessage>`
    *   `AlexandriaAiService.invokeTool(ToolInvocation invocation)`: `Future<ToolResult>`

### 2.3 Document & Note Editor
Markdown-based editor for local notes and project documentation.
*   **Target Services:** `editor_service.dart`, `version_control_service.dart`
*   **Providers:** `editorStateProvider(noteId)`
*   **Methods/Streams:**
    *   `EditorService.saveNote(Note note)`: `Future<void>`
    *   `EditorService.watchNoteContent(String noteId)`: `Stream<String>`
    *   `VersionControlService.commitChanges(String noteId)`: `Future<String>`

### 2.4 Knowledge Graph View
Visual representation of connections between documents, notes, and tags.
*   **Target Services:** `knowledge_graph_service.dart`
*   **Providers:** `graphNodesProvider`, `graphEdgesProvider`
*   **Methods/Streams:**
    *   `KnowledgeGraphService.getGraphData()`: `Future<GraphData>`
    *   `KnowledgeGraphService.findShortestPath(String nodeIdA, String nodeIdB)`: `Future<GraphPath>`

## 3. Network Pillar

### 3.1 Node Operations Dashboard
Status of the local IPFS/P2P node, bandwidth, and connection health.
*   **Target Services:** `ipfs_node_service.dart`, `telemetry_service.dart`
*   **Providers:** `nodeStatusProvider`, `networkTelemetryProvider`
*   **Methods/Streams:**
    *   `IpfsNodeService.startNode()`: `Future<void>`
    *   `IpfsNodeService.watchNodeStatus()`: `Stream<NodeStatus>`
    *   `TelemetryService.watchBandwidthUsage()`: `Stream<BandwidthStats>`

### 3.2 Peer Discovery & Mesh
Management of connected peers and swarm connectivity.
*   **Target Services:** `peer_discovery_service.dart`, `mesh_transport_service.dart`
*   **Providers:** `connectedPeersProvider`
*   **Methods/Streams:**
    *   `PeerDiscoveryService.watchConnectedPeers()`: `Stream<List<Peer>>`
    *   `MeshTransportService.connectToPeer(String multiaddr)`: `Future<bool>`
    *   `MeshTransportService.disconnectPeer(String peerId)`: `Future<void>`

### 3.3 Replication & Pinning
Tracking data distribution and redundancy across the network.
*   **Target Services:** `replication_service.dart`, `preservation_service.dart`
*   **Providers:** `replicationStatusProvider(cid)`
*   **Methods/Streams:**
    *   `ReplicationService.getReplicationFactor(String cid)`: `Future<int>`
    *   `PreservationService.requestRemotePin(String cid, String peerId)`: `Future<void>`
    *   `ReplicationService.watchPinningQueue()`: `Stream<List<PinTask>>`

### 3.4 Sync & Conflict Resolution
Managing state synchronization between user devices.
*   **Target Services:** `sync_service.dart`, `crdt_service.dart`
*   **Providers:** `syncStatusProvider`
*   **Methods/Streams:**
    *   `SyncService.triggerManualSync()`: `Future<void>`
    *   `CrdtService.resolveMergeConflict(Conflict conflict)`: `Future<Resolution>`
    *   `SyncService.watchSyncProgress()`: `Stream<SyncProgress>`

## 4. Security Pillar

### 4.1 Security Dashboard
Overview of wallet status, encryption state, and recent alerts.
*   **Target Services:** `security_service.dart`
*   **Providers:** `securityOverviewProvider`
*   **Methods/Streams:**
    *   `SecurityService.getSecurityScore()`: `Future<int>`
    *   `SecurityService.watchSecurityAlerts()`: `Stream<List<SecurityAlert>>`

### 4.2 Key Management & Wallet
Management of cryptographic identities, DIDs, and keys.
*   **Target Services:** `key_management_service.dart`, `did_service.dart`
*   **Providers:** `activeIdentitiesProvider`
*   **Methods/Streams:**
    *   `KeyManagementService.generateNewKeypair(KeyType type)`: `Future<Keypair>`
    *   `DidService.resolveDid(String did)`: `Future<DidDocument>`
    *   `KeyManagementService.exportPrivateKey(String keyId, String password)`: `Future<String>`

### 4.3 Access Control & Permissions
Managing who has access to specific encrypted documents or workspaces.
*   **Target Services:** `access_control_service.dart`, `encryption_service.dart`
*   **Providers:** `documentAclProvider(cid)`
*   **Methods/Streams:**
    *   `AccessControlService.grantAccess(String cid, String peerDid)`: `Future<void>`
    *   `AccessControlService.revokeAccess(String cid, String peerDid)`: `Future<void>`
    *   `EncryptionService.encryptForPeer(Uint8List data, String peerPubKey)`: `Future<Uint8List>`

### 4.4 Audit Logs & Proof of Retrievability
Verifying data integrity and reviewing system audits.
*   **Target Services:** `audit_service.dart`, `proof_of_retrievability_service.dart`
*   **Providers:** `auditLogsProvider`, `porChallengesProvider`
*   **Methods/Streams:**
    *   `AuditService.getRecentLogs(int limit)`: `Future<List<AuditLog>>`
    *   `ProofOfRetrievabilityService.issueChallenge(String cid, String peerId)`: `Future<PorChallenge>`
    *   `ProofOfRetrievabilityService.verifyProof(PorProof proof)`: `Future<bool>`
