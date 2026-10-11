import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'skeleton.dart';

/// Cache key for a photo link. Signed links change with every snapshot (new expiry and signature) but point at the same
/// picture, so the key is the stored file, not the link: an already loaded photo stays visible after its link expires.
String photoCacheKey(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return url;
  final seg = u.pathSegments;
  if (seg.length >= 2 && seg.first == 'files') return 'files/${seg[1].split('.').first}';
  return u.replace(query: '', fragment: '').toString();
}

/// A photo from the backend (check-in or hazard) with a skeleton while it loads and a quiet icon when it is missing or
/// cannot be loaded, so a tile never shows a broken-image glyph.
class NetPhoto extends StatelessWidget {
  const NetPhoto({super.key, required this.url, this.fit = BoxFit.cover, this.fallbackIcon = Icons.image_outlined});
  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    Widget fallback() => ColoredBox(color: c.border, child: Center(child: Icon(fallbackIcon, color: c.muted)));
    final u = url;
    if (u == null || u.isEmpty) return fallback();
    return CachedNetworkImage(
      imageUrl: u,
      cacheKey: photoCacheKey(u),
      fit: fit,
      placeholder: (_, _) => const Skeleton(radius: 0),
      errorWidget: (_, _, _) => fallback(),
    );
  }
}

/// Full-screen, pinch-to-zoom view of one photo.
Future<void> showPhotoViewer(BuildContext context, {required String? url, required String title}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final c = MgColors.of(ctx);
      final t = Theme.of(ctx).textTheme;
      return Dialog.fullscreen(
        backgroundColor: c.ink900,
        child: SafeArea(
          child: Stack(children: [
            Positioned.fill(child: InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: NetPhoto(url: url, fit: BoxFit.contain)))),
            Positioned(
              left: Space.lg,
              right: Space.x4 + Space.lg,
              top: Space.md,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(color: Colors.white)),
            ),
            Positioned(right: Space.sm, top: Space.xs, child: IconButton(tooltip: 'Close photo', color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      );
    },
  );
}
