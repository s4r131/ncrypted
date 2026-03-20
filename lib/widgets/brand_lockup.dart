import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    required this.logoSize,
    required this.wordmarkSize,
    this.wordmarkLetterSpacing = 1.4,
    this.taglineToWordmarkRatio = 0.42,
    this.taglineLetterSpacingRatio = 0.01,
    this.easterEggEnabled = false,
  });

  final double logoSize;
  final double wordmarkSize;
  final double wordmarkLetterSpacing;
  final double taglineToWordmarkRatio;
  final double taglineLetterSpacingRatio;
  final bool easterEggEnabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF888780)
        : const Color(0xFF888780);

    final taglineSize = wordmarkSize * taglineToWordmarkRatio;
    final taglineLetterSpacing = wordmarkSize * taglineLetterSpacingRatio;
    if (easterEggEnabled) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/branding/sabre_terminal_orange.png',
          height: logoSize + 22,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    return Row(
      children: [
        SvgPicture.asset(
          'assets/branding/ncry_logo.svg',
          width: logoSize,
          height: logoSize,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ncrypted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall?.copyWith(
                  fontSize: wordmarkSize,
                  letterSpacing: wordmarkLetterSpacing,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'secure · local · yours',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: taglineSize,
                    letterSpacing: taglineLetterSpacing,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
