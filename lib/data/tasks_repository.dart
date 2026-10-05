import 'package:drift/drift.dart';

import 'database.dart';

/// Una tarea junto con el curso al que pertenece, que la lista necesita para
/// mostrar el nombre y el color.
typedef TareaConCurso = ({Task tarea, Course curso});

/// Operaciones sobre las tareas.
class TasksRepository {
  TasksRepository(this._db);

  final AppDatabase _db;

  /// Tareas ordenadas por fecha, cada una con su curso. Si
  /// [incluirCompletadas] es falso, solo devuelve las pendientes.
  Stream<List<TareaConCurso>> watchTareas({required bool incluirCompletadas}) {
    final consulta = _db.select(_db.tasks).join([
      innerJoin(_db.courses, _db.courses.id.equalsExp(_db.tasks.courseId)),
    ]);
    if (!incluirCompletadas) {
      consulta.where(_db.tasks.completada.equals(false));
    }
    consulta.orderBy([OrderingTerm.asc(_db.tasks.inicio)]);

    return consulta.watch().map(
      (filas) => [
        for (final fila in filas)
          (
            tarea: fila.readTable(_db.tasks),
            curso: fila.readTable(_db.courses),
          ),
      ],
    );
  }

  /// Crea una tarea y devuelve su id.
  Future<int> crear(TasksCompanion tarea) {
    return _db.into(_db.tasks).insert(tarea);
  }

  Future<void> actualizar(Task tarea) {
    return _db.update(_db.tasks).replace(tarea);
  }

  Future<void> marcarCompletada(int id, {required bool completada}) {
    return (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(completada: Value(completada)),
    );
  }

  Future<void> borrar(int id) {
    return (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
  }

  /// Vuelve a insertar una tarea borrada, con su mismo id. Lo usa el botón
  /// "Deshacer" después de borrar.
  Future<void> restaurar(Task tarea) {
    return _db.into(_db.tasks).insert(tarea);
  }
}
