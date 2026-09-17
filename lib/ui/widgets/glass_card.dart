import 'package:flutter/material.dart';

/// A plain bordered surface container.
///
/// Formerly a glassmorphic blur card; now a simple bordered [Container] that
/// blends with the editorial theme. The public API is preserved so existing
/// call sites continue to work unchanged.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.onTap,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
      ),
      borderRadius: BorderRadius.circular(12.0),
    );

    final content = Container(
      height: height,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: content,
      ),
    );
  }
}
