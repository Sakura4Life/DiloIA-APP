import 'package:drift/drift.dart';

import 'database.dart';

export 'database.dart' show claveDeOrden;

/// Operaciones sobre los cursos. Las pantallas usan esta clase en vez de
/// hablar directamente con la base de datos.
class CoursesRepository {
  CoursesRepository(this._db);

  final AppDatabase _db;

  /// Cursos en el orden que eligió el usuario. Es un stream: emite una lista
  /// nueva cada vez que se crea, edita, mueve o borra un curso.
  Stream<List<Course>> watchTodos() {
    return (_db.select(_db.courses)..orderBy([
          (c) => OrderingTerm.asc(c.orden),
          // Desempate estable si dos cursos tuvieran el mismo orden.
          (c) => OrderingTerm.asc(c.id),
        ]))
        .watch();
  }

  /// Los cursos una sola vez, sin quedarse escuchando cambios.
  Future<List<Course>> todos() {
    return (_db.select(_db.courses)..orderBy([
          (c) => OrderingTerm.asc(c.orden),
          (c) => OrderingTerm.asc(c.id),
        ]))
        .get();
  }

  /// Crea un curso al inicio de la lista y devuelve su id.
  Future<int> crear({required String nombre, required int color}) async {
    // Un número menor que el del primer curso actual lo pone arriba de todos.
    // Puede ser negativo: solo importa que sea el más pequeño.
    final minimo = _db.courses.orden.min();
    final fila = await (_db.selectOnly(
      _db.courses,
    )..addColumns([minimo])).getSingle();
    final siguiente = (fila.read(minimo) ?? 1) - 1;

    return _db
        .into(_db.courses)
        .insert(
          CoursesCompanion.insert(
            nombre: nombre.trim(),
            color: color,
            orden: Value(siguiente),
          ),
        );
  }

  Future<void> actualizar(Course curso) {
    return _db.update(_db.courses).replace(curso);
  }

  /// Guarda el nuevo orden después de arrastrar un curso. [idsEnOrden] es la
  /// lista completa de ids tal como quedó en pantalla.
  Future<void> reordenar(List<int> idsEnOrden) {
    // Una transacción: o se guardan todas las posiciones o ninguna.
    return _db.transaction(() async {
      for (var i = 0; i < idsEnOrden.length; i++) {
        await (_db.update(_db.courses)
              ..where((c) => c.id.equals(idsEnOrden[i])))
            .write(CoursesCompanion(orden: Value(i)));
      }
    });
  }

  /// Borra el curso. Sus tareas se borran solas (borrado en cascada).
  Future<void> borrar(int id) {
    return (_db.delete(_db.courses)..where((c) => c.id.equals(id))).go();
  }

  /// Cuántas tareas tiene un curso, para avisar antes de borrarlo.
  Future<int> contarTareas(int courseId) async {
    final cantidad = _db.tasks.id.count();
    final consulta = _db.selectOnly(_db.tasks)
      ..addColumns([cantidad])
      ..where(_db.tasks.courseId.equals(courseId));
    final fila = await consulta.getSingle();
    return fila.read(cantidad) ?? 0;
  }
}
