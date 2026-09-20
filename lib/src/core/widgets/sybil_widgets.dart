import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

export '../theme/sybil_palette.dart';

class SybilBetaBadge extends StatelessWidget {
  const SybilBetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          'Beta',
          style: AppTypography.bodySmall.copyWith(
            color: palette.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A stable personal colour and shape, derived only from the supplied identity.
class SybilAvatar extends StatelessWidget {
  const SybilAvatar({
    required this.label,
    required this.identity,
    this.size = 48,
    super.key,
  }) : assert(size > 0);

  final String label;
  final String identity;
  final double size;

  int get _tone {
    var hash = 0;
    for (final codePoint in identity.runes) {
      hash = (hash * 31 + codePoint) & 0x7fffffff;
    }
    return hash % 5;
  }

  String get _initials {
    final words = label.trim().split(RegExp(r'\s+'));
    if (words.first.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    final tone = _tone;
    final background = switch (tone) {
      0 => palette.peach,
      1 => palette.lilac,
      2 => palette.sage,
      3 => palette.sky,
      _ => palette.lime,
    };
    final radius = switch (tone) {
      0 => BorderRadius.circular(size / 2),
      1 => BorderRadius.only(
        topLeft: Radius.circular(size * 0.375),
        topRight: Radius.circular(size * 0.375),
        bottomLeft: Radius.circular(size * 0.375),
        bottomRight: Radius.circular(size * 0.146),
      ),
      2 => BorderRadius.circular(size * 0.292),
      3 => BorderRadius.vertical(
        top: Radius.circular(size / 2),
        bottom: Radius.circular(size * 0.271),
      ),
      _ => BorderRadius.only(
        topLeft: Radius.circular(size / 3),
        topRight: Radius.circular(size * 0.104),
        bottomLeft: Radius.circular(size * 0.104),
        bottomRight: Radius.circular(size / 3),
      ),
    };

    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Text(
            _initials,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: AppTypography.headlineLarge.copyWith(
              fontSize: size * 0.417,
              height: 1,
              letterSpacing: -size / 48,
              color: palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class SybilCard extends StatelessWidget {
  const SybilCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SybilPageHeader extends StatelessWidget {
  const SybilPageHeader({
    required this.title,
    this.eyebrow,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = SybilPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: AppTypography.bodySmall.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Young Serif',
              fontSize: 42,
              height: 1.2,
              letterSpacing: -1.4,
              color: palette.ink,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTypography.bodyMedium.copyWith(color: palette.muted),
          ),
        ],
      ],
    );
  }
}
