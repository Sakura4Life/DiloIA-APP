import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se guarda la preferencia de modo claro u oscuro.
///
/// Es una interfaz para poder reemplazarla en las pruebas con una en memoria
/// (`TemaRepositoryEnMemoria`), así no se escribe en el disco del equipo que
/// corre la suite.
abstract interface class TemaRepository {
  /// Modo elegido la última vez, o `null` si el usuario todavía no eligió.
  ThemeMode? get modoGuardado;

  /// Deja escrito el modo elegido para la próxima vez que abra la app.
  Future<void> guardarModo(ThemeMode modo);
}

/// Implementación de verdad: escribe en `shared_preferences`, que persiste en
/// el dispositivo aunque se cierre la app.
class TemaRepositoryPreferencias implements TemaRepository {
  TemaRepositoryPreferencias(this._prefs);

  final SharedPreferences _prefs;

  static const _clave = 'tema_modo';

  @override
  ThemeMode? get modoGuardado {
    final valor = _prefs.getString(_clave);
    if (valor == null) return null;
    // Si la app cambia y guarda un modo que esta versión no conoce, se
    // ignora y se vuelve al modo del sistema en vez de fallar.
    for (final modo in ThemeMode.values) {
      if (modo.name == valor) return modo;
    }
    return null;
  }

  @override
  Future<void> guardarModo(ThemeMode modo) =>
      _prefs.setString(_clave, modo.name);
}

/// Relleno que no toca el disco: guarda solo en memoria. Lo usa la app en
/// pruebas, donde no existe `shared_preferences`.
class TemaRepositoryEnMemoria implements TemaRepository {
  ThemeMode? _modo;

  @override
  ThemeMode? get modoGuardado => _modo;

  @override
  Future<void> guardarModo(ThemeMode modo) async => _modo = modo;
}
