// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sybil_widgets.dart' show SybilBetaBadge;

class OnboardingWelcomeBackdrop extends StatelessWidget {
  const OnboardingWelcomeBackdrop({
    super.key,
    this.fit = BoxFit.fill,
    this.alignment = Alignment.center,
  });

  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/welcome_bg_dark.png'
        : 'assets/illustrations/welcome_bg_light.png';
    return Image.asset(asset, fit: fit, alignment: alignment);
  }
}

const _vizorWordmarkFrameWidth = 140.0;
const _vizorWordmarkFrameHeight = 52.83;

/// The compact Sybil mark used beside the wordmark and in small product
/// surfaces. It is drawn from the same geometric S as the launcher artwork so
/// the app does not depend on a raster logo for in-app rendering.
class SybilMark extends StatelessWidget {
  const SybilMark({this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SybilMarkPainter(color ?? context.colors.text.accent),
      size: const Size.square(24),
    );
  }
}

class _SybilMarkPainter extends CustomPainter {
  const _SybilMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale, scale);
    final path = Path()
      ..moveTo(5.1, 4)
      ..lineTo(19.2, 4)
      ..lineTo(16.9, 7)
      ..lineTo(8.2, 7)
      ..cubicTo(7.2, 7, 6.5, 7.6, 6.5, 8.4)
      ..cubicTo(6.5, 9.1, 7.1, 9.5, 8.1, 9.8)
      ..lineTo(15.9, 12)
      ..cubicTo(18.3, 12.7, 19.5, 14, 19.5, 16.1)
      ..cubicTo(19.5, 18.7, 17.3, 20, 14.5, 20)
      ..lineTo(4, 20)
      ..lineTo(6.2, 17)
      ..lineTo(14.2, 17)
      ..cubicTo(15.3, 17, 16, 16.6, 16, 15.9)
      ..cubicTo(16, 15.2, 15.4, 14.8, 14.4, 14.5)
      ..lineTo(6.3, 12.2)
      ..cubicTo(3.9, 11.5, 2.5, 10.1, 2.5, 8)
      ..cubicTo(2.5, 5.5, 4.3, 4, 5.1, 4)
      ..close();
    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
    canvas.drawCircle(const Offset(19.3, 4.1), 0.9, paint);
  }

  @override
  bool shouldRepaint(_SybilMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class VizorWordmark extends StatelessWidget {
  /// Retains the upstream layout API while matching the Sybil sidebar wordmark.
  const VizorWordmark({
    super.key,
    this.width = _vizorWordmarkFrameWidth,
    this.height = _vizorWordmarkFrameHeight,
    this.color,
  });

  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        label: 'Sybil Beta',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: SybilMark(color: color ?? colors.text.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'sybil.',
                style: TextStyle(
                  fontFamily: 'Young Serif',
                  fontSize: 40,
                  letterSpacing: -2,
                  color: color ?? colors.text.accent,
                ),
              ),
              const SizedBox(width: 10),
              const SybilBetaBadge(),
            ],
          ),
        ),
      ),
    );
  }
}
