import 'package:flutter/material.dart';

const efataVehicleTypes = [
  'Truck',
  'Tipper',
  'Petrol Tanker',
  'Van',
  'Pickup',
  'Mixer',
];

class VehicleIllustration extends StatelessWidget {
  const VehicleIllustration(this.type, {super.key});
  final String type;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(48, 28), painter: _VehiclePainter(type));
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.type);
  final String type;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 28);
    final paint = Paint();
    void box(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double radius = 2,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        paint..color = color,
      );
    }

    const ink = Color(0xFF21343A);
    const teal = Color(0xFF08766C);
    const glass = Color(0xFFBCE8E4);
    box(3, 19, 42, 4, ink);
    box(29, type == 'Pickup' ? 13 : 9, 15, type == 'Pickup' ? 9 : 13, teal);
    box(35, type == 'Pickup' ? 14 : 11, 6, 5, glass);
    switch (type) {
      case 'Van':
        box(4, 8, 30, 13, teal);
        box(8, 10, 12, 5, glass);
      case 'Pickup':
        box(5, 16, 24, 5, teal);
      case 'Tipper':
        canvas.drawPath(
          Path()
            ..moveTo(3, 8)
            ..lineTo(29, 10)
            ..lineTo(25, 18)
            ..lineTo(7, 18)
            ..close(),
          paint..color = const Color(0xFFB76525),
        );
      case 'Petrol Tanker':
        box(3, 8, 27, 11, const Color(0xFF65848C), 6);
        box(9, 12, 15, 2, glass);
      case 'Mixer':
        canvas.save();
        canvas.translate(17, 13);
        canvas.rotate(-0.34);
        box(-12, -5, 24, 11, const Color(0xFF48749D), 5);
        box(-2, -5, 3, 11, glass, 1);
        canvas.restore();
      default:
        box(3, 5, 25, 15, const Color(0xFF48749D));
    }
    for (final x in [11.0, 37.0]) {
      canvas.drawCircle(Offset(x, 22), 4.2, paint..color = ink);
      canvas.drawCircle(Offset(x, 22), 1.6, paint..color = glass);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VehiclePainter oldDelegate) => oldDelegate.type != type;
}
