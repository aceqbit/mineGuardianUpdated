import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Last-resort safety net so a bug in one widget or plugin never shows a red crash screen or kills the app.
/// - Flutter framework errors are logged and the broken widget is replaced by a small, readable card.
/// - Uncaught async errors (plugins, timers, streams) are logged and swallowed.
/// Logs never include tokens or user data: only the exception text and, in debug builds, the stack.
class ErrorGuard {
  ErrorGuard._();

  static final List<String> recent = <String>[];

  static void _log(Object error, StackTrace? stack, {required String source}) {
    final line = '[$source] ${error.toString().split('\n').first}';
    recent.add(line);
    if (recent.length > 50) recent.removeAt(0);
    debugPrint(line);
    if (kDebugMode && stack != null) debugPrint(stack.toString());
  }

  /// Call once, before runApp.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _log(details.exception, details.stack, source: 'flutter');
      if (kDebugMode) previous?.call(details); // keep the full report while developing
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _log(error, stack, source: 'platform');
      return true; // handled: do not crash
    };
    ErrorWidget.builder = (details) => FriendlyError(message: kDebugMode ? details.exceptionAsString() : null);
  }

  /// Runs [body] so errors thrown in any async code are caught here instead of crashing.
  static void run(void Function() body) {
    runZonedGuarded(body, (error, stack) => _log(error, stack, source: 'zone'));
  }
}

/// Replaces a widget that failed to build. Small enough to sit inside any layout.
class FriendlyError extends StatelessWidget {
  const FriendlyError({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    // Built outside normal theming when the tree is broken, so it uses plain colours that pass contrast.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC81E1E))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Color(0xFFC81E1E)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message == null ? 'Something went wrong in this section. Go back and try again.' : 'Build error: $message',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 13, decoration: TextDecoration.none, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      ),
    );
  }
}
