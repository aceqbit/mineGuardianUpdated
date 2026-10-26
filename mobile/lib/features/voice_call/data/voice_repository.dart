import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';

class PlacedCall {
  const PlacedCall({required this.callId, required this.status, required this.mode, required this.dryRun, required this.targetLabel, required this.statusUpdates});
  final String callId;
  final VoiceCallStatus status;
  final String mode;
  final bool dryRun;
  final String targetLabel;

  /// False when PUBLIC_BASE_URL is not public https: Twilio cannot report ringing / answered / ended back.
  final bool statusUpdates;
}

/// POST /api/voice/call and /hangup (CLAUDE.md section 23.5).
class VoiceRepository {
  VoiceRepository({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<PlacedCall> call({required String targetType, required String targetId, String? reason}) async {
    final j = await _api.postJson('/api/voice/call', body: {'targetType': targetType, 'targetId': targetId, if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
    return PlacedCall(
      callId: '${j['callId']}',
      status: VoiceCallStatus.fromWire('${j['status']}'),
      mode: j['mode'] as String? ?? 'say',
      dryRun: j['dryRun'] == true,
      targetLabel: j['targetLabel'] as String? ?? '',
      statusUpdates: j['statusUpdates'] == true,
    );
  }

  Future<VoiceCallStatus> hangup(String callId) async => VoiceCallStatus.fromWire('${(await _api.postJson('/api/voice/call/$callId/hangup'))['status']}');
}

/// What the person sees when the server refuses a call.
String voiceErrorText(ApiException e) => switch (e.code) {
      'UNSAFE_DIAL_TARGET' => 'That number is a real emergency service and cannot be called by the app.',
      'NO_PHONE' => e.message,
      'CALL_COOLDOWN' => 'You just called. Try again in ${(e.details is Map ? (e.details as Map)['retryAfterSec'] : null) ?? 30} s.',
      'NOT_ALLOWLISTED' => 'Live calls only reach verified team numbers (TWILIO_CALL_ALLOWLIST). No call was placed.',
      'FORBIDDEN_SCOPE' => 'You cannot call this person from your role.',
      'CALL_FAILED' => 'The phone service could not place the call.',
      'NETWORK' => 'No connection. Use the phone dialler instead.',
      _ => e.message,
    };
