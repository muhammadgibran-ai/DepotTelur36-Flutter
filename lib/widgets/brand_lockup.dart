import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';

/// Identitas visual utama DepotTelur36 (`BrandLockup`): lencana telur solid `#FBB017`,
/// wordmark `depot telur36`, dan subjudul `TOKO TELUR & SEMBAKO`.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.badgeSize = 68,
    this.useHero = true,
  });

  final double badgeSize;
  final bool useHero;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      container: true,
      header: true,
      label: 'DepotTelur36, Toko Telur dan Sembako',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.yolk,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.ink,
                  width: 3,
                ),
              ),
              child: Center(
                child: CustomPaint(
                  size: Size.square(badgeSize * 0.5),
                  painter: const _SolidEggPainter(color: AppColors.ink),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Wordmark merek dikecualikan dari pemeriksaan kontras logotype
            // karena label semantik lengkap sudah disediakan di Semantics induk.
            ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'depot',
                    style: AppTypography.heading(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.yolk,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'telur36',
                    style: AppTypography.heading(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                'TOKO TELUR & SEMBAKO',
                style: AppTypography.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!useHero) return content;
    return Hero(
      tag: 'depot_telur_brand_lockup',
      child: Material(
        type: MaterialType.transparency,
        child: content,
      ),
    );
  }
}

class _SolidEggPainter extends CustomPainter {
  const _SolidEggPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.50, h * 0.08)
      ..cubicTo(w * 0.72, h * 0.08, w * 0.87, h * 0.44, w * 0.87, h * 0.64)
      ..cubicTo(w * 0.87, h * 0.84, w * 0.71, h * 0.94, w * 0.50, h * 0.94)
      ..cubicTo(w * 0.29, h * 0.94, w * 0.13, h * 0.84, w * 0.13, h * 0.64)
      ..cubicTo(w * 0.13, h * 0.44, w * 0.28, h * 0.08, w * 0.50, h * 0.08)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SolidEggPainter oldDelegate) =>
      oldDelegate.color != color;
}
