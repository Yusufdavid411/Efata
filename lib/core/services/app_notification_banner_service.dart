import 'dart:async';

import 'package:flutter/material.dart';

enum AppToastType { success, error, info }

class AppNotificationBannerService {
  AppNotificationBannerService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  static void show({
    required String title,
    required String body,
    IconData icon = Icons.notifications_active_outlined,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hideTimer?.cancel();
    _currentEntry?.remove();

    _currentEntry = OverlayEntry(
      builder: (context) {
        final style = _ToastStyle.forType(type);
        return Positioned.fill(
          child: IgnorePointer(
            child: SafeArea(
              minimum: const EdgeInsets.all(18),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 160),
                      child: child,
                    ),
                  );
                },
                child: Align(
                  alignment: Alignment.center,
                  child: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: style.background,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: style.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x400F172A),
                              blurRadius: 26,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: style.iconBackground,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(icon, color: style.iconColor),
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
                                    style: TextStyle(
                                      color: style.titleColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (body.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      body,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: style.bodyColor,
                                        height: 1.3,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_currentEntry!);
    _hideTimer = Timer(duration, hide);
  }

  static void success(String message, {String title = 'Success'}) {
    show(
      title: title,
      body: message,
      icon: Icons.check_circle_rounded,
      type: AppToastType.success,
    );
  }

  static void error(String message, {String title = 'Something went wrong'}) {
    show(
      title: title,
      body: message,
      icon: Icons.error_rounded,
      type: AppToastType.error,
      duration: const Duration(seconds: 4),
    );
  }

  static void info(
    String message, {
    String title = 'EFATA',
    IconData icon = Icons.notifications_active_outlined,
  }) {
    show(title: title, body: message, icon: icon);
  }

  static void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _ToastStyle {
  const _ToastStyle({
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.iconColor,
    required this.titleColor,
    required this.bodyColor,
  });

  final Color background;
  final Color border;
  final Color iconBackground;
  final Color iconColor;
  final Color titleColor;
  final Color bodyColor;

  static _ToastStyle forType(AppToastType type) {
    switch (type) {
      case AppToastType.success:
        return const _ToastStyle(
          background: Color(0xFFF0FDF4),
          border: Color(0xFF86EFAC),
          iconBackground: Color(0xFFDCFCE7),
          iconColor: Color(0xFF16A34A),
          titleColor: Color(0xFF14532D),
          bodyColor: Color(0xFF166534),
        );
      case AppToastType.error:
        return const _ToastStyle(
          background: Color(0xFFFEF2F2),
          border: Color(0xFFFCA5A5),
          iconBackground: Color(0xFFFEE2E2),
          iconColor: Color(0xFFDC2626),
          titleColor: Color(0xFF7F1D1D),
          bodyColor: Color(0xFF991B1B),
        );
      case AppToastType.info:
        return const _ToastStyle(
          background: Color(0xFFF0FDFA),
          border: Color(0xFF99F6E4),
          iconBackground: Color(0xFFCCFBF1),
          iconColor: Color(0xFF0F766E),
          titleColor: Color(0xFF134E4A),
          bodyColor: Color(0xFF0F766E),
        );
    }
  }
}
