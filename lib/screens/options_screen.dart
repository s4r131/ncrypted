import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/ncry_identity.dart';
import '../services/ncry_crypto.dart';
import '../services/security_preferences.dart';
import '../services/ncry_keys.dart';

const _bitStrengthArg = 'bitStrength';
const _publicExponentArg = 'publicExponent';
const _publicPemArg = 'publicPem';
const _privatePemArg = 'privatePem';

Map<String, String> _generateIdentityPem(Map<String, int> args) {
  final pair = CryptoService.generateKeyPair(
    bitStrength: args[_bitStrengthArg] ?? SecurityPreferences.defaultRsaKeyBits,
    publicExponent: args[_publicExponentArg] ?? SecurityPreferences.defaultRsaPublicExponent,
  );
  return {
    _publicPemArg: CryptoService.publicKeyToPem(pair.publicKey),
    _privatePemArg: CryptoService.privateKeyToPem(pair.privateKey),
  };
}

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.onEasterEggChanged,
  });

  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onEasterEggChanged;

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  static const _rsaKeySizes = <int>[2048, 3072, 4096];
  static const _rsaExponents = <int>[65537, 131071, 262147];

  bool _isLoading = true;
  bool _isApplying = false;
  int _rsaKeyBits = SecurityPreferences.defaultRsaKeyBits;
  int _rsaExponent = SecurityPreferences.defaultRsaPublicExponent;
  bool _requireVerifiedSender = SecurityPreferences.defaultRequireVerifiedSender;
  int _savedRsaKeyBits = SecurityPreferences.defaultRsaKeyBits;
  int _savedRsaExponent = SecurityPreferences.defaultRsaPublicExponent;
  bool _savedRequireVerifiedSender = SecurityPreferences.defaultRequireVerifiedSender;
  bool _isMaxProfile = false;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    final settings = await SecurityPreferences.load();
    final activeIdentity = await KeyStore.loadActiveIdentity();
    final isMax = await KeyStore.isActiveIdentityMaxProfile();
    if (!mounted) return;
    int effectiveBits = settings.rsaKeyBits;
    int effectiveExponent = settings.rsaPublicExponent;
    if (activeIdentity != null) {
      try {
        final values = _extractRsaFromIdentity(activeIdentity);
        effectiveBits = values.$1;
        effectiveExponent = values.$2;
      } catch (_) {
        // Fallback to saved settings if identity parsing fails.
      }
    }
    widget.onEasterEggChanged(isMax);
    setState(() {
      _rsaKeyBits = effectiveBits;
      _rsaExponent = effectiveExponent;
      _requireVerifiedSender = settings.requireVerifiedSender;
      _savedRsaKeyBits = effectiveBits;
      _savedRsaExponent = effectiveExponent;
      _savedRequireVerifiedSender = settings.requireVerifiedSender;
      _isMaxProfile = isMax;
      _isLoading = false;
    });
  }

  (int, int) _extractRsaFromIdentity(IdentityProfile identity) {
    final key = CryptoService.pemToPublicKey(identity.publicKeyPem);
    final bits = key.modulus?.bitLength;
    final exponent = key.exponent?.toInt();
    if (bits == null || exponent == null) {
      throw StateError('Could not read RSA parameters from identity');
    }
    return (bits, exponent);
  }

  bool get _hasPendingChanges {
    return _rsaKeyBits != _savedRsaKeyBits ||
        _rsaExponent != _savedRsaExponent ||
        _requireVerifiedSender != _savedRequireVerifiedSender;
  }

  Future<void> _showEasterEggPopupLive({
    required ValueListenable<String> publicPemListenable,
  }) async {
    if (!mounted) return;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'EasterEgg',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ValueListenableBuilder<String>(
          valueListenable: publicPemListenable,
          builder: (context, publicPem, _) {
            return _SabreTerminalEasterEgg(publicPem: publicPem);
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _applySecuritySettings() async {
    if (_isApplying || !_hasPendingChanges) return;
    setState(() => _isApplying = true);

    final nextIsMax = SecurityPreferences.isMaxProfileValues(
      rsaKeyBits: _rsaKeyBits,
      rsaPublicExponent: _rsaExponent,
    );
    final becameMax = nextIsMax && !_isMaxProfile;

    final popupPem = ValueNotifier<String>(
      'KEY STREAM AUTHORIZATION IN PROGRESS\n'
      'GENERATING IDENTITY KEY...\n'
      'PLEASE STAND BY',
    );

    DateTime? popupShownAt;
    var popupWasShown = false;

    try {
      if (becameMax && mounted) {
        popupShownAt = DateTime.now();
        popupWasShown = true;
        unawaited(_showEasterEggPopupLive(publicPemListenable: popupPem));
      }

      await SecurityPreferences.saveRsaKeyBits(_rsaKeyBits);
      await SecurityPreferences.saveRsaPublicExponent(_rsaExponent);
      await SecurityPreferences.saveRequireVerifiedSender(_requireVerifiedSender);

      final pemPair = await compute<Map<String, int>, Map<String, String>>(
        _generateIdentityPem,
        <String, int>{
          _bitStrengthArg: _rsaKeyBits,
          _publicExponentArg: _rsaExponent,
        },
      );

      final publicPem = pemPair[_publicPemArg] ?? '';
      final privatePem = pemPair[_privatePemArg] ?? '';

      if (publicPem.isEmpty || privatePem.isEmpty) {
        throw StateError('Generated key material was empty.');
      }

      popupPem.value = publicPem;

      await KeyStore.saveOrUpdateActiveIdentity(
        publicKeyPem: publicPem,
        privateKeyPem: privatePem,
      );

      if (!mounted) return;

      setState(() {
        _savedRsaKeyBits = _rsaKeyBits;
        _savedRsaExponent = _rsaExponent;
        _savedRequireVerifiedSender = _requireVerifiedSender;
        _isMaxProfile = nextIsMax;
      });

      final activeIsMax = await KeyStore.isActiveIdentityMaxProfile();
      widget.onEasterEggChanged(activeIsMax);

      if (popupWasShown) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final elapsed = DateTime.now().difference(popupShownAt!);
        const minimumDisplay = Duration(seconds: 2);
        if (elapsed < minimumDisplay) {
          await Future<void>.delayed(minimumDisplay - elapsed);
        }

        if (mounted) {
          final navigator = Navigator.of(context, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
          }
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security settings applied. New identity key created.'),
        ),
      );
    } catch (e) {
      if (popupWasShown && mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not apply settings: $e'),
        ),
      );
    } finally {
      popupPem.dispose();
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  int get _keySizeIndex {
    final idx = _rsaKeySizes.indexOf(_rsaKeyBits);
    return idx < 0 ? 0 : idx;
  }

  int get _exponentIndex {
    final idx = _rsaExponents.indexOf(_rsaExponent);
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Options',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                    selected: {widget.currentThemeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      widget.onThemeModeChanged(selection.first);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto light/dark follows your device setting.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'Advanced Security',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RSA key size: $_rsaKeyBits-bit',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _keySizeIndex.toDouble(),
                    min: 0,
                    max: (_rsaKeySizes.length - 1).toDouble(),
                    divisions: _rsaKeySizes.length - 1,
                    label: '${_rsaKeySizes[_keySizeIndex]}-bit',
                    onChanged: _isApplying
                        ? null
                        : (value) {
                            final selected = _rsaKeySizes[value.round()];
                            setState(() => _rsaKeyBits = selected);
                          },
                  ),
                  Text(
                    _rsaKeyBits == 2048
                        ? 'Balanced speed/security for most devices.'
                        : 'Higher bit sizes are slower but harder to brute-force.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'RSA public exponent: $_rsaExponent',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _exponentIndex.toDouble(),
                    min: 0,
                    max: (_rsaExponents.length - 1).toDouble(),
                    divisions: _rsaExponents.length - 1,
                    label: _rsaExponents[_exponentIndex].toString(),
                    onChanged: _isApplying
                        ? null
                        : (value) {
                            final selected = _rsaExponents[value.round()];
                            setState(() => _rsaExponent = selected);
                          },
                  ),
                  Text(
                    '65537 is standard and recommended for compatibility.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _requireVerifiedSender,
                    onChanged: _isApplying
                        ? null
                        : (value) {
                            setState(() => _requireVerifiedSender = value);
                          },
                    title: const Text('Require verified sender'),
                    subtitle: const Text(
                      'Block saving decrypted files when sender signature is unknown.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Apply to save these settings and automatically create a new identity key.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (!_hasPendingChanges || _isApplying)
                        ? null
                        : _applySecuritySettings,
                    icon: Icon(_isApplying ? Icons.hourglass_top : Icons.check_circle_outline),
                    label: Text(_isApplying ? 'Applying...' : 'Apply & Create New Key'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SabreTerminalEasterEgg extends StatefulWidget {
  const _SabreTerminalEasterEgg({required this.publicPem});

  final String publicPem;

  @override
  State<_SabreTerminalEasterEgg> createState() => _SabreTerminalEasterEggState();
}

class _SabreTerminalEasterEggState extends State<_SabreTerminalEasterEgg>
    with TickerProviderStateMixin {
  late final AnimationController _scrollController;
  late final AnimationController _fxController;
  late final AnimationController _cursorController;

  ui.Image? _logoImage;
  bool _logoLoadFailed = false;

  @override
  void initState() {
    super.initState();

    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();

    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/branding/sabre_terminal_orange.png');
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _logoImage = frame.image;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _logoLoadFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fxController.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _scrollController,
        _fxController,
        _cursorController,
      ]),
      builder: (context, _) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 760,
                height: 420,
                child: CustomPaint(
                  painter: _CrtTerminalPainter(
                    publicPem: widget.publicPem,
                    scrollT: _scrollController.value,
                    fxT: _fxController.value,
                    cursorVisible: _cursorController.value > 0.35,
                    logoImage: _logoImage,
                    logoLoadFailed: _logoLoadFailed,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CrtTerminalPainter extends CustomPainter {
  const _CrtTerminalPainter({
    required this.publicPem,
    required this.scrollT,
    required this.fxT,
    required this.cursorVisible,
    required this.logoImage,
    required this.logoLoadFailed,
  });

  final String publicPem;
  final double scrollT;
  final double fxT;
  final bool cursorVisible;
  final ui.Image? logoImage;
  final bool logoLoadFailed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = fxT * 1.3 * math.pi;

    final recorder = ui.PictureRecorder();
    final sourceCanvas = Canvas(recorder, Offset.zero & size);

    _drawSource(sourceCanvas, size, time);

    final picture = recorder.endRecording();
    final sourceImage = picture.toImageSync(w.ceil(), h.ceil());

    final srcRect = Rect.fromLTWH(0, 0, w, h);
    final dstRect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(dstRect, Paint()..color = const Color(0xFF0A0800));

    for (int y = 0; y < h.floor(); y++) {
      final wave =
          math.sin(y * 0.035 + time * 7.5) * 1.2 +
          math.sin(y * 0.012 + time * 2.8) * 0.8;

      final bucket = (time * 40).floor();
      final n = _pseudoNoise(y * 0.73 + bucket * 13.17);
      final randomJitter = (n - 0.5) * 2.2;

      double bandShift = 0;
      final bandCenter = (math.sin(time * 1.7) * 0.5 + 0.5) * h;
      final distFromBand = (y - bandCenter).abs();

      if (distFromBand < 20) {
        bandShift = (1 - distFromBand / 20) * math.sin(time * 38) * 8;
      }

      final xOffset = wave + randomJitter + bandShift;

      final lineSrc = Rect.fromLTWH(0, y.toDouble(), w, 1);
      final lineDst = Rect.fromLTWH(xOffset, y.toDouble(), w, 1);

      canvas.drawImageRect(sourceImage, lineSrc, lineDst, Paint());
    }

    if (((fxT * 1000).floor() % 3) == 0) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = const Color(0xFFF5C060).withValues(alpha: 0.07),
      );
      canvas.translate(1, 0);
      canvas.drawImageRect(sourceImage, srcRect, dstRect, Paint());
      canvas.restore();
    }

    _drawScanlines(canvas, size);
    _drawNoise(canvas, size, time);
    _drawVignette(canvas, size);
    _drawFlicker(canvas, size, time);
    _drawStatusLine(canvas, size);
  }

  void _drawSource(Canvas canvas, Size size, double time) {
    final w = size.width;
    final h = size.height;

    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        const [
          Color(0xFF1A0F00),
          Color(0xFF0A0800),
        ],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, h / 2),
        w * 0.35,
        [
          const Color(0xFFF5A030).withValues(alpha: 0.18),
          const Color(0xFFF5A030).withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final lines = publicPem
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    final repeatedLines = <String>[
      ...lines,
      ...lines,
      ...lines,
    ];

    final textStyle = ui.TextStyle(
      color: const Color(0xFFF5A030).withValues(alpha: 0.40),
      fontSize: 9,
      fontFamily: 'monospace',
    );

    final paragraphStyle = ui.ParagraphStyle(
      maxLines: 1,
      fontSize: 9,
    );

    const lineHeight = 11.0;
    final textOffsetY = -220.0 * scrollT;

    for (int i = 0; i < repeatedLines.length; i++) {
      final y = 8.0 + textOffsetY + (i * lineHeight);
      if (y < -20 || y > h + 20) continue;

      final builder = ui.ParagraphBuilder(paragraphStyle)..pushStyle(textStyle);
      builder.addText(repeatedLines[i]);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 730));
      canvas.drawParagraph(paragraph, Offset(12, y));
    }

    final topFade = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        [
          const Color(0xFF0A0800).withValues(alpha: 0.96),
          const Color(0x220A0800),
          const Color(0x220A0800),
          const Color(0xFF0A0800).withValues(alpha: 0.96),
        ],
        const [0.0, 0.18, 0.82, 1.0],
      );
    canvas.drawRect(Offset.zero & size, topFade);

    if (logoImage != null) {
      final img = logoImage!;
      final targetWidth = w * 0.52;
      final scale = targetWidth / img.width;
      final targetHeight = img.height * scale;
      final dx = (w - targetWidth) / 2;
      final dy = (h - targetHeight) / 2 + math.sin(time * 2) * 1.0;

      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(dx - 1.5, dy, targetWidth, targetHeight),
        Paint()..color = Colors.white.withValues(alpha: 0.16),
      );

      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(dx + 1.2, dy, targetWidth, targetHeight),
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );

      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(dx, dy, targetWidth, targetHeight),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );

      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(dx, dy, targetWidth, targetHeight),
        Paint(),
      );
    } else {
      final titlePainter = TextPainter(
        text: TextSpan(
          text: logoLoadFailed ? 'SABRE TERMINAL' : 'LOADING TERMINAL',
          style: const TextStyle(
            color: Color(0xFFF5C060),
            fontSize: 42,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final subPainter = TextPainter(
        text: const TextSpan(
          text: 'KEY STREAM AUTHORIZATION',
          style: TextStyle(
            color: Color(0xCCF5C060),
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      titlePainter.paint(
        canvas,
        Offset((w - titlePainter.width) / 2, (h / 2) - 34),
      );
      subPainter.paint(
        canvas,
        Offset((w - subPainter.width) / 2, (h / 2) + 18),
      );
    }

    final centerGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, h / 2),
        w * 0.48,
        const [
          Color(0x22F5A030),
          Colors.transparent,
          Color(0x66000000),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, centerGlow);
  }

  void _drawScanlines(Canvas canvas, Size size) {
    for (double y = 0; y < size.height; y += 4.0) {
      final p1 = Paint()..color = Colors.black.withValues(alpha: 0.00);
      final p2 = Paint()..color = Colors.black.withValues(alpha: 0.00);
      final p3 = Paint()..color = Colors.black.withValues(alpha: 0.18);
      final p4 = Paint()..color = Colors.black.withValues(alpha: 0.28);

      canvas.drawLine(Offset(0, y), Offset(size.width, y), p1);
      canvas.drawLine(Offset(0, y + 1), Offset(size.width, y + 1), p2);
      canvas.drawLine(Offset(0, y + 2), Offset(size.width, y + 2), p3);
      canvas.drawLine(Offset(0, y + 3), Offset(size.width, y + 3), p4);
    }
  }

  void _drawNoise(Canvas canvas, Size size, double time) {
    final random = math.Random((time * 1000).floor());
    final paint = Paint()..color = const Color(0xFFF5C060).withValues(alpha: 0.06);

    for (int i = 0; i < 1200; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 0.8, 0.8), paint);
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        math.max(size.width, size.height) * 0.72,
        const [
          Color(0x00000000),
          Color(0x52000000),
        ],
        const [0.50, 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawFlicker(Canvas canvas, Size size, double time) {
    final opacity = 0.04 + (0.04 * (0.5 + 0.5 * math.sin(time * 17.0)));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
  }

  void _drawStatusLine(Canvas canvas, Size size) {
    final statusPainter = TextPainter(
      text: const TextSpan(
        text: 'KEY STREAM AUTHORIZED',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: Color(0xCCF5C060),
          letterSpacing: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    statusPainter.paint(canvas, Offset(16, size.height - 26));

    if (cursorVisible) {
      canvas.drawRect(
        Rect.fromLTWH(
          16 + statusPainter.width + 6,
          size.height - 24,
          7,
          11,
        ),
        Paint()..color = const Color(0xFFF5A030),
      );
    }
  }

  double _pseudoNoise(double n) {
    final x = math.sin(n * 127.1) * 43758.5453123;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _CrtTerminalPainter oldDelegate) {
    return oldDelegate.publicPem != publicPem ||
        oldDelegate.scrollT != scrollT ||
        oldDelegate.fxT != fxT ||
        oldDelegate.cursorVisible != cursorVisible ||
        oldDelegate.logoImage != logoImage ||
        oldDelegate.logoLoadFailed != logoLoadFailed;
  }
}