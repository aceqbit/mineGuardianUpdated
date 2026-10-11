import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'tile_art.dart';

/// Navy gradient header with an optional photo wash, rounded bottom corners and a content slot.
/// Used at the top of the role home screens so each starts with who/where/what-now in one glance.
class MgHeroHeader extends StatelessWidget {
  const MgHeroHeader({super.key, required this.title, this.subtitle, this.eyebrow, this.imageUrl, this.art, this.trailing, this.child, this.padding});
  final String title;
  final String? subtitle;

  /// Small label above the title (e.g. "Good morning").
  final String? eyebrow;
  final String? imageUrl;

  /// Drawn illustration used as the background wash (no network needed).
  final TileArtKind? art;
  final Widget? trailing;

  /// Content under the title (chips, rings, progress).
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sheet),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.ink800, c.ink600])),
          child: Stack(children: [
            if (art != null) Positioned.fill(child: Opacity(opacity: 0.55, child: TileArt(kind: art!))),
            if (imageUrl != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.18,
                  child: CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover, fadeInDuration: Motion.of(context, Motion.slow), errorWidget: (_, _, _) => const SizedBox.shrink(), placeholder: (_, _) => const SizedBox.shrink()),
                ),
              ),
            Padding(
              padding: padding ?? const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (eyebrow != null) Text(eyebrow!, style: t.labelMedium?.copyWith(color: c.amber500, letterSpacing: 0.8)),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headlineMedium?.copyWith(color: Colors.white)),
                      if (subtitle != null) ...[const SizedBox(height: Space.xs), Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: c.slate300))],
                    ]),
                  ),
                  if (trailing != null) ...[const SizedBox(width: Space.md), trailing!],
                ]),
                if (child != null) ...[const SizedBox(height: Space.lg), child!],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
