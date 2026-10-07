import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/fecha_lima.dart';
import '../../data/courses_repository.dart';
import '../../data/database.dart';
import '../../data/dictados_repository.dart';
import 'extraccion_api.dart';

/// Envía los dictados guardados a la IA y anota el resultado en la cola.
///
/// Todo dictado pasa por aquí, haya internet o no: primero se guarda en la
/// cola y luego se procesa. Así, si algo falla a mitad de camino, el dictado
/// no se pierde.
class ProcesadorDictados {
  ProcesadorDictados({
    required this._dictados,
    required this._cursos,
    required this._api,
    Future<Uint8List> Function(String ruta)? leerAudio,
    Future<void> Function(Duration)? esperar,
    this.pausaEntreDictados = const Duration(seconds: 4),
  }) : _leerAudio = leerAudio ?? ((ruta) => File(ruta).readAsBytes()),
       _esperar = esperar ?? Future<void>.delayed;

  final DictadosRepository _dictados;
  final CoursesRepository _cursos;
  final ExtraccionApi _api;
  final Future<Uint8List> Function(String ruta) _leerAudio;
  final Future<void> Function(Duration) _esperar;

  /// Gemini gratis acepta 15 peticiones por minuto: una cada 4 s como mucho.
  final Duration pausaEntreDictados;

  /// Dictados que se están enviando ahora mismo, con su resultado pendiente.
  final _enCurso = <int, Future<Dictado?>>{};

  /// Ids que se están procesando, para mostrar "Procesando…" en pantalla.
  final procesando = ValueNotifier<Set<int>>(const {});

  bool _vaciandoCola = false;

  /// Envía un dictado a la IA y devuelve cómo quedó (o `null` si el usuario
  /// lo descartó mientras tanto). Si ya se está enviando, no lo envía dos
  /// veces: devuelve el mismo resultado.
  Future<Dictado?> procesar(int id) {
    return _enCurso[id] ??= _procesar(id).whenComplete(() {
      _enCurso.remove(id);
      procesando.value = {..._enCurso.keys};
    });
  }

  Future<Dictado?> _procesar(int id) async {
    procesando.value = {..._enCurso.keys, id};
    final dictado = await _dictados.obtener(id);
    if (dictado == null) return null;

    try {
      final audio = await _leerAudio(dictado.rutaAudio);
      final cursos = await _cursos.todos();
      final resultado = await _api.extraer(
        audioWav: audio,
        // La fecha en que se grabó, no la de hoy: si dijo "mañana" el lunes,
        // es el martes aunque el dictado se procese el miércoles.
        hoy: fechaEnLima(dictado.grabadoEn),
        cursos: [for (final c in cursos) c.nombre],
      );
      await _dictados.marcarListo(id, jsonEncode(resultado.aJson()));
    } on ErrorExtraccion catch (e) {
      if (e.reintentable) {
        await _dictados.marcarEsperando(id, e.mensaje);
      } else {
        await _dictados.marcarFallido(id, e.mensaje);
      }
    } on FileSystemException {
      await _dictados.marcarFallido(id, 'No se encontró el audio del dictado.');
    }
    return _dictados.obtener(id);
  }

  /// Procesa todos los dictados que esperan, uno por uno. Se llama al abrir
  /// la app y cada vez que vuelve la conexión.
  Future<void> procesarPendientes() async {
    // Si ya se está vaciando la cola (por ejemplo, la red se cortó y volvió
    // dos veces seguidas), no se empieza otra vuelta en paralelo.
    if (_vaciandoCola) return;
    _vaciandoCola = true;
    try {
      final pendientes = await _dictados.esperando();
      for (var i = 0; i < pendientes.length; i++) {
        if (i > 0) await _esperar(pausaEntreDictados);
        final dictado = await procesar(pendientes[i].id);
        // Si siguió esperando, el problema afecta a todos (no hay internet o
        // la IA está ocupada): se intenta de nuevo la próxima vez.
        if (dictado?.estado == EstadoDictado.esperando) break;
      }
    } finally {
      _vaciandoCola = false;
    }
  }

  void dispose() => procesando.dispose();
}
