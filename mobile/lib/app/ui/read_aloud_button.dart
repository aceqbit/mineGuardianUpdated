import 'package:flutter/material.dart';

import '../../core/speech/speech_service.dart';
import '../theme/tokens.dart';
import 'voice_settings_sheet.dart';

/// Play / stop control that reads [segments] aloud. Stops its own speech when removed from the tree.
/// Pass [service] only in tests; otherwise the shared [SpeechService.instance] is used.
class ReadAloudButton extends StatefulWidget {
  const ReadAloudButton({super.key, required this.owner, required this.segments, this.label, this.service, this.onDark = false});

  /// Unique id of the thing being read, e.g. `first-aid:Burns`. Only the owner's button shows "stop".
  final String owner;
  final List<String> segments;

  /// When set, renders a labelled pill; otherwise a compact icon button.
  final String? label;
  final SpeechService? service;
  final bool onDark;

  @override
  State<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<ReadAloudButton> {
  SpeechService get _svc => widget.service ?? SpeechService.instance;

  @override
  void dispose() {
    if (_svc.state.value.owner == widget.owner) _svc.stop();
    super.dispose();
  }

  void _toggle(bool mine) => mine ? _svc.stop() : _svc.speak(widget.segments, owner: widget.owner);

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return ValueListenableBuilder<SpeechState>(
      valueListenable: _svc.state,
      builder: (context, st, _) {
        final mine = st.speaking && st.owner == widget.owner;
        final icon = mine ? Icons.stop_circle_outlined : Icons.volume_up_rounded;
        final tip = mine ? 'Stop reading' : 'Read aloud';
        final color = widget.onDark ? Colors.white : c.amber600;
        if (widget.label == null) {
          return IconButton(tooltip: tip, icon: Icon(icon, color: color), onPressed: () => _toggle(mine));
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Semantics(
              button: true,
              label: tip,
              child: ActionChip(
                avatar: Icon(icon, size: 18, color: color),
                label: Text(mine ? 'Stop' : widget.label!, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => _toggle(mine),
              ),
            ),
          ),
          IconButton(tooltip: 'Voice and speed', icon: Icon(Icons.tune, size: 20, color: widget.onDark ? Colors.white : c.muted), onPressed: () => showVoiceSettings(context, service: widget.service)),
        ]);
      },
    );
  }
}
