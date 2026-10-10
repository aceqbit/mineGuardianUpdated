import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/models/session_user.dart';

class ZoneOption {
  const ZoneOption({required this.id, required this.code, required this.name, required this.mineName});
  final String id;
  final String code;
  final String name;
  final String mineName;

  factory ZoneOption.fromJson(Map<String, dynamic> j) => ZoneOption(
        id: (j['id'] ?? j['_id']).toString(),
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
        mineName: j['mineName'] as String? ?? '',
      );
}

class SignupData {
  const SignupData({
    required this.role,
    required this.fullName,
    required this.employeeId,
    required this.isoCode,
    required this.dialCode,
    required this.national,
    required this.e164,
    required this.password,
    required this.mineName,
    required this.zoneId,
    required this.shift,
    required this.designation,
    required this.experienceYears,
    required this.dateOfJoining,
    required this.dob,
    required this.bloodGroup,
    required this.emergencyName,
    required this.emergencyRelation,
    required this.emergencyIso,
    required this.emergencyDial,
    required this.emergencyNational,
    this.address,
  });
  final String role;
  final String fullName;
  final String employeeId;
  final String isoCode;
  final String dialCode;
  final String national;
  final String e164;
  final String password;
  final String mineName;
  final String zoneId;
  final String shift;
  final String designation;
  final int experienceYears;
  final DateTime dateOfJoining;
  final DateTime dob;
  final String bloodGroup;
  final String emergencyName;
  final String emergencyRelation;
  final String emergencyIso;
  final String emergencyDial;
  final String emergencyNational;
  final String? address;

  Map<String, dynamic> toBody() => {
        'role': role,
        'fullName': fullName.trim(),
        'employeeId': employeeId.trim(),
        'phone': {'isoCode': isoCode, 'dialCode': dialCode, 'national': national},
        'designation': designation,
        'experienceYears': experienceYears,
        'dateOfJoining': _d(dateOfJoining),
        'dob': _d(dob),
        'bloodGroup': bloodGroup,
        'mineName': mineName,
        'zoneId': zoneId,
        'shift': shift,
        'emergencyContact': {
          'name': emergencyName.trim(),
          'relation': emergencyRelation,
          'phone': {'isoCode': emergencyIso, 'dialCode': emergencyDial, 'national': emergencyNational},
        },
        if (address != null && address!.trim().isNotEmpty) 'address': address!.trim(),
      };

  static String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Failure carrying which step shows the error (0 account, 1 work, 2 personal).
class SignupFailure implements Exception {
  SignupFailure(this.message, {this.step = 2, this.alreadyRegistered = false});
  final String message;
  final int step;
  final bool alreadyRegistered;
}

class SignupRepository {
  SignupRepository({required AuthRepository auth, required ApiClient api}) : _auth = auth, _api = api;
  final AuthRepository _auth;
  final ApiClient _api;

  Future<List<ZoneOption>> zones() async {
    final list = await _api.getList('/api/zones');
    return list.map((e) => ZoneOption.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Firebase account first, then the profile POST. Any failure after step 1 deletes the Firebase user.
  Future<SessionUser> register(SignupData d, {void Function(String stage)? onStage}) async {
    await createAccount(d);
    onStage?.call('Saving profile…');
    return completeRegistration(d);
  }

  /// Step 1 of sign-up: the Firebase identity.
  Future<void> createAccount(SignupData d) async {
    try {
      await _auth.createAccount(d.e164, d.password);
    } on AuthFailure catch (f) {
      throw SignupFailure(f.message, step: 0, alreadyRegistered: f.code == 'ALREADY_REGISTERED');
    }
  }

  /// Rollback used when the phone is not verified: no orphan Firebase users.
  Future<void> discardAccount() => _auth.deleteCurrentFirebaseUser();

  /// Step 2 of sign-up: the profile POST. Any failure deletes the Firebase user created in [createAccount].
  Future<SessionUser> completeRegistration(SignupData d) async {
    try {
      await _api.postJson('/api/auth/signup', body: d.toBody());
      final me = await _api.getJson('/api/auth/me');
      return SessionUser.fromMe(me);
    } on ApiException catch (e) {
      await _auth.deleteCurrentFirebaseUser();
      throw SignupFailure(e.message, step: _stepFor(e));
    } catch (_) {
      await _auth.deleteCurrentFirebaseUser();
      throw SignupFailure('Could not save your profile. Please try again');
    }
  }

  int _stepFor(ApiException e) {
    String path = '';
    final det = e.details;
    if (det is Map && det['path'] is String) {
      path = det['path'] as String;
    } else if (det is Map && det['field'] is String) {
      path = det['field'] as String;
    } else if (det is List && det.isNotEmpty && det.first is Map) {
      path = ((det.first as Map)['path'] ?? '').toString();
    }
    if (path.startsWith('emergencyContact') || path == 'dob' || path == 'bloodGroup' || path == 'address') return 2;
    if (path.startsWith('zoneId') || path == 'mineName' || path == 'shift' || path == 'designation' || path == 'experienceYears' || path == 'dateOfJoining') return 1;
    if (path.startsWith('phone') || path == 'employeeId' || path == 'fullName' || path == 'role') return 0;
    if (e.code == 'PHONE_TOKEN_MISMATCH' || e.code == 'INVALID_PHONE' || e.code == 'DUPLICATE') return 0;
    return 2;
  }
}
