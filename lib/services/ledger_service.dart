import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import '../services/identity_service.dart';

/// Provider for the LedgerService
final ledgerServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  return LedgerService(identityService);
});

/// Action types that can be recorded in the ledger
enum LedgerActionType {
  pinContent,
  validateHash,
  curateCollection,
  proposeMetadataFix,
  mergeAccepted,
  crossSignLedger,
  reportBadContent,
  createContent,
  endorseContent,
}

/// Weights for reputation accrual (Spec §12.3)
class ReputationWeights {
  static const double pinContent = 1.0;
  static const double validateHash = 2.0;
  static const double curateCollection = 1.5;
  static const double proposeMetadataFix = 0.5;
  static const double mergeAccepted = 3.0;
  static const double crossSignLedger = 1.0;
  static const double reportBadContent = 0.5;
  static const double createContent = 2.0;
  static const double endorseContent = 1.0;

  /// Multipliers applied when actions are confirmed/accepted
  static const double acceptedMultiplier = 2.0;
  static const double confirmedMultiplier = 5.0;

  /// Daily limits for reputation accrual
  static const Map<LedgerActionType, int> dailyLimits = {
    LedgerActionType.pinContent: 100,
    LedgerActionType.validateHash: 50,
    LedgerActionType.curateCollection: 20,
    LedgerActionType.proposeMetadataFix: 30,
    LedgerActionType.mergeAccepted: 10,
    LedgerActionType.crossSignLedger: 5,
    LedgerActionType.reportBadContent: 5,
    LedgerActionType.createContent: 50,
    LedgerActionType.endorseContent: 20,
  };

  /// Get weight for an action type
  static double getWeight(LedgerActionType action) {
    switch (action) {
      case LedgerActionType.pinContent:
        return pinContent;
      case LedgerActionType.validateHash:
        return validateHash;
      case LedgerActionType.curateCollection:
        return curateCollection;
      case LedgerActionType.proposeMetadataFix:
        return proposeMetadataFix;
      case LedgerActionType.mergeAccepted:
        return mergeAccepted;
      case LedgerActionType.crossSignLedger:
        return crossSignLedger;
      case LedgerActionType.reportBadContent:
        return reportBadContent;
      case LedgerActionType.createContent:
        return createContent;
      case LedgerActionType.endorseContent:
        return endorseContent;
    }
  }
}

/// Cross-signature from another Archivist
class CrossSignature {
  final Uint8List signerPublicKey;
  final Uint8List signature;
  final DateTime timestamp;

