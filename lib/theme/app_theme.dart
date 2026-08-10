import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData build({required bool pink}) {
    final primary = pink ? const Color(0xFFF5A9C0) : const Color(0xFF5AAFE3);
    final secondary = pink ? const Color(0xFFF8C9D7) : const Color(0xFF83C6ED);
    final background = pink ? const Color(0xFFFFF5FA) : const Color(0xFFF3FAFF);
    final surface = pink ? const Color(0xFFFFFBFD) : const Color(0xFFF7FBFF);
    final border = pink ? const Color(0xFFF4C1D3) : const Color(0xFFB9DFF5);
    final text = pink ? const Color(0xFF5A4050) : const Color(0xFF25445A);

    return ThemeData(
      fontFamily: 'Microsoft YaHei',
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: text,
        surface: surface,
        onSurface: text,
        primaryContainer:
            pink ? const Color(0xFFFFE2EC) : const Color(0xFFDDF1FF),
        onPrimaryContainer: text,
        secondaryContainer:
            pink ? const Color(0xFFFFEEF4) : const Color(0xFFE8F6FF),
        onSecondaryContainer: text,
        outline: border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: text.withOpacity(.55)),
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: text,
            displayColor: text,
            fontFamily: 'Microsoft YaHei',
          ),
    );
  }
}
