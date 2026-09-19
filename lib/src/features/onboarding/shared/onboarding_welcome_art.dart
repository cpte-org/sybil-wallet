// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

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

class VizorWordmark extends StatelessWidget {
  /// Retains the upstream layout API while matching the Sigil sidebar wordmark.
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
        label: 'Sigil',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            'sigil.',
            style: TextStyle(
              fontFamily: 'Young Serif',
              fontSize: 40,
              letterSpacing: -2,
              color: color ?? colors.text.accent,
            ),
          ),
        ),
      ),
    );
  }
}
