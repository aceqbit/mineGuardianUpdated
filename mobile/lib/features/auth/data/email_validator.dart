/// Email address check shared by login and sign-up. Returns an error message, or null when the address is fine.
/// The address is the login identity, so it is trimmed and lower-cased before it is used anywhere ([normalizeEmail]).
String? validateEmail(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Enter your email address';
  if (v.length > 120) return 'Email address is too long';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v) ? null : 'Enter a valid email address';
}

String normalizeEmail(String raw) => raw.trim().toLowerCase();
