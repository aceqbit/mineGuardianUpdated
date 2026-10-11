/// Build-time configuration. Override with --dart-define=API_BASE_URL=http://HOST:4000
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000');

/// Socket.io shares the API origin.
const String socketUrl = apiBaseUrl;

/// Every login and sign-up must be confirmed with an SMS code sent to the phone number.
/// Only turn this off for development while the Firebase Phone provider is not enabled yet:
/// --dart-define=OTP_REQUIRED=false
const bool otpRequired = bool.fromEnvironment('OTP_REQUIRED', defaultValue: true);

/// Google Maps Platform key with the Map Tiles API enabled (the evacuation map's base layer). Restrict it by app/referrer in
/// Google Cloud and pass it at build time, never commit it: --dart-define=GOOGLE_MAPS_API_KEY=...
/// Without a key the map still draws the mine layout, routes and your position on a plain background.
const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Shows the "Simulate walk" control in the evacuation view of release builds too (always available in debug builds):
/// --dart-define=NAV_SIMULATE=true
const bool navSimulate = bool.fromEnvironment('NAV_SIMULATE', defaultValue: false);

