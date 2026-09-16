import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Categories of credit transactions in Alexandria
enum CreditType {
  storageReward,
  computeReward,
  verificationReward,
  sponsorshipKickback,
  priorityAccessDebit,
  pinningRequestDebit,
  protocolFeeDebit,
}

/// Double-entry record for an archival credit transaction
class CreditTransaction {
  final String id;
  final DateTime timestamp;
  final CreditType type;
  final double amount;
  final String description;
  final String? referenceId;
  final String hash;

  /// TRUE only when this credit derives from a verifier-signed work receipt
  /// whose verifier pubkey differs from the local identity (ALX-010
  /// self-dealing guard). Locally self-certified mints are always FALSE.
  final bool isAttested;

  /// Canonical prover pubkey this attested mint belongs to (schema v7 —
  /// multi-identity sharding). Non-null only on attested CREDIT rows
  /// written by a v7+ build: the egress gate sums attested value per
  /// currently-held key, so value minted under a rotated-out identity
  /// stops backing egress once the key leaves the held set. Null =
  /// the unscoped legacy bucket (pre-v7 rows and egress debit rows
  /// themselves), which counts toward any held-key set. Deliberately
  /// NOT part of [computeHash] — the hash predates the column and is
  /// display-only.
  final String? attestedPubkey;

  /// How much of this row's debit consumed the ATTESTED pool (schema v8
  /// `burned_attested`) — the durable mirror of the service's
  /// unattested-first burn attribution. Non-zero only on debit rows: the
  /// attested share an ordinary debit burned once the unattested pool
  /// ran dry, or the full |amount| on attested-flagged egress rows.
  /// Mints and PoR penalty rows carry 0. The in-memory replay still
  /// derives burns itself; the column is what the durable egress gate
  /// sums. Deliberately NOT part of [computeHash].
  final double burnedAttested;

  CreditTransaction({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.description,
    this.referenceId,
    required this.hash,
    this.isAttested = false,
    this.attestedPubkey,
    this.burnedAttested = 0.0,
  });

