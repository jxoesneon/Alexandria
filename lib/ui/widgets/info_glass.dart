import 'package:flutter/material.dart';
import 'glass_card.dart';

class InfoGlass extends StatelessWidget {
  final String title;
  final String? value;
  final IconData? icon;
  final String? description;
  final bool small;
  final Color? color;

  const InfoGlass({
    super.key,
    required this.title,
    this.value,
    this.icon,
    this.description,
    this.small = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.primary;
    final titleStyle = (small
            ? Theme.of(context).textTheme.labelMedium
            : Theme.of(context).textTheme.titleSmall)
        ?.copyWith(
      fontWeight: FontWeight.bold,
      color: foreground,
    );

    final bodyStyle = (small
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.bodyMedium)
        ?.copyWith(
      color: foreground.withValues(alpha: 0.8),
    );

    if (value != null) {
      return GlassCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.info, color: foreground),
            const SizedBox(width: 12.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                Text(value!,
                    style: bodyStyle?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      );
    }

    return GlassCard(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: foreground),
          const SizedBox(width: 12.0),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                if (description != null)
                  Text(
                    description!,
                    style: bodyStyle,
                    softWrap: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
