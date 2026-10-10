import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme/motion.dart';
import 'theme/tokens.dart';

enum SizeClass { compact, medium, expanded }

SizeClass sizeClassForWidth(double w) {
  if (w < 600) return SizeClass.compact;
  if (w < 1024) return SizeClass.medium;
  return SizeClass.expanded;
}

extension ResponsiveContext on BuildContext {
  SizeClass get sizeClass => sizeClassForWidth(MediaQuery.sizeOf(this).width);
  bool get isCompact => sizeClass == SizeClass.compact;
  bool get isExpanded => sizeClass == SizeClass.expanded;
}

/// Number of columns for an adaptive grid: clamp(floor((w+s)/(min+s)), 1, max).
int adaptiveColumns(double width, {double minTileWidth = 160, int maxColumns = 4, double spacing = 16}) {
  final n = ((width + spacing) / (minTileWidth + spacing)).floor();
  return n.clamp(1, maxColumns);
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160,
    this.maxColumns = 4,
    this.spacing = Space.lg,
    this.aspectRatio = 1.15,
    this.fixedTileHeight,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;
  final double aspectRatio;
  final double? fixedTileHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = adaptiveColumns(c.maxWidth, minTileWidth: minTileWidth, maxColumns: maxColumns, spacing: spacing);
      return GridView.count(
        crossAxisCount: cols,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: fixedTileHeight == null ? aspectRatio : math.max(0.1, ((c.maxWidth - spacing * (cols - 1)) / cols) / fixedTileHeight!),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (var i = 0; i < children.length; i++) StaggerIn(index: i, child: children[i])],
      );
    });
  }
}

/// Centres content and caps its width (440 forms, 1200 pages).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = Widths.page, this.padding});
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.symmetric(horizontal: context.isCompact ? Space.lg : Space.x2);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: Padding(padding: pad, child: child)),
    );
  }
}
