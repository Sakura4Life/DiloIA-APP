import 'dart:io';

import 'package:drift/drift.dart';

import '../core/constants.dart';
import 'database.dart';

/// Operaciones sobre la cola de dictados por voz (tabla Dictados).
class DictadosRepository {
  /// [borrarArchivo] se puede reemplazar en las pruebas para no tocar el disco.
  DictadosRepository(
    this._db, {
    Future<void> Function(String ruta)? borrarArchivo,
  }) : _borrarArchivo = borrarArchivo ?? _borrarDelDisco;

  final AppDatabase _db;
  final Future<void> Function(String ruta) _borrarArchivo;

  static Future<void> _borrarDelDisco(String ruta) async {
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  }

  /// Todos los dictados, del más antiguo al más nuevo.
  Stream<List<Dictado>> watchTodos() {
    return (_db.select(_db.dictados)..orderBy([
          (d) => OrderingTerm.asc(d.grabadoEn),
          (d) => OrderingTerm.asc(d.id),
        ]))
        .watch();
  }

  Future<Dictado?> obtener(int id) {
    return (_db.select(
      _db.dictados,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  Future<int> contar() async {
    final cantidad = _db.dictados.id.count();
    final fila = await (_db.selectOnly(
      _db.dictados,
    )..addColumns([cantidad])).getSingle();
    return fila.read(cantidad) ?? 0;
  }

  /// Guarda un dictado recién grabado, todavía sin procesar.
  Future<int> crear({required String rutaAudio, required DateTime grabadoEn}) {
    return _db
        .into(_db.dictados)
        .insert(
          DictadosCompanion.insert(
            rutaAudio: rutaAudio,
            grabadoEn: grabadoEn,
            estado: EstadoDictado.esperando,
          ),
        );
  }

  /// Los que aún debe procesar la IA, del más antiguo al más nuevo.
  Future<List<Dictado>> esperando() {
    return (_db.select(_db.dictados)
          ..where((d) => d.estado.equalsValue(EstadoDictado.esperando))
          ..orderBy([
            (d) => OrderingTerm.asc(d.grabadoEn),
            (d) => OrderingTerm.asc(d.id),
          ]))
        .get();
  }

  Future<void> _cambiar(int id, DictadosCompanion cambios) {
    return (_db.update(
      _db.dictados,
    )..where((d) => d.id.equals(id))).write(cambios);
  }

  /// La IA lo entendió: [resultadoJson] es su respuesta tal cual.
  Future<void> marcarListo(int id, String resultadoJson) => _cambiar(
    id,
    DictadosCompanion(
      estado: const Value(EstadoDictado.listo),
      resultado: Value(resultadoJson),
      mensaje: const Value(null),
    ),
  );

  /// Se volverá a intentar más tarde (sin internet, IA ocupada…).
  Future<void> marcarEsperando(int id, String mensaje) => _cambiar(
    id,
    DictadosCompanion(
      estado: const Value(EstadoDictado.esperando),
      mensaje: Value(mensaje),
    ),
  );

  /// No tiene sentido reintentarlo solo: el usuario decide qué hacer.
  Future<void> marcarFallido(int id, String mensaje) => _cambiar(
    id,
    DictadosCompanion(
      estado: const Value(EstadoDictado.fallido),
      mensaje: Value(mensaje),
    ),
  );

  /// Lo vuelve a poner en la cola, por ejemplo al tocar "Reintentar".
  Future<void> volverAEsperar(int id) => _cambiar(
    id,
    const DictadosCompanion(
      estado: Value(EstadoDictado.esperando),
      mensaje: Value(null),
    ),
  );

  /// Borra el dictado y su audio. Se usa al guardar la tarea o al descartarlo.
  Future<void> borrar(int id) async {
    final dictado = await obtener(id);
    if (dictado == null) return;
    await (_db.delete(_db.dictados)..where((d) => d.id.equals(id))).go();
    await _borrarArchivo(dictado.rutaAudio);
  }
}
