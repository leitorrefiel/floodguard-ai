import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const blue = Color(0xFF1E70E8);
  static const navy = Color(0xFF123B78);
  static const paleBlue = Color(0xFFEAF3FF);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: blue),
    scaffoldBackgroundColor: const Color(0xFFF8FAFD),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF8FAFD),
      foregroundColor: navy,
      centerTitle: true,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE3EAF4)),
      ),
    ),
  );
}
