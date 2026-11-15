import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Ikon vektor logo Google empat warna tanpa bergantung pada asset eksternal.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(s / 2, s / 2);
    final stroke = s * 0.205;
    final radius = (s - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Merah (atas)
    canvas.drawArc(
      rect,
      _deg(212),
      _deg(104),
      false,
      arcPaint(const Color(0xFFEA4335)),
    );
    // Kuning (kiri bawah)
    canvas.drawArc(
      rect,
      _deg(145),
      _deg(70),
      false,
      arcPaint(const Color(0xFFFBBC05)),
    );
    // Hijau (bawah)
    canvas.drawArc(
      rect,
      _deg(42),
      _deg(106),
      false,
      arcPaint(const Color(0xFF34A853)),
    );
    // Biru (kanan)
    canvas.drawArc(
      rect,
      _deg(-5),
      _deg(50),
      false,
      arcPaint(const Color(0xFF4285F4)),
    );

    // Palang horizontal huruf G
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        center.dx - stroke * 0.1,
        center.dy - stroke * 0.48,
        s * 0.45,
        stroke * 0.96,
      ),
      Radius.circular(stroke * 0.12),
    );
    canvas.drawRRect(barRect, barPaint);
  }

  double _deg(double d) => d * math.pi / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