  static String computeHash({
    required String id,
    required DateTime timestamp,
    required CreditType type,
    required double amount,
    required String description,
    String? referenceId,
    bool isAttested = false,
  }) {
    final raw =
        '$id|${timestamp.toIso8601String()}|${type.name}|$amount|$description|${referenceId ?? ''}|$isAttested';
    // Full-width sha256 (64 hex chars). Earlier builds truncated the
    // digest to 16 chars; persisted short hashes are tolerated — the
    // hash is display-only and never gates a ledger invariant.
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'amount': amount,
        'description': description,
        'referenceId': referenceId,
        'hash': hash,
        'isAttested': isAttested,
        'attestedPubkey': attestedPubkey,
        'burnedAttested': burnedAttested,
      };

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['timestamp'];
    return CreditTransaction(
      id: json['id'] as String,
      // Drift rows hand back DateTime; JSON blobs hand back ISO strings.
      timestamp: rawTimestamp is DateTime
          ? rawTimestamp
          : DateTime.parse(rawTimestamp as String),
      type: CreditType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CreditType.storageReward,
      ),
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      referenceId: json['referenceId'] as String?,
      hash: json['hash'] as String,
      isAttested: json['isAttested'] as bool? ?? false,
      attestedPubkey: json['attestedPubkey'] as String?,
      burnedAttested: (json['burnedAttested'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Metrics governing Proof of Common Heritage (PoCH - ALX-005 §3)
class PoCHMetrics {
  final int allocatedStorageBytes;
  final int dailySeedingBytes;
  final int dailyPoRChallengesAnswered;
  final DateTime lastCalculated;

  const PoCHMetrics({
    required this.allocatedStorageBytes,
    required this.dailySeedingBytes,
    required this.dailyPoRChallengesAnswered,
    required this.lastCalculated,
  });

  /// Minimum thresholds required for unchoked baseline access
  static const int minStorageBytes = 1000 * 1024 * 1024; // 1 GB baseline
  static const int minSeedingBytes = 500 * 1024 * 1024; // 500 MB / day
  static const int minDailyChallenges = 12; // 12 challenges / day

  /// Evaluates normalized score [0.0, 1.0] across Storage, Seeding, and Verification
  double get score {
    final sScore = (allocatedStorageBytes / minStorageBytes).clamp(0.0, 1.0);
    final bScore = (dailySeedingBytes / minSeedingBytes).clamp(0.0, 1.0);
    final vScore =
        (dailyPoRChallengesAnswered / minDailyChallenges).clamp(0.0, 1.0);

    // Alpha = 0.4, Beta = 0.4, Gamma = 0.2
    return (0.4 * sScore) + (0.4 * bScore) + (0.2 * vScore);
  }

  /// Whether the node fulfills the mandatory minimum baseline contribution
  bool get isCompliant => score >= 0.50;

  /// QoS Bandwidth multiplier applied to swarm transfer queue (ALX-005 §3.2)
  double get bandwidthMultiplier {
    const threshold = 0.50;
    const floor = 0.10; // 10% base trickle bandwidth for freeloaders

    if (score < threshold) {
      // Quadratic degradation curve
      return floor * pow(score / threshold, 2);
    } else {
      // Logarithmic bonus unchoking curve
      return 1.0 + 0.50 * (log(1.0 + score - threshold) / ln10);
    }
  }

  Map<String, dynamic> toJson() => {
        'allocatedStorageBytes': allocatedStorageBytes,
        'dailySeedingBytes': dailySeedingBytes,
        'dailyPoRChallengesAnswered': dailyPoRChallengesAnswered,
        'lastCalculated': lastCalculated.toIso8601String(),
        'score': score,
        'isCompliant': isCompliant,
        'bandwidthMultiplier': bandwidthMultiplier,
      };
}

/// An ethical, privacy-preserving institutional sponsorship slot (ALX-005 §5)
class SponsorshipSlot {
  final String campaignId;
  final String sponsorName;
  final String badgeText;
  final String actionUrl;
  final List<String> categories;
  final List<String> tags;
  final double rewardCredits;

  const SponsorshipSlot({
    required this.campaignId,
    required this.sponsorName,
    required this.badgeText,
    required this.actionUrl,
    required this.categories,
    required this.tags,
    required this.rewardCredits,
  });

  /// In-memory client-side contextual matching with zero telemetry or network leakage
  bool matchesContext(String category, List<String> documentTags) {
    final catLower = category.toLowerCase().trim();
    if (categories.any((c) => c.toLowerCase().trim() == catLower)) return true;
    for (final tag in documentTags) {
      final tagLower = tag.toLowerCase().trim();
      if (tags.any((t) => t.toLowerCase().trim() == tagLower)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'sponsorName': sponsorName,
        'badgeText': badgeText,
        'actionUrl': actionUrl,
        'categories': categories,
        'tags': tags,
        'rewardCredits': rewardCredits,
      };
}

/// Cryptographic impression receipt for a verified sponsorship dwell
class ImpressionReceipt {
  final String campaignId;
  final DateTime timestamp;
  final double dwellTimeSeconds;
  final String nonce;
  final double grossCredits;
  final double clientKickback;
  final double archivalCommonsPool;
  final double protocolFee;

  ImpressionReceipt({
    required this.campaignId,
    required this.timestamp,
    required this.dwellTimeSeconds,
    required this.nonce,
    required this.grossCredits,
    required this.clientKickback,
    required this.archivalCommonsPool,
    required this.protocolFee,
  });

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'timestamp': timestamp.toIso8601String(),
        'dwellTimeSeconds': dwellTimeSeconds,
        'nonce': nonce,
        'grossCredits': grossCredits,
        'clientKickback': clientKickback,
        'archivalCommonsPool': archivalCommonsPool,
        'protocolFee': protocolFee,
      };
}
