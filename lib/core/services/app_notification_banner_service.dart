import 'dart:async';

import 'package:flutter/material.dart';

class AppNotificationBannerService {
  AppNotificationBannerService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  static void show({
    required String title,
    required String body,
    IconData icon = Icons.notifications_active_outlined,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hideTimer?.cancel();
    _currentEntry?.remove();

    _currentEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -20, end: 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) {
                return Transform.translate(
                  offset: Offset(0, offset),
                  child: child,
                );
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x330F172A),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF14B8A6,
                          ).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: const Color(0xFF5EEAD4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_currentEntry!);
    _hideTimer = Timer(const Duration(seconds: 4), hide);
  }

  static void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
