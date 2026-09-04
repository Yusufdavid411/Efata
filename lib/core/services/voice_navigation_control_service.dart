import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class VoiceNavigationControlService {
  VoiceNavigationControlService._();

  static const Duration _nativeCallTimeout = Duration(seconds: 4);

  static Future<bool> stopActiveGuidance() async {
    final stopped = await _tryCall(GoogleMapsNavigator.stopGuidance);
    final cleared = await _tryCall(GoogleMapsNavigator.clearDestinations);
    final cleaned = await _tryCall(() => GoogleMapsNavigator.cleanup());
    return stopped || cleared || cleaned;
  }

  static Future<bool> detachListenersOnly() async {
    return _tryCall(() => GoogleMapsNavigator.cleanup(resetSession: false));
  }

  static Future<bool> stopStaleGuidanceOnFreshLaunch() {
    return stopActiveGuidance();
  }

  static Future<bool> _tryCall(Future<void> Function() action) async {
    try {
      await action().timeout(_nativeCallTimeout);
      return true;
    } catch (_) {
      // Navigation may already be stopped or the native session may be gone.
      return false;
    }
  }
}
