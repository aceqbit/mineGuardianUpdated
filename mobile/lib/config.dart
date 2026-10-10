/// Build-time configuration. Override with --dart-define=API_BASE_URL=http://HOST:4000
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000');

/// Socket.io shares the API origin.
const String socketUrl = apiBaseUrl;

/// Every login and sign-up must be confirmed with an SMS code sent to the phone number.
/// Only turn this off for development while the Firebase Phone provider is not enabled yet:
/// --dart-define=OTP_REQUIRED=false
const bool otpRequired = bool.fromEnvironment('OTP_REQUIRED', defaultValue: true);

/// Shows the "Simulate walk" control in the evacuation view of release builds too (always available in debug builds):
/// --dart-define=NAV_SIMULATE=true
const bool navSimulate = bool.fromEnvironment('NAV_SIMULATE', defaultValue: false);

/// How verification codes are delivered. `firebase` (default) sends a real SMS through Firebase phone auth.
/// `demo` is for presentations when SMS is not available: a random code is generated on the device and shown on screen
/// in a clearly labelled DEMO banner. No SMS is sent and it is not a security control.
/// --dart-define=OTP_MODE=demo
const String otpMode = String.fromEnvironment('OTP_MODE', defaultValue: 'firebase');
