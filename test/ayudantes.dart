import 'dart:async';

import 'package:diloia_app/features/voice/providers_voz.dart';

/// Reemplaza la conectividad real (que necesita el celular) en las pruebas.
class ConectividadFalsa extends Conectividad {
  ConectividadFalsa({this.conectado = false});

  bool conectado;
  final _cambios = StreamController<bool>.broadcast();

  @override
  Future<bool> hayRed() async => conectado;

  @override
  Stream<bool> get cambios => _cambios.stream;

  /// Simula que la red se corta o vuelve.
  void cambiar({required bool conectado}) {
    this.conectado = conectado;
    _cambios.add(conectado);
  }
}
