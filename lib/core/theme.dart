import 'package:flutter/material.dart';

/// Tema visual de la app. Material 3 genera toda la paleta (botones, barras,
/// fondos) a partir de un solo color semilla, en versión clara y oscura.
abstract final class AppTheme {
  static const _colorSemilla = Color(0xFF4F46E5);

  static final claro = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _colorSemilla),
  );

  static final oscuro = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _colorSemilla,
      brightness: Brightness.dark,
    ),
  );
}
