// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_icon_size.dart';
import 'package:zcash_wallet/src/core/theme/app_radii.dart';
import 'package:zcash_wallet/src/core/theme/app_sizing.dart';
import 'package:zcash_wallet/src/core/theme/app_spacing.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_data.dart';
import 'package:zcash_wallet/src/core/theme/app_typography.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';

void main() {
  test('token selectors resolve to the compiled form factor set', () {
    // `flutter test` runs with the default define (desktop) unless a
    // --dart-define=VIZOR_FORM_FACTOR=mobile lane overrides it; this test
    // is form-factor agnostic so it passes in both lanes.
    final mobile = kAppFormFactor == AppFormFactor.mobile;

    expect(
      AppTypography.bodyMedium,
      mobile ? AppTypographyMobile.bodyMedium : AppTypographyDesktop.bodyMedium,
    );
    expect(
      AppTypography.displayLarge,
      mobile
          ? AppTypographyMobile.displayLarge
          : AppTypographyDesktop.displayLarge,
    );
    expect(
      AppTypography.headlineMedium,
      mobile
          ? AppTypographyMobile.headlineMedium
          : AppTypographyDesktop.headlineMedium,
    );
    expect(
      AppTypography.codeMedium,
      mobile ? AppTypographyMobile.codeMedium : AppTypographyDesktop.codeMedium,
    );
    expect(
      AppButtonSizing.largeHeight,
      mobile
          ? AppButtonSizingMobile.largeHeight
          : AppButtonSizingDesktop.largeHeight,
    );
    expect(
      AppInputSizing.height,
      mobile ? AppInputSizingMobile.height : AppInputSizingDesktop.height,
    );
    expect(
      AppAssetSize.size,
      mobile ? AppAssetSizeMobile.size : AppAssetSizeDesktop.size,
    );
    expect(
      AppButtonSizing.mediumSmallIconSize,
      mobile
          ? AppButtonSizingMobile.mediumSmallIconSize
          : AppButtonSizingDesktop.mediumSmallIconSize,
    );
  });

  test('desktop sizing tokens match 1 Sizing-3.zip', () {
    expect(AppSpacing.xxs, 4);
    expect(AppSpacing.xs, 8);
    expect(AppSpacing.s, 12);
    expect(AppSpacing.sm, 16);
    expect(AppSpacing.md, 24);
    expect(AppSpacing.base, 32);
    expect(AppSpacing.lg, 48);
    expect(AppSpacing.xl, 64);
    expect(AppSpacing.xl2, 96);
    expect(AppSpacing.xl3, 128);

    expect(AppRadii.xSmall, 8);
    expect(AppRadii.small, 12);
    expect(AppRadii.medium, 16);
    expect(AppRadii.large, 24);
    expect(AppRadii.xLarge, 32);
    expect(AppRadii.full, 999);

    expect(AppAssetSizeDesktop.size, 32);
    expect(AppAssetSizeDesktop.icon, 16);
    expect(AppAssetSizeDesktop.padding, 4);
    expect(AppIconSize.medium, AppAssetSizeDesktop.icon);

    expect(AppButtonSizingDesktop.largeHeight, 44);
    expect(AppButtonSizingDesktop.mediumSmallIconSize, 16);

    expect(AppInputSizingDesktop.height, 46);
    expect(AppInputSizingDesktop.iconWrapWidth, 32);
    expect(AppInputSizingDesktop.iconSize, 20);
    expect(AppInputSizingDesktop.radius, AppRadii.small);

    expect(AppWindowSizing.minWidth, 1080);
    expect(AppWindowSizing.minHeight, 720);
    expect(AppWindowSizing.maxWidth, 1296);
    expect(AppWindowSizing.maxHeight, 864);
    expect(AppWindowSizing.contentAreaMaxWidth, 420);
    expect(AppWindowSizing.paneRadius, 20);
  });

  test('mobile sizing tokens match 1 Sizing-3.zip', () {
    expect(AppAssetSizeMobile.size, 40);
    expect(AppAssetSizeMobile.icon, 18);
    expect(AppAssetSizeMobile.padding, 0);

    expect(AppButtonSizingMobile.largeHeight, 50);
    expect(AppButtonSizingMobile.mediumSmallIconSize, 20);

    expect(AppInputSizingMobile.height, 60);
    expect(AppInputSizingMobile.iconWrapWidth, 36);
    expect(AppInputSizingMobile.iconSize, 24);
    // Figma `Input/Radii` aliases `Radii.SM` (16) on mobile; the Figma
    // radii scale is shifted one tier against Dart's, so `SM` = `medium`.
    expect(AppInputSizingMobile.radius, AppRadii.medium);
  });

  test('desktop font tokens preserve redesign serif typography', () {
    const caseFigures = [FontFeature.enable('case')];

    expect(AppTypographyDesktop.displayMedium.fontFamily, 'Young Serif');
    expect(AppTypographyDesktop.displayMedium.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.displayMedium.fontFeatures, caseFigures);
    expect(AppTypographyDesktop.displayMedium.fontSize, 45);
    expect(AppTypographyDesktop.displayMedium.height, 48 / 45);
    expect(AppTypographyDesktop.displayMedium.letterSpacing, -1.35);

    expect(AppTypographyDesktop.headlineLarge.fontFamily, 'Young Serif');
    expect(AppTypographyDesktop.headlineLarge.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.headlineLarge.fontFeatures, caseFigures);
    expect(AppTypographyDesktop.headlineLarge.fontSize, 32);
    expect(AppTypographyDesktop.headlineLarge.height, 33 / 32);

    expect(AppTypographyDesktop.headlineMedium.fontFamily, 'Young Serif');
    expect(AppTypographyDesktop.headlineMedium.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.headlineMedium.fontFeatures, caseFigures);
    expect(AppTypographyDesktop.headlineMedium.fontSize, 28);
    expect(AppTypographyDesktop.headlineMedium.height, 30 / 28);
    expect(AppTypographyDesktop.headlineMedium.letterSpacing, -0.28);

    expect(AppTypographyDesktop.headlineSmall.fontSize, 16);
    expect(AppTypographyDesktop.headlineSmall.height, 20 / 16);

    expect(AppTypographyDesktop.bodyLarge.fontSize, 16);
    expect(AppTypographyDesktop.bodyLarge.height, 24 / 16);
    expect(AppTypographyDesktop.bodyMedium.fontSize, 14);
    expect(AppTypographyDesktop.bodyMedium.height, 21 / 14);
    expect(AppTypographyDesktop.bodyMediumStrong.fontSize, 14);
    expect(AppTypographyDesktop.bodyMediumStrong.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.bodySmall.fontSize, 12);
    expect(AppTypographyDesktop.bodySmall.height, 18 / 12);
    expect(AppTypographyDesktop.bodyExtraSmall.fontSize, 11);
    expect(AppTypographyDesktop.bodyExtraSmall.height, 16 / 11);

    expect(AppTypographyDesktop.labelLarge.fontSize, 14);
    expect(AppTypographyDesktop.labelLarge.height, 16 / 14);

    expect(AppTypographyDesktop.labelMedium.fontFamily, 'Geist');
    expect(AppTypographyDesktop.labelMedium.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.labelMedium.fontSize, 13);
    expect(AppTypographyDesktop.labelMedium.height, 14 / 13);
    expect(AppTypographyDesktop.labelMedium.letterSpacing, 0);

    expect(AppTypographyDesktop.labelSmall.fontFamily, 'Geist');
    expect(AppTypographyDesktop.labelSmall.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.labelSmall.fontSize, 13);
    expect(AppTypographyDesktop.labelSmall.height, 14 / 13);

    expect(AppTypographyDesktop.codeSmall.fontFamily, 'Geist Mono');
    expect(AppTypographyDesktop.codeSmall.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.codeSmall.fontSize, 13);
    expect(AppTypographyDesktop.codeSmall.height, 17 / 13);
  });

  test('mobile font tokens match 3 Fonts-3.zip and app screen overrides', () {
    // The current variable export updates mobile body/label/code metrics,
    // but actual mobile app frames still render display headlines with
    // Young Serif. Keep that intentional app-level screen behavior pinned.
    expect(AppTypographyMobile.displayLarge.fontFamily, 'Young Serif');
    expect(AppTypographyMobile.displayLarge.fontWeight, FontWeight.w400);
    expect(AppTypographyMobile.displayLarge.fontSize, 40);
    expect(AppTypographyMobile.displayLarge.height, 40 / 40);
    expect(AppTypographyMobile.displayLarge.letterSpacing, -1.35);
    const lining = [FontFeature.liningFigures()];
    expect(AppTypographyMobile.displayLarge.fontFeatures, lining);
    expect(AppTypographyMobile.headlineLarge.fontFeatures, lining);
    expect(AppTypographyMobile.headlineMedium.fontFeatures, lining);

    expect(AppTypographyMobile.headlineLarge.fontFamily, 'Young Serif');
    expect(
      AppTypographyMobile.headlineLarge.fontSize,
      AppTypographyDesktop.headlineLarge.fontSize,
    );
    expect(
      AppTypographyMobile.headlineLarge.height,
      AppTypographyDesktop.headlineLarge.height,
    );
    expect(AppTypographyMobile.headlineMedium.fontFamily, 'Young Serif');
    expect(
      AppTypographyMobile.headlineMedium.fontSize,
      AppTypographyDesktop.headlineMedium.fontSize,
    );
    expect(
      AppTypographyMobile.headlineMedium.height,
      AppTypographyDesktop.headlineMedium.height,
    );
    expect(AppTypographyMobile.headlineMedium.letterSpacing, -0.28);

    // Code S is mode-invariant; Code M scales up on mobile.
    expect(AppTypographyMobile.codeMedium.fontSize, 16);
    expect(AppTypographyMobile.codeMedium.height, 21 / 16);
    expect(AppTypographyMobile.codeSmall, AppTypographyDesktop.codeSmall);

    expect(AppTypographyMobile.headlineSmall.fontSize, 18);
    expect(AppTypographyMobile.headlineSmall.height, 22 / 18);

    expect(AppTypographyMobile.bodyLarge.fontSize, 18);
    expect(AppTypographyMobile.bodyLarge.height, 26 / 18);
    expect(AppTypographyMobile.bodyLarge.letterSpacing, -0.24);
    expect(AppTypographyMobile.bodyMedium.fontSize, 16);
    expect(AppTypographyMobile.bodyMedium.height, 25 / 16);
    expect(AppTypographyMobile.bodyMedium.letterSpacing, -0.21);
    expect(AppTypographyMobile.bodyMediumStrong.fontSize, 16);
    expect(AppTypographyMobile.bodyMediumStrong.height, 25 / 16);
    expect(AppTypographyMobile.bodyMediumStrong.fontWeight, FontWeight.w500);
    expect(AppTypographyMobile.bodySmall.fontSize, 14);
    expect(AppTypographyMobile.bodySmall.height, 20 / 14);
    expect(AppTypographyMobile.bodyExtraSmall.fontSize, 13);
    expect(AppTypographyMobile.bodyExtraSmall.height, 18 / 13);

    expect(AppTypographyMobile.labelLarge.fontSize, 16);
    expect(AppTypographyMobile.labelLarge.height, 17 / 16);
    expect(AppTypographyMobile.labelLarge.letterSpacing, -0.06);
    expect(AppTypographyMobile.labelMedium.fontSize, 14);
    expect(AppTypographyMobile.labelMedium.height, 15 / 14);
    expect(AppTypographyMobile.labelSmall, AppTypographyMobile.labelMedium);
  });

  test('semantic colours match the approved Sybil palette', () {
    final light = AppThemeData.light.colors;
    final dark = AppThemeData.dark.colors;

    expect(light.background.window, const Color(0xFFF7F6EF));
    expect(light.background.ground, const Color(0xFFF7F6EF));
    expect(light.background.base, const Color(0xFFFFFEF9));
    expect(light.background.raised, const Color(0xFFFFFEF9));
    expect(light.background.overlay, const Color(0xFFEEEEE4));
    expect(dark.background.window, const Color(0xFF19261F));
    expect(dark.background.ground, const Color(0xFF19261F));
    expect(dark.background.base, const Color(0xFF22352A));
    expect(dark.background.raised, const Color(0xFF22352A));
    expect(dark.background.overlay, const Color(0xFF2C3D31));
    expect(light.background.neutralScrim, const Color(0x80122119));
    expect(dark.background.neutralScrim, const Color(0x80122119));

    expect(light.surface.card, const Color(0xFFFFFEF9));
    expect(dark.surface.card, const Color(0xFF22352A));
    expect(light.surface.input.primary, const Color(0xFFFFFEF9));
    expect(light.surface.input.secondary, const Color(0xFFEEEEE4));
    expect(light.surface.input.focus, const Color(0xFFF7F6EF));
    expect(dark.surface.input.primary, const Color(0xFF22352A));
    expect(dark.surface.input.secondary, const Color(0xFF2C3D31));
    expect(dark.surface.input.focus, const Color(0xFF19261F));
    // Device-scanned QR codes keep a pure white backing in both themes.
    expect(light.surface.qrCode, const Color(0xFFFFFFFF));
    expect(dark.surface.qrCode, const Color(0xFFFFFFFF));

    expect(light.text.accent, const Color(0xFF243B30));
    expect(light.text.primary, const Color(0xFF35483D));
    expect(light.text.secondary, const Color(0xFF627065));
    expect(dark.text.accent, const Color(0xFFEDF1DE));
    expect(dark.text.primary, const Color(0xFFE0E8D9));
    expect(dark.text.secondary, const Color(0xFFB0C1B1));
    expect(light.border.subtle, const Color(0xFFD9DFD3));
    expect(dark.border.subtle, const Color(0xFF415345));

    expect(light.button.primary.bg, const Color(0xFF294A35));
    expect(light.button.primary.label, const Color(0xFFFFFEF9));
    expect(dark.button.primary.bg, const Color(0xFFDDEAAA));
    expect(dark.button.primary.label, const Color(0xFF233A2E));
    expect(light.button.secondary.bg, const Color(0xFFFFFEF9));
    expect(light.button.secondary.bgHover, const Color(0xFFEEEEE4));
    expect(light.button.secondary.bgPressed, const Color(0xFFDCE8D9));
    expect(dark.button.secondary.bg, const Color(0xFF22352A));
    expect(dark.button.secondary.bgHover, const Color(0xFF2C3D31));
    expect(dark.button.secondary.bgPressed, const Color(0xFF304B38));
    expect(light.button.disabled.bg, const Color(0xFFEEEEE4));
    expect(dark.button.disabled.bg, const Color(0xFF2C3D31));

    expect(light.text.warning, const Color(0xFF8A4A13));
    expect(dark.text.warning, const Color(0xFFF0BF7F));
    expect(light.text.destructive, const Color(0xFFAC352C));
    expect(dark.text.destructive, const Color(0xFFF8AAA0));
    expect(light.button.destructive.bg, const Color(0xFFAC352C));
    expect(dark.button.destructive.bg, const Color(0xFFF8AAA0));
    expect(light.background.utilityDestructiveSubtle, const Color(0xFFFFF0ED));
    expect(dark.background.utilityDestructiveSubtle, const Color(0xFF4B302A));
    expect(light.icon.success, const Color(0xFF294A35));
    expect(dark.icon.success, const Color(0xFFDDEAAA));
    expect(light.text.brandCrimson, const Color(0xFF294A35));
    expect(dark.icon.brandCrimson, const Color(0xFFDDEAAA));

    expect(light.state.selected, const Color(0xFFE0EBAF));
    expect(dark.state.selected, const Color(0xFF3C4B29));
    expect(light.state.focusRing, const Color(0xFF294A35));
    expect(dark.state.focusRing, const Color(0xFFDDEAAA));
    expect(light.state.focusRingDestructive, const Color(0xFFAC352C));
    expect(dark.state.focusRingDestructive, const Color(0xFFF8AAA0));
    expect(light.fade.illustration, const Color(0x0019261F));
    expect(dark.fade.illustration, const Color(0x8019261F));
    expect(light.sync.lightError, const Color(0xFFAC352C));
    expect(dark.sync.lightError, const Color(0xFFF8AAA0));
  });

  test('Sybil text and active controls retain readable contrast', () {
    double contrast(Color foreground, Color background) {
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    for (final colors in [
      AppThemeData.light.colors,
      AppThemeData.dark.colors,
    ]) {
      for (final surface in [colors.background.ground, colors.surface.card]) {
        for (final text in [
          colors.text.primary,
          colors.text.secondary,
          colors.text.warning,
          colors.text.destructive,
        ]) {
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        contrast(colors.button.primary.label, colors.button.primary.bg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(
          colors.button.primary.labelHover,
          colors.button.primary.bgHover,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.button.destructive.label, colors.button.destructive.bg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.navPanel.activeLabel, colors.navPanel.activeBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(colors.text.warning, isNot(colors.text.destructive));
      expect(colors.text.warning, isNot(colors.text.success));
    }
  });

  test('macOS utility colours follow Sybil window surfaces', () {
    final light = AppThemeData.light.colors.macosUtility;
    final dark = AppThemeData.dark.colors.macosUtility;

    expect(light.window, const Color(0xFFF7F6EF));
    expect(light.windowTransparent, const Color(0x00F7F6EF));
    expect(light.navPanel, const Color(0x4DFFFEF9));
    expect(light.font, const Color(0xFF243B30));
    expect(light.thinBorder, const Color(0xFFD9DFD3));
    expect(light.innerBorder, const Color(0x26FFFFFF));

    expect(dark.window, const Color(0xFF19261F));
    expect(dark.windowTransparent, const Color(0x0019261F));
    expect(dark.navPanel, const Color(0x4D13251C));
    expect(dark.font, const Color(0xFFEDF1DE));
    expect(dark.thinBorder, const Color(0xFF415345));
    expect(dark.innerBorder, const Color(0x26FFFFFF));
  });

  test('plum primitive tokens match 2 Color Theme-3.zip', () {
    expect(PlumPrimitives.p0Light, const Color(0xFFF6ECF9));
    expect(PlumPrimitives.p50Light, const Color(0xFFE6C5EC));
    expect(PlumPrimitives.p300Light, const Color(0xFFAB40BF));
    expect(PlumPrimitives.p400Light, const Color(0xFF9338A7));
    expect(PlumPrimitives.p500Light, const Color(0xFF772E89));
    expect(PlumPrimitives.p900Light, const Color(0xFF0C050E));

    expect(PlumPrimitives.p0Dark, const Color(0xFF0B060D));
    expect(PlumPrimitives.p50Dark, const Color(0xFF2F133A));
    expect(PlumPrimitives.p300Dark, const Color(0xFF9338A7));
    expect(PlumPrimitives.p400Dark, const Color(0xFFAB40BF));
    expect(PlumPrimitives.p500Dark, const Color(0xFFB85BC8));
    expect(PlumPrimitives.p900Dark, const Color(0xFFF6ECF9));

    expect(PlumPrimitives.p400Alpha15Light, const Color(0x269338A7));
    expect(PlumPrimitives.p400Alpha15Dark, const Color(0x26AB40BF));
  });
}
