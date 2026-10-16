import 'package:flutter/material.dart';

const ink = Color(0xff181d26),
    muted = Color(0xff626b78),
    hairline = Color(0xffe3e6ea),
    danger = Color(0xffaa2d00),
    success = Color(0xff248458);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  fontFamily: 'Segoe UI',
  fontFamilyFallback: const ['Microsoft YaHei UI', 'PingFang SC'],
  colorScheme: const ColorScheme.light(
    primary: ink,
    secondary: ink,
    surface: Colors.white,
    error: danger,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14, color: ink),
    bodyLarge: TextStyle(fontSize: 14, color: ink),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w500,
      color: ink,
    ),
  ),
  dividerTheme: const DividerThemeData(color: hairline, space: 1, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    hintStyle: const TextStyle(color: muted, fontSize: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: hairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: hairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xff458fff), width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(100, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(100, 44),
      side: const BorderSide(color: Color(0xffa8afb8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 14),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: const TextStyle(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 400),
  ),
);
String clockText(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}
