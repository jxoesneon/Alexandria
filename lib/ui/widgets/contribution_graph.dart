import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ContributionGraph extends StatelessWidget {
  final Map<DateTime, int> activityData;
  final ScrollController? scrollController;

  const ContributionGraph({
    super.key,
    required this.activityData,
    this.scrollController,
  });

  /// Groups dates into a map of YYYY-MM-DD -> count
  static Map<DateTime, int> normalizeData(List<DateTime> rawDates) {
    final normalized = <DateTime, int>{};
    for (var date in rawDates) {
      final key = DateTime(date.year, date.month, date.day);
      normalized[key] = (normalized[key] ?? 0) + 1;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the grid
    final now = DateTime.now();
    // Start from 1 year ago (approx 52 weeks)
    // Align to the PREVIOUS Sunday to start the grid correctly
    final oneYearAgo = now.subtract(const Duration(days: 365));
    // Find the Sunday before or on oneYearAgo
    final startDate = oneYearAgo.subtract(
      Duration(days: oneYearAgo.weekday % 7),
    );

    return SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      reverse: true, // Start from right (today) like GitHub
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(53, (weekIndex) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (dayIndex) {
                // Show Mon-Fri (5 days) to fit in constrained height
                final currentDate = startDate.add(
                  Duration(days: (weekIndex * 7) + dayIndex + 1),
                );

                // Don't render future days
                if (currentDate.isAfter(now)) {
                  return const SizedBox(width: 10, height: 10);
                }

                // Normalize query date
                final checkDate = DateTime(
                  currentDate.year,
                  currentDate.month,
                  currentDate.day,
                );
                final count = activityData[checkDate] ?? 0;

                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: _getColorForCount(count),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Tooltip(
                    message:
                        '${_formatDate(currentDate)}: $count contributions',
                    child: const SizedBox.expand(),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  Color _getColorForCount(int count) {
    if (count == 0) return AppTheme.surfaceColor.withValues(alpha: 0.5);
    if (count == 1) return AppTheme.primaryColor.withValues(alpha: 0.3);
    if (count <= 3) return AppTheme.primaryColor.withValues(alpha: 0.6);
    return AppTheme.primaryColor;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
