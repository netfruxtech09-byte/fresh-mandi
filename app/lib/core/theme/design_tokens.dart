import 'package:flutter/material.dart';

class DT {
  static const bg = Color(0xFFF2F8F4);
  static const card = Colors.white;
  static const text = Color(0xFF121826);
  static const sub = Color(0xFF586174);
  static const muted = Color(0xFF98A1B2);
  static const primary = Color(0xFF09C256);
  static const primaryDark = Color(0xFF04963F);
  static const orange = Color(0xFFFF8A00);
  static const field = Color(0xFFE9EAF0);
  static const border = Color(0xFFD0D5DD);

  static BorderRadius get r12 => BorderRadius.circular(12);
  static BorderRadius get r16 => BorderRadius.circular(16);
  static BorderRadius get r20 => BorderRadius.circular(20);
  static BorderRadius get r24 => BorderRadius.circular(24);

  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x160F172A),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ];
}
