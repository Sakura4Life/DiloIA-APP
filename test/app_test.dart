import 'package:diloia_app/app.dart';
import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/core/formato.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/providers.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  late AppDatabase db;

  // "4:00 p. m." tal como lo escribe la app (intl usa espacios especiales).
  // Es una función porque el español se carga recién en setUpAll.
  String cuatroPm() => textoHora(DateTime(2000, 1, 1, 16));

  setUpAll(() async {
    await initializeDateFormatting('es');
    Intl.defaultLocale = 'es';
  });

  setUp(() {
    // closeStreamsSynchronously evita que queden temporizadores de Drift
    // pendientes al terminar cada prueba de pantalla.
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const DiloIAApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Desmonta la app antes de cerrar la base, para no cortar streams activos.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  Future<void> crearTareaDeFisica() async {
    final curso = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(nombre: 'Física', color: 0xFF4F46E5));
    final manana = DateTime.now().add(const Duration(days: 1));
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            courseId: curso,
            tipo: TipoActividad.entrega,
            inicio: DateTime(manana.year, manana.month, manana.day, 16),
            duracionMinutos: 60,
            pesoPorcentaje: const Value(20),
          ),
        );
  }

  testWidgets('arranca en Pendientes con el botón de voz', (tester) async {
    await abrirApp(tester);

    expect(find.text('Sin tareas'), findsOneWidget);
    expect(find.text('Todas'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('la barra inferior cambia de pestaña', (tester) async {
    await abrirApp(tester);

    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    expect(find.text('Tu mes de un vistazo'), findsOneWidget);

    await tester.tap(find.text('Panel'));
    await tester.pumpAndSettle();
    expect(find.text('Carga semanal'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('un toque corto explica que hay que mantener presionado', (
    tester,
  ) async {
    await abrirApp(tester);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.text('Mantén presionado para dictar.'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('una tarea guardada aparece agrupada bajo "Mañana"', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);

    expect(find.text('Mañana'), findsOneWidget);
    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(find.text('${cuatroPm()} · 20% de la nota'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('con título, el título va arriba y tipo y curso abajo', (
    tester,
  ) async {
    final curso = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(nombre: 'Física', color: 0xFF4F46E5));
    final manana = DateTime.now().add(const Duration(days: 1));
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            courseId: curso,
            tipo: TipoActividad.entrega,
            titulo: const Value('Laboratorio 3'),
            inicio: DateTime(manana.year, manana.month, manana.day, 16),
            duracionMinutos: 60,
          ),
        );
    await abrirApp(tester);

    expect(find.text('Laboratorio 3'), findsOneWidget);
    expect(find.text('Entrega · Física · ${cuatroPm()}'), findsOneWidget);
    await cerrar(tester);
  });

  /// Toca el botón de filtro, que muestra el nombre del filtro [actual].
  /// ("Pendientes" también es el nombre de la pestaña, por eso se busca el
  /// botón por su descripción y no por su texto.)
  Future<void> siguienteFiltro(WidgetTester tester, String actual) async {
    final boton = find.byTooltip('Cambiar filtro');
    expect(
      find.descendant(of: boton, matching: find.text(actual)),
      findsOneWidget,
    );
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  testWidgets('marcar una tarea la deja visible, tachada y con check', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    final titulo = tester.widget<Text>(find.text('Entrega · Física'));
    expect(titulo.style?.decoration, TextDecoration.lineThrough);
    await cerrar(tester);
  });

  testWidgets('en "Pendientes", marcar no la oculta hasta cambiar de filtro', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);
    await siguienteFiltro(tester, 'Todas'); // → Pendientes

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Entrega · Física'), findsOneWidget);

    await siguienteFiltro(tester, 'Pendientes'); // → Completadas
    expect(find.text('Entrega · Física'), findsOneWidget);
    await siguienteFiltro(tester, 'Completadas'); // → Pasadas
    expect(find.text('Sin tareas pasadas'), findsOneWidget);
    await siguienteFiltro(tester, 'Pasadas'); // → Todas (vuelve a empezar)
    expect(find.text('Entrega · Física'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('"Pasadas" muestra solo las tareas cuya fecha ya pasó', (
    tester,
  ) async {
    await crearTareaDeFisica(); // mañana
    final curso = (await db.select(db.courses).get()).single.id;
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            courseId: curso,
            tipo: TipoActividad.examen,
            titulo: const Value('Parcial'),
            inicio: DateTime.now().subtract(const Duration(days: 2)),
            duracionMinutos: 120,
          ),
        );
    await abrirApp(tester);
    expect(find.text('Parcial'), findsOneWidget);
    expect(find.text('Entrega · Física'), findsOneWidget);

    await siguienteFiltro(tester, 'Todas'); // → Pendientes
    await siguienteFiltro(tester, 'Pendientes'); // → Completadas
    await siguienteFiltro(tester, 'Completadas'); // → Pasadas

    expect(find.text('Parcial'), findsOneWidget);
    expect(find.text('Entrega · Física'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('deslizar pregunta antes de borrar; cancelar conserva la tarea', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);

    await tester.drag(find.text('Entrega · Física'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar esta tarea?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(await db.select(db.tasks).get(), hasLength(1));
    await cerrar(tester);
  });

  testWidgets('una tarea borrada no reaparece al cambiar de filtro', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);

    await tester.drag(find.text('Entrega · Física'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(await db.select(db.tasks).get(), isEmpty);

    // Antes aparecía un instante; se revisa cuadro por cuadro en cada filtro.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Cambiar filtro'));
      await tester.pump();
      expect(find.text('Entrega · Física'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Entrega · Física'), findsNothing);
    }
    await cerrar(tester);
  });

  testWidgets('el formulario no guarda si faltan datos obligatorios', (
    tester,
  ) async {
    await abrirApp(tester);

    await tester.tap(find.byTooltip('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // Sigue en el formulario y marca curso, fecha y hora como obligatorios.
    expect(find.text('Nueva tarea'), findsOneWidget);
    expect(find.text('Obligatorio'), findsNWidgets(3));
    expect(find.text('Tipo · Obligatorio'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('el botón de cursos crea un curso nuevo', (tester) async {
    await abrirApp(tester);

    await tester.tap(find.byTooltip('Cursos'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes cursos'), findsOneWidget);

    await tester.tap(find.text('Nuevo curso'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Cálculo II');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Cálculo II'), findsOneWidget);
    await cerrar(tester);
  });
}
