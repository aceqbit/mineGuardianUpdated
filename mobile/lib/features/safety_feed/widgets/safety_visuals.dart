import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/glass_card.dart';
import '../../../app/ui/read_aloud_button.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../data/safety_feed_repository.dart';

ChipTone kindTone(SafetyItemKind k) => switch (k) { SafetyItemKind.rule => ChipTone.warning, SafetyItemKind.prevent => ChipTone.success, SafetyItemKind.react => ChipTone.danger, SafetyItemKind.lesson => ChipTone.info };

IconData hazardIcon(String? category) => switch (category) {
      'GAS_LEAK' => Icons.air,
      'ROOF_FALL' => Icons.landslide,
      'FIRE_SMOKE' => Icons.local_fire_department,
      'FLOODING' => Icons.water,
      'ELECTRICAL' => Icons.bolt,
      'EQUIPMENT_FAILURE' => Icons.precision_manufacturing,
      'VENTILATION_FAILURE' => Icons.wind_power,
      _ => Icons.health_and_safety,
    };

String sourceLine(SafetyItem i) => i.sources.isEmpty ? '' : 'AI summary from ${i.sources.map((s) => s.domain).toSet().join(', ')} — confirm with your supervisor';

/// One feed item: kind, title, body, numbered steps and where it came from.
class SafetyItemCard extends StatelessWidget {
  const SafetyItemCard({super.key, required this.item});
  final SafetyItem item;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusChip(label: item.kind.label, tone: kindTone(item.kind), icon: item.kind.icon),
          const Spacer(),
          if (item.hazardCategory != null) Icon(hazardIcon(item.hazardCategory), color: c.muted),
        ]),
        const SizedBox(height: Space.md),
        Text(item.title, style: t.titleMedium),
        const SizedBox(height: Space.xs),
        Text(item.body, style: t.bodyMedium),
        if (item.steps.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          for (var i = 0; i < item.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(color: item.kind == SafetyItemKind.react ? c.dangerFill : c.ink700, shape: BoxShape.circle), child: Text('${i + 1}', style: t.labelMedium?.copyWith(color: Colors.white))),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(item.steps[i], style: t.bodyMedium)),
              ]),
            ),
        ],
        const SizedBox(height: Space.sm),
        Row(children: [
          Expanded(child: Text(sourceLine(item), style: t.labelSmall?.copyWith(color: c.muted))),
          ReadAloudButton(owner: 'safety-${item.id}', label: 'Read aloud', segments: [item.title, item.body, ...item.steps]),
        ]),
      ]),
    );
  }
}

/// AI-scripted animated explainer (SAFETY_VIDEO_MODE=storyboard): one frame every 4 s with a progress bar, drawn icon and
/// on-device narration. Static (manual next/previous) under reduced motion.
class StoryboardPlayer extends StatefulWidget {
  const StoryboardPlayer({super.key, required this.video, this.hazardCategory});
  final FeedVideo video;
  final String? hazardCategory;
  @override
  State<StoryboardPlayer> createState() => _StoryboardPlayerState();
}

class _StoryboardPlayerState extends State<StoryboardPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  int _i = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _p.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        if (_i < widget.video.frames.length - 1) {
          setState(() => _i++);
          _p.forward(from: 0);
        } else {
          setState(() => _playing = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _toggle() {
    if (Motion.reduce(context)) return;
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_i >= widget.video.frames.length - 1 && _p.isCompleted) _i = 0;
      _p.forward(from: _p.isCompleted ? 0 : _p.value);
    } else {
      _p.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final frames = widget.video.frames;
    if (frames.isEmpty) return const SizedBox.shrink();
    final reduce = Motion.reduce(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: ColoredBox(
        color: c.ink900,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const StatusChip(label: 'AI-generated explainer', tone: ChipTone.info),
            const SizedBox(height: Space.sm),
            Text(widget.video.title, style: t.titleMedium?.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.md),
            AnimatedBuilder(
              animation: _p,
              builder: (context, _) => Row(children: [
                for (var k = 0; k < frames.length; k++) ...[
                  if (k > 0) const SizedBox(width: Space.xs),
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(minHeight: 3, value: k < _i ? 1 : (k == _i ? (_playing ? _p.value : (reduce ? 1 : _p.value)) : 0), backgroundColor: Colors.white24, color: c.amber500))),
                ],
              ]),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              height: 150,
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.slow),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a), child: child)),
                child: Row(key: ValueKey(_i), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: c.amber500.withValues(alpha: 0.18), shape: BoxShape.circle, border: Border.all(color: c.amber500, width: 2)), child: Icon(_i == 0 ? hazardIcon(widget.hazardCategory) : _stepIcon(_i), color: c.amber500, size: 32)),
                  const SizedBox(width: Space.lg),
                  Expanded(child: SingleChildScrollView(child: Text(frames[_i], style: t.titleMedium?.copyWith(color: Colors.white, height: 1.35)))),
                ]),
              ),
            ),
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              IconButton.filledTonal(tooltip: 'Previous', onPressed: _i == 0 ? null : () => setState(() => _i--), icon: const Icon(Icons.skip_previous)),
              if (!reduce) IconButton.filled(tooltip: _playing ? 'Pause' : 'Play', onPressed: _toggle, icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
              IconButton.filledTonal(tooltip: 'Next', onPressed: _i >= frames.length - 1 ? null : () => setState(() => _i++), icon: const Icon(Icons.skip_next)),
              ReadAloudButton(owner: 'storyboard-${widget.video.itemId}', label: 'Narrate', segments: frames),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Numbered badge for step frame n (1..6).
IconData _stepIcon(int n) => switch (n) { 1 => Icons.looks_one, 2 => Icons.looks_two, 3 => Icons.looks_3, 4 => Icons.looks_4, 5 => Icons.looks_5, _ => Icons.looks_6 };

/// Paid AI clip (SAFETY_VIDEO_MODE=veo), from a 15-minute signed link.
class VeoClip extends StatefulWidget {
  const VeoClip({super.key, required this.video});
  final FeedVideo video;
  @override
  State<VeoClip> createState() => _VeoClipState();
}

class _VeoClipState extends State<VeoClip> {
  VideoPlayerController? _v;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.video.url!));
    _v = c;
    unawaited(c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    }));
  }

  @override
  void dispose() {
    _v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final v = _v;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StatusChip(label: 'AI-generated video', tone: ChipTone.info),
      const SizedBox(height: Space.sm),
      Text(widget.video.title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.sm),
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card),
          child: ColoredBox(
            color: c.ink900,
            child: _failed || v == null
                ? Center(child: Text('The clip could not be loaded', style: TextStyle(color: c.slate300)))
                : !v.value.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                        child: Stack(alignment: Alignment.center, children: [VideoPlayer(v), if (!v.value.isPlaying) Icon(Icons.play_circle, size: 64, color: Colors.white.withValues(alpha: 0.9))]),
                      ),
          ),
        ),
      ),
    ]);
  }
}
