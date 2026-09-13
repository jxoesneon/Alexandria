import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/credits/credit_models.dart';
import '../../services/credits/sponsorship_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Contextual, privacy-preserving institutional sponsorship card (ALX-005 §5)
/// Only renders if the user has explicitly opted in to sponsorships.
class SponsorshipCard extends ConsumerStatefulWidget {
  final String category;
  final List<String> tags;

  const SponsorshipCard({
    super.key,
    required this.category,
    this.tags = const [],
  });

  @override
  ConsumerState<SponsorshipCard> createState() => _SponsorshipCardState();
}

class _SponsorshipCardState extends ConsumerState<SponsorshipCard> {
  Timer? _dwellTimer;
  bool _rewardClaimed = false;
  SponsorshipSlot? _currentSlot;

  @override
  void initState() {
    super.initState();
    _startDwellCountdown();
  }

  void _startDwellCountdown() {
    _dwellTimer?.cancel();
    _dwellTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_currentSlot != null && !_rewardClaimed) {
        final service = ref.read(sponsorshipServiceProvider);
        final receipt = service.recordDwellImpression(
          slot: _currentSlot!,
          dwellTimeSeconds: 5.0,
        );
        if (receipt != null && mounted) {
          setState(() {
            _rewardClaimed = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOptIn = ref.watch(sponsorshipOptInProvider);
    if (!isOptIn) {
      return const SizedBox.shrink(); // Zero visual footprint when opted out
    }

    final sponsorshipService = ref.watch(sponsorshipServiceProvider);
    final slot = sponsorshipService.findMatchingSlot(
      category: widget.category,
      tags: widget.tags,
    );

    if (slot == null) {
      return const SizedBox.shrink();
    }

    _currentSlot = slot;
    final userKickback = slot.rewardCredits * 0.85;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.volunteer_activism_outlined,
                color: AppTheme.primaryAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ETHICAL SPONSOR',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        slot.sponsorName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                      const Spacer(),
                      if (_rewardClaimed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${userKickback.toStringAsFixed(1)} ℭ Claimed',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        )
                      else
                        Text(
                          '+${userKickback.toStringAsFixed(1)} ℭ Kickback',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    slot.badgeText,
                    style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
