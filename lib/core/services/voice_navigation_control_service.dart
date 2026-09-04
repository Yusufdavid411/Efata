import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class VoiceNavigationControlService {
  VoiceNavigationControlService._();

  static Future<void> stopActiveGuidance() async {
    await _tryCall(GoogleMapsNavigator.stopGuidance);
    await _tryCall(GoogleMapsNavigator.clearDestinations);
    await _tryCall(() => GoogleMapsNavigator.cleanup());
  }

  static Future<void> detachListenersOnly() async {
    await _tryCall(() => GoogleMapsNavigator.cleanup(resetSession: false));
  }

  static Future<void> stopStaleGuidanceOnFreshLaunch() {
    return stopActiveGuidance();
  }

  static Future<void> _tryCall(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Navigation may already be stopped or the native session may be gone.
    }
  }
}
