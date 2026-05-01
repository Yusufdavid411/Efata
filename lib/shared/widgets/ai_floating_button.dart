import 'package:flutter/material.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("AI assistant coming soon"),
            ),
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