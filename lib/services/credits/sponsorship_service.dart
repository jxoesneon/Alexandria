import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'credit_models.dart';
import 'credit_service.dart';

/// Provider for SponsorshipService
final sponsorshipServiceProvider =
    ChangeNotifierProvider<SponsorshipService>((ref) {
  final creditService = ref.read(creditServiceProvider);
  return SponsorshipService(creditService: creditService);
});

/// Provider for whether the user has opted in to ethical community sponsorships
final sponsorshipOptInProvider = Provider<bool>((ref) {
  final service = ref.watch(sponsorshipServiceProvider);
  return service.isOptInEnabled;
});

/// Service managing privacy-preserving, opt-in institutional sponsorships (ALX-005 §5)
class SponsorshipService extends ChangeNotifier {
  final CreditService _creditService;
  bool _isOptInEnabled;

  final List<SponsorshipSlot> _catalog = [];
  final List<ImpressionReceipt> _impressionHistory = [];

  SponsorshipService({
    required CreditService creditService,
    bool initialOptIn = false, // Strictly false by default for user privacy
  })  : _creditService = creditService,
        _isOptInEnabled = initialOptIn {
    _populateDefaultCatalog();
  }

  bool get isOptInEnabled => _isOptInEnabled;
  List<SponsorshipSlot> get catalog => List.unmodifiable(_catalog);
  List<ImpressionReceipt> get impressionHistory =>
      List.unmodifiable(_impressionHistory);

  /// Toggle user opt-in status in Settings
  void toggleOptIn(bool enabled) {
    _isOptInEnabled = enabled;
    notifyListeners();
  }

  /// In-memory client-side contextual match against the open catalog
  SponsorshipSlot? findMatchingSlot({
    required String category,
    List<String> tags = const [],
  }) {
    if (!_isOptInEnabled || _catalog.isEmpty) return null;

    // Search for explicit category or tag match
    for (final slot in _catalog) {
      if (slot.matchesContext(category, tags)) {
        return slot;
      }
    }

    // Fallback to first general patronage slot if no specific category matches
    return _catalog.first;
  }

  /// Validates dwell time (>= 5.0 seconds) and settles the 85 / 10 / 5 revenue split
  ImpressionReceipt? recordDwellImpression({
    required SponsorshipSlot slot,
    required double dwellTimeSeconds,
  }) {
    if (!_isOptInEnabled) return null;
    // `!isFinite` first (round-1 red finding): `NaN < 5.0` is FALSE, so a
    // non-finite dwell slips past the attention threshold and mints a
    // sponsorship kickback for a measurement that never happened. Reject
    // before any comparison — no receipt, no mint.
    if (!dwellTimeSeconds.isFinite || dwellTimeSeconds < 5.0) {
      return null; // Minimum attention threshold (ALX-005 §5.1)
    }

    final receipt = _creditService.awardSponsorshipKickback(
      campaignId: slot.campaignId,
      grossCredits: slot.rewardCredits,
      dwellTimeSeconds: dwellTimeSeconds,
    );

    _impressionHistory.add(receipt);
    notifyListeners();
    return receipt;
  }

  void _populateDefaultCatalog() {
    _catalog.addAll(const [
      SponsorshipSlot(
        campaignId: 'eff-digital-rights-2026',
        sponsorName: 'Electronic Frontier Foundation',
        badgeText:
            'Championing user privacy, open encryption, and digital freedom across the globe.',
        actionUrl: 'https://eff.org',
        categories: ['technology', 'law', 'security', 'privacy', 'computer_science'],
        tags: ['cryptography', 'freedom', 'open-source', 'privacy', 'tor'],
        rewardCredits: 10.0,
      ),
      SponsorshipSlot(
        campaignId: 'internet-archive-preservation',
        sponsorName: 'Internet Archive Open Library',
        badgeText:
            'Universal access to all knowledge: building digital libraries for future generations.',
        actionUrl: 'https://archive.org',
        categories: ['literature', 'history', 'philosophy', 'arts', 'classics'],
        tags: ['preservation', 'scanned-books', 'libraries', 'public-domain'],
        rewardCredits: 8.0,
      ),
      SponsorshipSlot(
        campaignId: 'openalex-scholarly-commons',
        sponsorName: 'OurResearch / OpenAlex',
        badgeText:
            'Powering open science: fully accessible, transparent global research index.',
        actionUrl: 'https://openalex.org',
        categories: ['academicAndScience', 'science', 'medicine', 'mathematics', 'physics'],
        tags: ['doi', 'research', 'papers', 'citations', 'peer-review'],
        rewardCredits: 12.0,
      ),
      SponsorshipSlot(
        campaignId: 'wikimedia-free-knowledge',
        sponsorName: 'Wikimedia Foundation',
        badgeText:
            'Empowering a world in which every human being can freely share in the sum of all knowledge.',
        actionUrl: 'https://wikimediafoundation.org',
        categories: ['general', 'reference', 'encyclopedia', 'other'],
        tags: ['open-knowledge', 'education', 'commons'],
        rewardCredits: 7.0,
      ),
    ]);
  }
}
