import 'dart:async';

import 'package:diloia_app/features/voice/grabadora.dart';
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

/// Un micrófono falso: no graba nada, solo anota lo que le pidieron.
class GrabadoraFalsa extends Grabadora {
  GrabadoraFalsa({this.permiso = true});

  bool permiso;

  /// Lo que se le pidió, en orden: "empezar", "pausar", "terminar"…
  final acciones = <String>[];

  @override
  Future<bool> tienePermiso({required bool pedir}) async => permiso;

  @override
  Future<String> empezar() async {
    acciones.add('empezar');
    return 'falso.wav';
  }

  @override
  Future<void> pausar() async => acciones.add('pausar');

  @override
  Future<void> reanudar() async => acciones.add('reanudar');

  @override
  Future<double> nivel() async => 0.5;

  @override
  Future<void> terminar() async => acciones.add('terminar');

  @override
  Future<void> cancelar() async => acciones.add('cancelar');

  @override
  Future<void> dispose() async {}
}
