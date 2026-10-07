import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/constants.dart';

// Este archivo lo escribe `dart run build_runner build` a partir de las tablas
// de abajo. No se edita a mano.
part 'database.g.dart';

/// Cursos del estudiante. Drift genera la clase `Course` para cada fila.
class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 60)();

  /// Color en formato ARGB (el número que devuelve `Color.toARGB32()`).
  IntColumn get color => integer()();

  /// Posición en la lista, elegida por el usuario al arrastrar los cursos.
  /// Agregado en la versión 3 del esquema.
  IntColumn get orden => integer().withDefault(const Constant(0))();
}

/// Tareas académicas. Drift genera la clase `Task` para cada fila.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Si se borra el curso, se borran también sus tareas.
  IntColumn get courseId =>
      integer().references(Courses, #id, onDelete: KeyAction.cascade)();

  /// Se guarda como texto ("entrega", "examen"…), igual que en el JSON de la IA.
  TextColumn get tipo => textEnum<TipoActividad>()();

  /// Nombre corto opcional para distinguir tareas del mismo curso y tipo, por
  /// ejemplo "Laboratorio 3". Agregado en la versión 2 del esquema.
  TextColumn get titulo => text().withLength(max: 80).nullable()();

  /// Fecha y hora de la entrega o del inicio del examen.
  DateTimeColumn get inicio => dateTime()();
  IntColumn get duracionMinutos => integer()();

  /// Porcentaje de la nota. Es opcional: no siempre se sabe cuánto vale.
  RealColumn get pesoPorcentaje => real().nullable()();
  BoolColumn get completada => boolean().withDefault(const Constant(false))();
}

/// Dictados por voz que todavía no son tareas: esperan internet, esperan que
/// el usuario revise la tarjeta, o la IA no los entendió. Drift genera la
/// clase `Dictado` para cada fila. Agregada en la versión 4 del esquema.
@DataClassName('Dictado')
class Dictados extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Archivo WAV en la carpeta de la app. Se borra junto con la fila.
  TextColumn get rutaAudio => text()();

  /// Cuándo se grabó. Se envía a la IA como "hoy", para que "mañana" se
  /// entienda respecto al día en que se habló y no al día en que se procesa.
  DateTimeColumn get grabadoEn => dateTime()();

  TextColumn get estado => textEnum<EstadoDictado>()();

  /// Lo que respondió la IA, tal cual (JSON). Solo cuando el estado es `listo`.
  TextColumn get resultado => text().nullable()();

  /// Mensaje para el usuario si algo salió mal, por ejemplo "Sin conexión".
  TextColumn get mensaje => text().nullable()();
}

@DriftDatabase(tables: [Courses, Tasks, Dictados])
class AppDatabase extends _$AppDatabase {
  /// Recibe la conexión desde fuera: las pruebas le pasan una base en memoria.
  AppDatabase(super.e);

  /// Base real del celular, guardada en el archivo `diloia.sqlite`.
  AppDatabase.defaults() : super(driftDatabase(name: 'diloia'));

  /// Subir este número cada vez que cambien las tablas, y agregar la migración.
  ///
  /// Historial:
  /// - 1: tablas Courses y Tasks.
  /// - 2: columna `titulo` en Tasks.
  /// - 3: columna `orden` en Courses.
  /// - 4: tabla Dictados (cola de dictados por voz).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Instalación nueva: crea todas las tablas ya en su última versión.
    onCreate: (m) => m.createAll(),
    // Actualización: lleva una base vieja del celular hasta la versión actual,
    // paso a paso, sin borrar los datos que ya tenía.
    onUpgrade: (m, desde, hasta) async {
      if (desde < 2) await m.addColumn(tasks, tasks.titulo);
      if (desde < 3) {
        await m.addColumn(courses, courses.orden);
        await _ordenarCursosAlfabeticamente();
      }
      if (desde < 4) await m.createTable(dictados);
    },
    beforeOpen: (details) async {
      // SQLite trae las relaciones entre tablas apagadas por defecto. Sin esto,
      // borrar un curso dejaría sus tareas huérfanas.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Antes de la versión 3 los cursos se mostraban en orden alfabético. Al
  /// migrar se guarda ese mismo orden, para que no cambien de lugar solos.
  Future<void> _ordenarCursosAlfabeticamente() async {
    final filas = await customSelect('SELECT id, nombre FROM courses').get();
    final cursos = [
      for (final fila in filas)
        (id: fila.read<int>('id'), nombre: fila.read<String>('nombre')),
    ]..sort((a, b) => claveDeOrden(a.nombre).compareTo(claveDeOrden(b.nombre)));
    for (var i = 0; i < cursos.length; i++) {
      await customUpdate(
        'UPDATE courses SET orden = ? WHERE id = ?',
        variables: [Variable.withInt(i), Variable.withInt(cursos[i].id)],
      );
    }
  }
}

/// Versión del nombre para ordenar y comparar: minúsculas y sin tildes, así
/// "Álgebra", "algebra" y "ALGEBRA" se tratan igual.
String claveDeOrden(String nombre) {
  const conTilde = 'áéíóúüñ';
  const sinTilde = 'aeiouun';
  final minusculas = nombre.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final letra in minusculas.split('')) {
    final i = conTilde.indexOf(letra);
    buffer.write(i == -1 ? letra : sinTilde[i]);
  }
  return buffer.toString();
}
