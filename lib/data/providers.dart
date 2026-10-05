import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'courses_repository.dart';
import 'database.dart';
import 'tasks_repository.dart';

/// La base de datos de la app. Se abre una sola vez y se comparte. Las pruebas
/// la reemplazan por una base en memoria con `overrideWithValue`.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.defaults();
  ref.onDispose(db.close);
  return db;
});

final coursesRepositoryProvider = Provider<CoursesRepository>(
  (ref) => CoursesRepository(ref.watch(databaseProvider)),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(databaseProvider)),
);

/// Cursos en orden alfabético, siempre al día.
final cursosProvider = StreamProvider<List<Course>>(
  (ref) => ref.watch(coursesRepositoryProvider).watchTodos(),
);

/// Todas las tareas con su curso, completadas incluidas. La pantalla filtra.
///
/// Es una sola lista a propósito: con una lista distinta para "pendientes" y
/// otra para "completadas", Riverpod pausa la que no se ve y, al cambiar el
/// filtro, mostraba por un instante datos viejos (por ejemplo, una tarea ya
/// borrada que aparecía y desaparecía).
final tareasProvider = StreamProvider<List<TareaConCurso>>(
  (ref) =>
      ref.watch(tasksRepositoryProvider).watchTareas(incluirCompletadas: true),
);
