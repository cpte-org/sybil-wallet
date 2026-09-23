// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sybil_widgets.dart';

/// The same quiet wordmark used by the wallet, without exposing account data.
class SybilUnlockBrand extends StatelessWidget {
  const SybilUnlockBrand({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) => Text(
    'sybil.',
    semanticsLabel: 'Sybil',
    style: AppTypography.displayLarge.copyWith(
      fontFamily: 'Young Serif',
      fontSize: large ? 80 : 40,
      height: 1.2,
      letterSpacing: -2,
      color: SybilPalette.of(context).ink,
    ),
  );
}

class OnboardingAuthShell extends StatelessWidget {
  const OnboardingAuthShell({super.key, required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    return ColoredBox(
      color: palette.paper,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: wide
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SybilUnlockBrand(large: true),
                                  const SizedBox(height: 32),
                                  Text(
                                    'Your people.\nYour wallet.',
                                    style: AppTypography.displayMedium.copyWith(
                                      color: palette.ink,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const SybilBetaBadge(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 48),
                            Flexible(child: card),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SybilUnlockBrand(),
                            const SizedBox(height: 28),
                            card,
                            const SizedBox(height: 24),
                            const SybilBetaBadge(),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OnboardingAuthCard extends StatelessWidget {
  const OnboardingAuthCard({
    super.key,
    required this.width,
    required this.height,
    required this.padding,
    required this.child,
  });

  final double width;
  final double height;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: BoxConstraints(minHeight: height),
    child: SybilCard(padding: padding, child: child),
  );
}
