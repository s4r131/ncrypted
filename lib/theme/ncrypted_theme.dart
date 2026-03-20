import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NcryptedTheme {
  static const ncBlack = Color(0xFF2C2C2A);
  static const ncInk = Color(0xFF444441);
  static const ncMuted = Color(0xFF888780);
  static const ncStone = Color(0xFFD3D1C7);
  static const ncCream = Color(0xFFF1EFE8);
  static const ncAccent = Color(0xFF1D9E75);
  static const ncAccentDark = Color(0xFF0F6E56);
  static const ncAccentLight = Color(0xFFE1F5EE);
  static const ncDanger = Color(0xFFE24B4A);
  static const terminalSolar = Color(0xFFF5C060); // highlights
  static const terminalAmber = Color(0xFFF5A030); // primary glow
  static const terminalCore = Color(0xFFE8830A); // core accent
  static const terminalEmber = Color(0xFF7A4200); // shadows, depth
  static const terminalPitch = Color(0xFF0A0800); // background
  static const terminalSurface = Color(0xFF161003); // cards/surfaces

  static ThemeData light({bool useSabrePalette = false}) {
    final scheme = ColorScheme.light(
      primary: useSabrePalette ? terminalCore : ncAccent,
      onPrimary: useSabrePalette ? terminalPitch : Colors.white,
      secondary: useSabrePalette ? terminalAmber : ncAccentDark,
      error: ncDanger,
      surface: useSabrePalette ? terminalSurface : Colors.white,
      onSurface: useSabrePalette ? terminalSolar : ncBlack,
      outline: useSabrePalette ? terminalEmber : ncStone,
      outlineVariant: useSabrePalette ? terminalEmber : const Color(0xFFE3E1D9),
    );
    return _baseTheme(scheme, isDark: false, useSabrePalette: useSabrePalette);
  }

  static ThemeData dark({bool useSabrePalette = false}) {
    final scheme = ColorScheme.dark(
      primary: useSabrePalette ? terminalCore : ncAccent,
      onPrimary: useSabrePalette ? terminalPitch : ncCream,
      secondary: useSabrePalette ? terminalAmber : ncAccentDark,
      error: ncDanger,
      surface: useSabrePalette ? terminalSurface : ncInk,
      onSurface: useSabrePalette ? terminalSolar : ncStone,
      outline: useSabrePalette ? terminalEmber : ncMuted,
      outlineVariant: useSabrePalette ? terminalEmber : const Color(0x66444441),
    );
    return _baseTheme(scheme, isDark: true, useSabrePalette: useSabrePalette);
  }

  static ThemeData _baseTheme(
    ColorScheme scheme, {
    required bool isDark,
    required bool useSabrePalette,
  }) {
    final baseTextTheme =
        GoogleFonts.jetBrainsMonoTextTheme(isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: useSabrePalette ? terminalPitch : (isDark ? ncBlack : ncCream),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: GoogleFonts.jetBrainsMono(
          fontSize: 32,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        ),
        headlineSmall: GoogleFonts.jetBrainsMono(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        ),
        titleLarge: GoogleFonts.jetBrainsMono(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        ),
        titleMedium: GoogleFonts.jetBrainsMono(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        ),
        bodyMedium: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: useSabrePalette ? terminalAmber : (isDark ? ncStone : ncInk),
        ),
        bodySmall: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: useSabrePalette ? terminalAmber : ncMuted,
          letterSpacing: 0.08,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: useSabrePalette ? terminalPitch : (isDark ? ncBlack : ncCream),
        foregroundColor: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: useSabrePalette ? terminalSurface : (isDark ? ncInk : Colors.white),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: useSabrePalette
                ? terminalEmber.withValues(alpha: 0.55)
                : (isDark ? ncMuted.withValues(alpha: 0.14) : ncStone.withValues(alpha: 0.22)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: useSabrePalette ? terminalSurface : (isDark ? ncInk : Colors.white),
        labelStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: useSabrePalette ? terminalAmber : ncMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: useSabrePalette ? terminalEmber : (isDark ? ncMuted.withValues(alpha: 0.5) : ncStone),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: useSabrePalette ? terminalCore : ncAccent,
          foregroundColor: useSabrePalette ? terminalPitch : (isDark ? ncCream : Colors.white),
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncBlack),
          side: BorderSide(
            color: useSabrePalette ? terminalEmber : (isDark ? ncMuted.withValues(alpha: 0.4) : ncStone),
          ),
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
          color: useSabrePalette ? terminalEmber : (isDark ? ncMuted.withValues(alpha: 0.4) : ncStone),
        ),
        backgroundColor: useSabrePalette ? terminalSurface : (isDark ? ncInk : Colors.white),
        labelStyle: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: useSabrePalette ? terminalSolar : (isDark ? ncStone : ncInk),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: useSabrePalette ? terminalSurface : null,
        contentTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: useSabrePalette ? terminalSolar : null,
        ),
      ),
      dividerColor: useSabrePalette
          ? terminalEmber.withValues(alpha: 0.55)
          : (isDark ? ncMuted.withValues(alpha: 0.2) : ncStone),
    );
  }
}
