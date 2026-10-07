import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/data/courses_repository.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/dictados_repository.dart';
import 'package:diloia_app/data/tasks_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CoursesRepository cursos;
  late TasksRepository tareas;

  setUp(() {
    // Base nueva y vacía en memoria para cada prueba: no toca el celular.
    db = AppDatabase(NativeDatabase.memory());
    cursos = CoursesRepository(db);
    tareas = TasksRepository(db);
  });

  tearDown(() => db.close());

  Future<int> crearTarea(
    int courseId, {
    required DateTime inicio,
    TipoActividad tipo = TipoActividad.entrega,
    double? peso,
  }) {
    return tareas.crear(
      TasksCompanion.insert(
        courseId: courseId,
        tipo: tipo,
        inicio: inicio,
        duracionMinutos: tipo.duracionPorDefecto.inMinutes,
        pesoPorcentaje: Value(peso),
      ),
    );
  }

  test('guarda una tarea y la devuelve junto con su curso', () async {
    final fisica = await cursos.crear(nombre: 'Física', color: 0xFF4F46E5);
    await crearTarea(fisica, inicio: DateTime(2026, 10, 6, 16), peso: 20);

    final lista = await tareas.watchTareas(incluirCompletadas: false).first;

    expect(lista, hasLength(1));
    expect(lista.single.curso.nombre, 'Física');
    expect(lista.single.tarea.tipo, TipoActividad.entrega);
    expect(lista.single.tarea.inicio, DateTime(2026, 10, 6, 16));
    expect(lista.single.tarea.pesoPorcentaje, 20);
    expect(lista.single.tarea.completada, isFalse);
  });

  test('guarda el título opcional', () async {
    final curso = await cursos.crear(nombre: 'Física', color: 0xFF4F46E5);
    await tareas.crear(
      TasksCompanion.insert(
        courseId: curso,
        tipo: TipoActividad.entrega,
        titulo: const Value('Laboratorio 3'),
        inicio: DateTime(2026, 10, 6, 16),
        duracionMinutos: 60,
      ),
    );

    final lista = await tareas.watchTareas(incluirCompletadas: false).first;

    expect(lista.single.tarea.titulo, 'Laboratorio 3');
  });

  test('migra una base de la versión 1 sin perder sus datos', () async {
    // Simula la base que ya existe en un celular con la versión anterior:
    // mismas tablas pero sin la columna `titulo`, y con una tarea guardada.
    final vieja = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE courses (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, nombre TEXT NOT NULL, color INTEGER NOT NULL);',
          );
          sqlite.execute(
            'CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, course_id INTEGER NOT NULL REFERENCES courses (id) '
            'ON DELETE CASCADE, tipo TEXT NOT NULL, inicio INTEGER NOT NULL, '
            'duracion_minutos INTEGER NOT NULL, peso_porcentaje REAL NULL, '
            'completada INTEGER NOT NULL DEFAULT 0);',
          );
          sqlite.execute(
            "INSERT INTO courses (nombre, color) VALUES ('Física', 1);",
          );
          sqlite.execute(
            'INSERT INTO tasks (course_id, tipo, inicio, duracion_minutos) '
            "VALUES (1, 'examen', 1791300000, 120);",
          );
          sqlite.execute('PRAGMA user_version = 1;');
        },
      ),
    );
    addTearDown(vieja.close);

    final lista = await TasksRepository(vieja)
        .watchTareas(incluirCompletadas: true)
        .first;

    expect(lista, hasLength(1));
    expect(lista.single.tarea.tipo, TipoActividad.examen);
    expect(lista.single.tarea.titulo, isNull);
    expect(lista.single.curso.nombre, 'Física');
  });

  test('las tareas salen ordenadas por fecha', () async {
    final curso = await cursos.crear(nombre: 'Cálculo', color: 0xFF000000);
    await crearTarea(curso, inicio: DateTime(2026, 10, 9));
    await crearTarea(curso, inicio: DateTime(2026, 10, 7));
    await crearTarea(curso, inicio: DateTime(2026, 10, 8));

    final lista = await tareas.watchTareas(incluirCompletadas: true).first;

    expect(lista.map((t) => t.tarea.inicio.day), [7, 8, 9]);
  });

  test('las completadas se ocultan salvo que se pidan', () async {
    final curso = await cursos.crear(nombre: 'Química', color: 0xFF000000);
    final id = await crearTarea(curso, inicio: DateTime(2026, 10, 6));

    await tareas.marcarCompletada(id, completada: true);

    expect(await tareas.watchTareas(incluirCompletadas: false).first, isEmpty);
    expect(
      await tareas.watchTareas(incluirCompletadas: true).first,
      hasLength(1),
    );
  });

  test('borrar un curso borra también sus tareas', () async {
    final curso = await cursos.crear(nombre: 'Historia', color: 0xFF000000);
    await crearTarea(curso, inicio: DateTime(2026, 10, 6));
    await crearTarea(curso, inicio: DateTime(2026, 10, 7));
    expect(await cursos.contarTareas(curso), 2);

    await cursos.borrar(curso);

    expect(await tareas.watchTareas(incluirCompletadas: true).first, isEmpty);
  });

  test('una tarea borrada se puede restaurar con su mismo id', () async {
    final curso = await cursos.crear(nombre: 'Arte', color: 0xFF000000);
    final id = await crearTarea(curso, inicio: DateTime(2026, 10, 6));
    final antes = await tareas.watchTareas(incluirCompletadas: true).first;

    await tareas.borrar(id);
    await tareas.restaurar(antes.single.tarea);

    final despues = await tareas.watchTareas(incluirCompletadas: true).first;
    expect(despues.single.tarea, antes.single.tarea);
  });

  test('un curso nuevo se agrega al inicio de la lista', () async {
    await cursos.crear(nombre: 'Química', color: 0xFF000000);
    await cursos.crear(nombre: 'Álgebra', color: 0xFF000000);
    await cursos.crear(nombre: 'Física', color: 0xFF000000);

    final lista = await cursos.watchTodos().first;

    expect(lista.map((c) => c.nombre), ['Física', 'Álgebra', 'Química']);
  });

  test('reordenar guarda el orden elegido por el usuario', () async {
    final quimica = await cursos.crear(nombre: 'Química', color: 0xFF000000);
    final algebra = await cursos.crear(nombre: 'Álgebra', color: 0xFF000000);
    final fisica = await cursos.crear(nombre: 'Física', color: 0xFF000000);

    await cursos.reordenar([quimica, fisica, algebra]);

    final lista = await cursos.watchTodos().first;
    expect(lista.map((c) => c.nombre), ['Química', 'Física', 'Álgebra']);

    // Un curso creado después aparece arriba, sin desordenar los demás.
    await cursos.crear(nombre: 'Arte', color: 0xFF000000);
    final conNuevo = await cursos.watchTodos().first;
    expect(conNuevo.map((c) => c.nombre), [
      'Arte',
      'Química',
      'Física',
      'Álgebra',
    ]);
  });

  test('migra la versión 2 conservando el orden alfabético de antes', () async {
    // En la versión 2 los cursos se mostraban en orden alfabético y no había
    // columna `orden`. Al migrar no deben cambiar de lugar.
    final vieja = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE courses (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, nombre TEXT NOT NULL, color INTEGER NOT NULL);',
          );
          sqlite.execute(
            'CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, course_id INTEGER NOT NULL REFERENCES courses (id) '
            'ON DELETE CASCADE, tipo TEXT NOT NULL, titulo TEXT NULL, '
            'inicio INTEGER NOT NULL, duracion_minutos INTEGER NOT NULL, '
            'peso_porcentaje REAL NULL, completada INTEGER NOT NULL DEFAULT 0);',
          );
          // Creados en desorden; antes se veían Álgebra, ética, Química.
          sqlite.execute(
            'INSERT INTO courses (nombre, color) VALUES '
            "('Química', 1), ('ética', 1), ('Álgebra', 1);",
          );
          sqlite.execute('PRAGMA user_version = 2;');
        },
      ),
    );
    addTearDown(vieja.close);

    final lista = await CoursesRepository(vieja).watchTodos().first;

    expect(lista.map((c) => c.nombre), ['Álgebra', 'ética', 'Química']);
  });

  test('migra la versión 3 agregando la cola de dictados', () async {
    final vieja = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE courses (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, nombre TEXT NOT NULL, color INTEGER NOT NULL, '
            'orden INTEGER NOT NULL DEFAULT 0);',
          );
          sqlite.execute(
            'CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, course_id INTEGER NOT NULL REFERENCES courses (id) '
            'ON DELETE CASCADE, tipo TEXT NOT NULL, titulo TEXT NULL, '
            'inicio INTEGER NOT NULL, duracion_minutos INTEGER NOT NULL, '
            'peso_porcentaje REAL NULL, completada INTEGER NOT NULL DEFAULT 0);',
          );
          sqlite.execute(
            "INSERT INTO courses (nombre, color, orden) VALUES ('Física', 1, 0);",
          );
          sqlite.execute('PRAGMA user_version = 3;');
        },
      ),
    );
    addTearDown(vieja.close);

    final repo = DictadosRepository(vieja, borrarArchivo: (_) async {});
    final id = await repo.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime(2026, 10, 6),
    );

    expect((await repo.obtener(id))!.estado, EstadoDictado.esperando);
    // Los cursos de antes siguen ahí.
    final lista = await CoursesRepository(vieja).watchTodos().first;
    expect(lista.single.nombre, 'Física');
  });

  test('claveDeOrden ignora tildes, mayúsculas y espacios', () {
    expect(claveDeOrden('  Álgebra '), 'algebra');
    expect(claveDeOrden('ESPAÑOL'), 'espanol');
  });
}
