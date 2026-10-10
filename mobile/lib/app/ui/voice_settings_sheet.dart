import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/db/cache_repository.dart';
import '../../core/speech/speech_prefs_store.dart';
import '../../core/speech/speech_service.dart';
import '../theme/tokens.dart';
import 'mg_button.dart';

/// Speed and voice for read-aloud, with a test button. Choices are saved on the phone.
Future<void> showVoiceSettings(BuildContext context, {SpeechService? service}) {
  CacheRepository? cache;
  try {
    cache = context.read<CacheRepository>();
  } catch (_) {}
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VoiceSettingsSheet(service: service ?? SpeechService.instance, cache: cache),
  );
}

class VoiceSettingsSheet extends StatefulWidget {
  const VoiceSettingsSheet({super.key, required this.service, this.cache});
  final SpeechService service;
  final CacheRepository? cache;

  @override
  State<VoiceSettingsSheet> createState() => _VoiceSettingsSheetState();
}

class _VoiceSettingsSheetState extends State<VoiceSettingsSheet> {
  late final Future<List<SpeechVoice>> _voices = widget.service.voices();

  Future<void> _apply(SpeechPrefs p) async {
    await widget.service.configure(p);
    final cache = widget.cache;
    if (cache != null) await SpeechPrefsStore(cache).save(p);
  }

  @override
  void dispose() {
    widget.service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ValueListenableBuilder<SpeechPrefs>(
          valueListenable: widget.service.prefs,
          builder: (context, prefs, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            children: [
              Text('Voice', style: t.headlineSmall),
              const SizedBox(height: Space.lg),
              Text('Speed', style: t.titleMedium),
              const SizedBox(height: Space.sm),
              SegmentedButton<SpeechSpeed>(
                segments: [for (final s in SpeechSpeed.values) ButtonSegment(value: s, label: Text(s.label))],
                selected: {prefs.speed},
                onSelectionChanged: (v) => _apply(prefs.copyWith(speed: v.first)),
              ),
              const SizedBox(height: Space.lg),
              Text('Voice', style: t.titleMedium),
              const SizedBox(height: Space.xs),
              Text('The best English voice on this device is chosen automatically. Pick another if you prefer.', style: t.bodySmall),
              const SizedBox(height: Space.sm),
              FutureBuilder<List<SpeechVoice>>(
                future: _voices,
                builder: (context, snap) {
                  final list = snap.data ?? const <SpeechVoice>[];
                  if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator()));
                  if (list.isEmpty) return Text('This device did not list any English voices, so its default voice is used.', style: t.bodyMedium);
                  return Column(children: [
                    RadioGroup<SpeechVoice?>(
                      groupValue: prefs.voice,
                      onChanged: (v) => _apply(v == null ? prefs.copyWith(clearVoice: true) : prefs.copyWith(voice: v)),
                      child: Column(children: [
                        const RadioListTile<SpeechVoice?>(value: null, title: Text('Automatic (best available)'), contentPadding: EdgeInsets.zero),
                        for (final v in list.take(12)) RadioListTile<SpeechVoice?>(value: v, title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(v.locale), contentPadding: EdgeInsets.zero),
                      ]),
                    ),
                  ]);
                },
              ),
              const SizedBox(height: Space.lg),
              MgButton(
                label: 'Test voice',
                icon: Icons.volume_up_rounded,
                expand: true,
                onPressed: () => widget.service.speak(const ['This is how emergency instructions will sound. Stay calm and follow the route to the nearest exit.'], owner: 'voice-test'),
              ),
              const SizedBox(height: Space.sm),
              Text('Voice quality depends on the voices installed on this device.', style: t.bodySmall?.copyWith(color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
