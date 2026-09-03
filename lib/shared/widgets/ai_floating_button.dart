import 'package:flutter/material.dart';
import 'package:logistics_app/core/services/app_notification_banner_service.dart';

class AIFloatingButton extends StatefulWidget {
  const AIFloatingButton({super.key});

  @override
  State<AIFloatingButton> createState() => _AIFloatingButtonState();
}

class _AIFloatingButtonState extends State<AIFloatingButton> {
  Offset position = const Offset(300, 520);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
          });
        },
        onTap: () {
          AppNotificationBannerService.info(
            'AI assistant coming soon.',
            title: 'Coming soon',
            icon: Icons.auto_awesome_rounded,
          );
        },
        child: Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: Colors.deepPurple,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text(
              "AI",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
