import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'skeleton.dart';

/// Image tile: network image, dark gradient, centred 56 px glass icon badge, shimmer, gradient fallback.
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
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [c.ink700, c.ink900], begin: Alignment.topLeft, end: Alignment.bottomRight)),
    );
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
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Motion.of(context, Motion.base),
                    placeholder: (_, _) => const Skeleton(radius: 0),
                    errorWidget: (_, _, _) => fallback,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.ink900.withValues(alpha: 0.25), c.ink900.withValues(alpha: 0.85)],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
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
