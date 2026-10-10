import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'tile_art.dart';

/// Illustrated tile: art drawn in code (see tile_art.dart), dark gradient for legible text, corner glass icon badge, title and subtitle.
class MediaTile extends StatelessWidget {
  const MediaTile({super.key, required this.imageUrl, required this.icon, required this.title, this.subtitle, this.onTap, this.aspectRatio = 1.15});
  final String imageUrl;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card),
          child: Material(
            color: c.ink900,
            child: InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Drawn illustration only: network photos rendered as solid black boxes in Chrome and added nothing offline.
                  TileArt(kind: tileArtFor(imageUrl)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.ink900.withValues(alpha: 0.0), c.ink900.withValues(alpha: 0.8)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: Space.md,
                    top: Space.md,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                  ),
                  Positioned(
                    left: Space.md,
                    right: Space.md,
                    bottom: Space.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                        if (subtitle != null)
                          Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