  CrossSignature({
    required this.signerPublicKey,
    required this.signature,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'signerPublicKey': base64Encode(signerPublicKey),
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
      };

  factory CrossSignature.fromJson(Map<String, dynamic> json) {
    return CrossSignature(
      signerPublicKey: base64Decode(json['signerPublicKey'] as String),
      signature: base64Decode(json['signature'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// A single entry in the personal honor blockchain
class LedgerEntry {
  final int index;
  final DateTime timestamp;
  final LedgerActionType action;
  final String contentCid;
  final Uint8List previousHash;
  final Uint8List signature;
  final List<CrossSignature> crossSignatures;

  LedgerEntry({
    required this.index,
    required this.timestamp,
    required this.action,
    required this.contentCid,
    required this.previousHash,
    required this.signature,
    this.crossSignatures = const [],
  });

  /// Compute the hash of this entry for Merkle linking
  Uint8List computeHash() {
    final data =
        '$index|${timestamp.toIso8601String()}|${action.name}|$contentCid|${base64Encode(previousHash)}';
    final digest = sha256.convert(utf8.encode(data));
    return Uint8List.fromList(digest.bytes);
  }

  /// Verify that this entry's hash chain is intact
  bool verifyChain(Uint8List expectedPreviousHash) {
    for (var i = 0; i < previousHash.length; i++) {
      if (previousHash[i] != expectedPreviousHash[i]) return false;
    }
    return true;
  }

  /// Get the reputation points for this entry
  double getReputationPoints({bool accepted = false}) {
    final baseWeight = ReputationWeights.getWeight(action);
    return accepted
        ? baseWeight * ReputationWeights.acceptedMultiplier
        : baseWeight;
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'timestamp': timestamp.toIso8601String(),
        'action': action.name,
        'contentCid': contentCid,
        'previousHash': base64Encode(previousHash),
        'signature': base64Encode(signature),
        'crossSignatures': crossSignatures.map((cs) => cs.toJson()).toList(),
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      index: json['index'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      action: LedgerActionType.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => LedgerActionType.pinContent,
      ),
      contentCid: json['contentCid'] as String,
      previousHash: base64Decode(json['previousHash'] as String),
      signature: base64Decode(json['signature'] as String),
      crossSignatures: (json['crossSignatures'] as List?)
              ?.map((cs) => CrossSignature.fromJson(cs as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Service for managing the personal honor blockchain
class LedgerService {
  final IdentityService _identityService;
  final List<LedgerEntry> _entries = [];

  LedgerService(this._identityService);

  /// Genesis hash for the first entry
  static final Uint8List genesisHash = Uint8List.fromList(
    sha256.convert(utf8.encode('Alexandria Genesis')).bytes,
  );

  /// Get all ledger entries (lazy-loaded)
  List<LedgerEntry> get entries => List.unmodifiable(_entries);

  /// Get the total reputation score
  double get totalReputation {
    return _entries.fold(
      0.0,
      (sum, entry) => sum + entry.getReputationPoints(),
    );
  }

  /// Get effective reputation with time decay (Spec §12.3)
  /// Formula: effective_rep = total_rep × (0.99 ^ days_inactive)
  double getEffectiveReputation(DateTime lastActive) {
    final daysInactive = DateTime.now().difference(lastActive).inDays;
    final decayFactor = 0.99;
    return totalReputation *
        (daysInactive > 0 ? pow(decayFactor, daysInactive) : 1.0);
  }

  /// Power function for decay calculation
  double pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// Get the previous hash (or genesis if empty)
  Uint8List get _previousHash {
    if (_entries.isEmpty) return genesisHash;
    return _entries.last.computeHash();
  }

  /// Record a new action in the ledger
  Future<LedgerEntry> recordAction({
    required LedgerActionType action,
    required String contentCid,
  }) async {
    final timestamp = DateTime.now();
    final index = _entries.length;
    final previousHash = _previousHash;

    // Create the entry data to sign
    final data =
        '$index|${timestamp.toIso8601String()}|${action.name}|$contentCid|${base64Encode(previousHash)}';
    final dataBytes = Uint8List.fromList(utf8.encode(data));

    // Sign the entry
    final signature = await _identityService.sign(dataBytes);

    final entry = LedgerEntry(
      index: index,
      timestamp: timestamp,
      action: action,
      contentCid: contentCid,
      previousHash: previousHash,
      signature: signature,
    );

    _entries.add(entry);
    return entry;
  }

  /// Verify the entire chain is intact
  bool verifyChain() {
    if (_entries.isEmpty) return true;

    var expectedPreviousHash = genesisHash;
    for (final entry in _entries) {
      if (!entry.verifyChain(expectedPreviousHash)) {
        return false;
      }
      expectedPreviousHash = entry.computeHash();
    }
    return true;
  }

  /// Export the ledger as JSON
  String exportToJson() {
    return jsonEncode(_entries.map((e) => e.toJson()).toList());
  }

  /// Import a ledger from JSON
  Future<bool> importFromJson(String json) async {
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      final importedEntries = decoded
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      // Verify the imported chain
      var expectedPreviousHash = genesisHash;
      for (final entry in importedEntries) {
        if (!entry.verifyChain(expectedPreviousHash)) {
          return false;
        }
        expectedPreviousHash = entry.computeHash();
      }

      _entries.clear();
      _entries.addAll(importedEntries);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add a cross-signature to an entry (vouching)
  Future<void> addCrossSignature({
    required int entryIndex,
    required Uint8List signerPublicKey,
    required Uint8List signature,
  }) async {
    if (entryIndex < 0 || entryIndex >= _entries.length) return;

    final entry = _entries[entryIndex];
    final updatedEntry = LedgerEntry(
      index: entry.index,
      timestamp: entry.timestamp,
      action: entry.action,
      contentCid: entry.contentCid,
      previousHash: entry.previousHash,
      signature: entry.signature,
      crossSignatures: [
        ...entry.crossSignatures,
        CrossSignature(
          signerPublicKey: signerPublicKey,
          signature: signature,
          timestamp: DateTime.now(),
        ),
      ],
    );

    _entries[entryIndex] = updatedEntry;
  }

  /// Get action counts for today (for daily limits)
  Map<LedgerActionType, int> getTodayActionCounts() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final counts = <LedgerActionType, int>{};
    for (final entry in _entries) {
      if (entry.timestamp.isAfter(startOfDay)) {
        counts[entry.action] = (counts[entry.action] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Check if an action is within daily limits
  bool isWithinDailyLimit(LedgerActionType action) {
    final counts = getTodayActionCounts();
    final limit = ReputationWeights.dailyLimits[action] ?? 100;
    return (counts[action] ?? 0) < limit;
  }
}
