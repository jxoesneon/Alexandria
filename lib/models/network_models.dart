import 'package:flutter/foundation.dart';

enum PeerStatus { connected, disconnected, pending }

enum TransportProtocol { ipfs, webrtc, tor }

extension TransportProtocolName on TransportProtocol {
  String get displayName {
    switch (this) {
      case TransportProtocol.ipfs:
        return 'IPFS';
      case TransportProtocol.webrtc:
        return 'WebRTC';
      case TransportProtocol.tor:
        return 'Tor';
    }
  }
}

@immutable
class NodeStatus {
  final bool isRunning;
  final int connectedPeers;
  final String nodeId;

  const NodeStatus({
    required this.isRunning,
    required this.connectedPeers,
    this.nodeId = '',
  });

  NodeStatus copyWith({
    bool? isRunning,
    int? connectedPeers,
    String? nodeId,
  }) {
    return NodeStatus(
      isRunning: isRunning ?? this.isRunning,
      connectedPeers: connectedPeers ?? this.connectedPeers,
      nodeId: nodeId ?? this.nodeId,
    );
  }

  @override
  String toString() =>
      'NodeStatus(isRunning: $isRunning, connectedPeers: $connectedPeers, nodeId: $nodeId)';
}

@immutable
class BandwidthStats {
  final int uploadBps;
  final int downloadBps;
  final DateTime timestamp;

  const BandwidthStats({
    required this.uploadBps,
    required this.downloadBps,
    required this.timestamp,
  });

  BandwidthStats copyWith({
    int? uploadBps,
    int? downloadBps,
    DateTime? timestamp,
  }) {
    return BandwidthStats(
      uploadBps: uploadBps ?? this.uploadBps,
      downloadBps: downloadBps ?? this.downloadBps,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

@immutable
class Peer {
  final String peerId;
  final String multiaddr;
  final int latencyMs;
  final PeerStatus status;

  const Peer({
    required this.peerId,
    required this.multiaddr,
    required this.latencyMs,
    required this.status,
  });

  Peer copyWith({
    String? peerId,
    String? multiaddr,
    int? latencyMs,
    PeerStatus? status,
  }) {
    return Peer(
      peerId: peerId ?? this.peerId,
      multiaddr: multiaddr ?? this.multiaddr,
      latencyMs: latencyMs ?? this.latencyMs,
      status: status ?? this.status,
    );
  }
}

@immutable
class TransportConfig {
  final TransportProtocol protocol;
  final bool enabled;
  final int port;
  final String relay;

  const TransportConfig({
    required this.protocol,
    required this.enabled,
    required this.port,
    this.relay = '',
  });

  TransportConfig copyWith({
    TransportProtocol? protocol,
    bool? enabled,
    int? port,
    String? relay,
  }) {
    return TransportConfig(
      protocol: protocol ?? this.protocol,
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      relay: relay ?? this.relay,
    );
  }
}

@immutable
class Transfer {
  final String name;
  final int bytesTransferred;
  final int totalBytes;

  const Transfer({
    required this.name,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;

  Transfer copyWith({
    String? name,
    int? bytesTransferred,
    int? totalBytes,
  }) {
    return Transfer(
      name: name ?? this.name,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

class Conflict {
  final String id;
  final String documentName;
  final String localVersion;
  final String remoteVersion;
  final DateTime timestamp;

  const Conflict({
    required this.id,
    required this.documentName,
    required this.localVersion,
    required this.remoteVersion,
    required this.timestamp,
  });

  Conflict copyWith({
    String? id,
    String? documentName,
    String? localVersion,
    String? remoteVersion,
    DateTime? timestamp,
  }) {
    return Conflict(
      id: id ?? this.id,
      documentName: documentName ?? this.documentName,
      localVersion: localVersion ?? this.localVersion,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

@immutable
class Resolution {
  final String id;
  final bool success;

  const Resolution({
    required this.id,
    this.success = true,
  });

  Resolution copyWith({
    String? id,
    bool? success,
  }) {
    return Resolution(
      id: id ?? this.id,
      success: success ?? this.success,
    );
  }
}

@immutable
class SyncProgress {
  final double overallProgress;
  final List<Transfer> activeTransfers;
  final List<Conflict> pendingConflicts;
  final bool inProgress;

  const SyncProgress({
    required this.overallProgress,
    required this.activeTransfers,
    required this.pendingConflicts,
    this.inProgress = false,
  });

  SyncProgress copyWith({
    double? overallProgress,
    List<Transfer>? activeTransfers,
    List<Conflict>? pendingConflicts,
    bool? inProgress,
  }) {
    return SyncProgress(
      overallProgress: overallProgress ?? this.overallProgress,
      activeTransfers: activeTransfers ?? this.activeTransfers,
      pendingConflicts: pendingConflicts ?? this.pendingConflicts,
      inProgress: inProgress ?? this.inProgress,
    );
  }
}
