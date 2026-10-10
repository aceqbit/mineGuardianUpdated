/// Build-time configuration. Override with --dart-define=API_BASE_URL=http://HOST:4000
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000');

/// Socket.io shares the API origin.
const String socketUrl = apiBaseUrl;

/// Offer "Enable OTP login" after a password login. Turn off with --dart-define=OTP_LINK_PROMPT=false
/// (e.g. while the Firebase Phone provider is not enabled yet).
const bool otpLinkPrompt = bool.fromEnvironment('OTP_LINK_PROMPT', defaultValue: true);
