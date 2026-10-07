import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'courses_repository.dart';
import 'database.dart';
import 'dictados_repository.dart';
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

final dictadosRepositoryProvider = Provider<DictadosRepository>(
  (ref) => DictadosRepository(ref.watch(databaseProvider)),
);

/// Dictados por voz que todavía no son tareas, del más antiguo al más nuevo.
final dictadosProvider = StreamProvider<List<Dictado>>(
  (ref) => ref.watch(dictadosRepositoryProvider).watchTodos(),
);

/// Cursos en el orden elegido por el usuario, siempre al día.
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
