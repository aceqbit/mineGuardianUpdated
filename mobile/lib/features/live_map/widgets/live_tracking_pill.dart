import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../contracts/enums.dart';
import '../../../core/location/tracking_controller.dart';
import '../bloc/live_tracking_bloc.dart';

const trackingConsentText =
    'Mine Guardian shares your live location with your zone supervisor and the control room during your shift and in an '
    'emergency, so they can find you and guide you out. It uses GPS and your phone\'s motion sensors, which keep working '
    'underground where GPS is weak. Sharing stops outside your shift. You can pause it at any time, except during an emergency.';

/// App-bar "Live" pill for miners (CLAUDE.md section 23.3). Renders nothing when tracking is not wired (tests, other roles).
class LiveTrackingPill extends StatelessWidget {
  const LiveTrackingPill({super.key});

  @override
  Widget build(BuildContext context) {
    TrackingController? controller;
    try {
      controller = RepositoryProvider.of<TrackingController>(context);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return BlocProvider(
      create: (_) => LiveTrackingBloc(controller: controller!)..add(const LiveTrackingWatched()),
      child: const _Pill(),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill();
  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _askedThisSession = false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LiveTrackingBloc, LiveTrackingState>(
      listenWhen: (a, b) => a.status.phase != b.status.phase,
      listener: (context, s) {
        if (s.status.phase == TrackingPhase.needsConsent && !_askedThisSession) {
          _askedThisSession = true;
          _openSheet(context);
        }
      },
      builder: (context, s) {
        final st = s.status;
        if (st.phase == TrackingPhase.notMiner) return const SizedBox.shrink();
        final c = MgColors.of(context);
        final compact = context.sizeClass == SizeClass.compact;
        final (label, color, live) = _look(st, c);
        return Semantics(
          button: true,
          liveRegion: true,
          label: 'Location sharing: $label',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: () => _openSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (live) PulseDot(color: color, size: 8) else Icon(Icons.location_off, size: 16, color: color),
                const SizedBox(width: Space.xs),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 72 : 140),
                  child: Text(compact ? label.split(' · ').first : label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  static (String, Color, bool) _look(TrackingStatus st, MgColors c) => switch (st.phase) {
        TrackingPhase.live when st.crisis => ('Live · emergency', c.danger, true),
        TrackingPhase.live => ('Live · ${_src(st.source)}', c.success, true),
        TrackingPhase.starting => ('Starting…', c.amberText, true),
        TrackingPhase.paused => ('Paused', c.muted, false),
        TrackingPhase.outsideShift => ('Off shift', c.muted, false),
        TrackingPhase.declined => ('Sharing off', c.muted, false),
        TrackingPhase.denied => ('Location blocked', c.danger, false),
        TrackingPhase.needsConsent => ('Share location?', c.amberText, false),
        TrackingPhase.notMiner => ('', c.muted, false),
      };

  static String _src(PositionSource? s) => switch (s) {
        PositionSource.gps => 'GPS',
        PositionSource.fused => 'GPS + sensors',
        PositionSource.pdr => 'sensors only',
        null => 'waiting for fix',
      };

  void _openSheet(BuildContext context) {
    final bloc = context.read<LiveTrackingBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(value: bloc, child: const _TrackingSheet()),
    );
  }
}

class _TrackingSheet extends StatelessWidget {
  const _TrackingSheet();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    return BlocBuilder<LiveTrackingBloc, LiveTrackingState>(
      builder: (context, s) {
        final st = s.status;
        final bloc = context.read<LiveTrackingBloc>();
        final consentAsked = st.phase == TrackingPhase.needsConsent || st.phase == TrackingPhase.declined;
        final fix = st.fix;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.form),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Live location sharing', style: t.titleLarge),
                const SizedBox(height: Space.md),
                Text(trackingConsentText, style: t.bodyMedium?.copyWith(color: c.muted)),
                const SizedBox(height: Space.lg),
                if (consentAsked) ...[
                  MgButton(label: 'Allow location sharing', icon: Icons.my_location, expand: true, onPressed: () {
                    bloc.add(const LiveTrackingConsentAnswered(true));
                    Navigator.of(context).maybePop();
                  }),
                  const SizedBox(height: Space.sm),
                  if (st.phase == TrackingPhase.needsConsent)
                    MgButton(label: 'Not now', kind: MgButtonKind.secondary, expand: true, onPressed: () {
                      bloc.add(const LiveTrackingConsentAnswered(false));
                      Navigator.of(context).maybePop();
                    }),
                ] else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Share my location'),
                    subtitle: Text(st.crisis ? 'Always on during an emergency' : _phaseText(st.phase)),
                    value: st.crisis || st.phase == TrackingPhase.live || st.phase == TrackingPhase.starting || st.phase == TrackingPhase.outsideShift,
                    onChanged: st.crisis ? null : (v) => bloc.add(LiveTrackingToggled(v)),
                  ),
                  if (fix != null) ...[
                    const SizedBox(height: Space.sm),
                    Text('Last position ±${fix.accuracyM.round()} m · ${_PillState._src(fix.source)}${fix.tunnelId == null ? '' : ' · ${fix.tunnelId}'}', style: t.labelMedium?.copyWith(color: c.muted)),
                  ],
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  static String _phaseText(TrackingPhase p) => switch (p) {
        TrackingPhase.live => 'Sharing now',
        TrackingPhase.starting => 'Starting…',
        TrackingPhase.paused => 'Paused by you',
        TrackingPhase.outsideShift => 'Starts automatically in your shift window',
        TrackingPhase.denied => 'Location permission is blocked in the phone settings',
        _ => '',
      };
}
