import 'dart:convert';

import 'package:diloia_app/app.dart';
import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/core/formato.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/dictados_repository.dart';
import 'package:diloia_app/data/providers.dart';
import 'package:diloia_app/features/voice/providers_voz.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'ayudantes.dart';

void main() {
  late AppDatabase db;
  late GrabadoraFalsa microfono;

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
    microfono = GrabadoraFalsa();
  });

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // Sin disco: borrar un dictado no toca archivos.
          dictadosRepositoryProvider.overrideWithValue(
            DictadosRepository(db, borrarArchivo: (_) async {}),
          ),
          // Sin red: así la cola no intenta llamar a la IA de verdad.
          conectividadProvider.overrideWithValue(ConectividadFalsa()),
          // Sin micrófono de verdad.
          grabadoraProvider.overrideWithValue(microfono),
        ],
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

    expect(find.text('Sin pendientes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Cambiar filtro'),
        matching: find.text('Pendientes'),
      ),
      findsOneWidget,
    );
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

  group('grabación al estilo WhatsApp', () {
    /// Toca el micrófono una vez (sin mantenerlo presionado).
    Future<void> empezarAGrabar(WidgetTester tester) async {
      await abrirApp(tester);
      await tester.tap(find.byTooltip('Dictar una tarea'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('un toque abre el panel con el límite de 30 s', (tester) async {
      await empezarAGrabar(tester);

      expect(microfono.acciones, ['empezar']);
      expect(find.text('0:00 / 0:30'), findsOneWidget);
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.byTooltip('Descartar'), findsOneWidget);
      expect(find.byTooltip('Enviar'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el contador avanza y la pausa lo detiene', (tester) async {
      await empezarAGrabar(tester);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:03 / 0:30'), findsOneWidget);

      await tester.tap(find.text('Pausar'));
      await tester.pump();
      expect(find.text('Continuar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:03 / 0:30'), findsOneWidget);

      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(microfono.acciones, ['empezar', 'pausar', 'reanudar']);
      expect(find.text('Pausar'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('a los 30 s se pausa sola y solo deja enviar o descartar', (
      tester,
    ) async {
      await empezarAGrabar(tester);

      await tester.pump(const Duration(seconds: 31));

      expect(find.text('0:30 / 0:30'), findsOneWidget);
      expect(find.textContaining('Llegaste al límite'), findsOneWidget);
      expect(microfono.acciones.last, 'pausar');
      final continuar = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Continuar'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(continuar.onPressed, isNull);
      await cerrar(tester);
    });

    testWidgets('descartar cierra el panel sin guardar nada', (tester) async {
      await empezarAGrabar(tester);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Descartar'));
      await tester.pumpAndSettle();

      expect(microfono.acciones.last, 'cancelar');
      expect(find.byTooltip('Dictar una tarea'), findsOneWidget);
      expect(await db.select(db.dictados).get(), isEmpty);
      await cerrar(tester);
    });

    testWidgets('enviar sin internet guarda el dictado en la cola', (
      tester,
    ) async {
      await empezarAGrabar(tester);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(microfono.acciones.last, 'terminar');
      expect(
        find.textContaining('Sin conexión. Guardé tu dictado'),
        findsOneWidget,
      );
      final cola = await db.select(db.dictados).get();
      expect(cola.single.rutaAudio, 'falso.wav');
      await cerrar(tester);
    });

    testWidgets('una grabación de menos de 1 s se descarta', (tester) async {
      await empezarAGrabar(tester);

      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(microfono.acciones.last, 'cancelar');
      expect(find.textContaining('muy corta'), findsOneWidget);
      expect(await db.select(db.dictados).get(), isEmpty);
      await cerrar(tester);
    });

    testWidgets('sin permiso explica cómo activarlo', (tester) async {
      microfono.permiso = false;
      await abrirApp(tester);

      await tester.tap(find.byTooltip('Dictar una tarea'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de micrófono'), findsOneWidget);
      expect(microfono.acciones, isEmpty);
      await cerrar(tester);
    });
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

  testWidgets('con título, título y curso van arriba y el tipo abajo', (
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

    expect(find.text('Laboratorio 3 · Física'), findsOneWidget);
    expect(find.text('Entrega · ${cuatroPm()}'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('un título y un curso largos caben en dos líneas con «…»', (
    tester,
  ) async {
    final curso = await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            nombre: 'Laboratorio de realidad extendida para videojuegos',
            color: 0xFF4F46E5,
          ),
        );
    final manana = DateTime.now().add(const Duration(days: 1));
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            courseId: curso,
            tipo: TipoActividad.examen,
            titulo: const Value('Examen de laboratorio'),
            inicio: DateTime(manana.year, manana.month, manana.day, 16),
            duracionMinutos: 120,
          ),
        );
    // Ancho de un celular angosto.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await abrirApp(tester);

    final linea = tester.widget<Text>(
      find.textContaining('Examen de laboratorio · Laboratorio'),
    );
    expect(linea.maxLines, 2);
    expect(linea.overflow, TextOverflow.ellipsis);
    // Sin desbordes (Flutter avisaría con una excepción).
    expect(tester.takeException(), isNull);
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

  testWidgets('en "Todas", marcar la deja visible, tachada y con check', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);
    await siguienteFiltro(tester, 'Pendientes'); // → Completadas
    await siguienteFiltro(tester, 'Completadas'); // → Pasadas
    await siguienteFiltro(tester, 'Pasadas'); // → Todas

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    final titulo = tester.widget<Text>(find.text('Entrega · Física'));
    expect(titulo.style?.decoration, TextDecoration.lineThrough);
    // Sigue en la lista, así que no hace falta "Deshacer".
    expect(find.text('Deshacer'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('en "Pendientes", completar la anima fuera y se puede deshacer', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await abrirApp(tester);

    await tester.tap(find.byType(Checkbox));
    // Primero se ve con el check, todavía en su lugar.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    // Al terminar la animación ya no está, y aparece el aviso.
    await tester.pumpAndSettle();
    expect(find.text('Entrega · Física'), findsNothing);
    expect(find.text('Tarea completada'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega · Física'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await cerrar(tester);
  });

  testWidgets('en "Completadas", desmarcar también la saca de la lista', (
    tester,
  ) async {
    await crearTareaDeFisica();
    await (db.update(db.tasks))
        .write(const TasksCompanion(completada: Value(true)));
    await abrirApp(tester);
    await siguienteFiltro(tester, 'Pendientes'); // → Completadas
    expect(find.text('Entrega · Física'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('Entrega · Física'), findsNothing);
    expect(find.text('Tarea marcada como pendiente'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets(
    'las vencidas sin marcar no salen en Pendientes sino en Pasadas',
    (tester) async {
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
      // Pendientes: solo la de mañana.
      expect(find.text('Parcial · Física'), findsNothing);
      expect(find.text('Entrega · Física'), findsOneWidget);

      await siguienteFiltro(tester, 'Pendientes'); // → Completadas
      await siguienteFiltro(tester, 'Completadas'); // → Pasadas

      expect(find.text('Parcial · Física'), findsOneWidget);
      expect(find.text('Entrega · Física'), findsNothing);

      await siguienteFiltro(tester, 'Pasadas'); // → Todas
      expect(find.text('Parcial · Física'), findsOneWidget);
      expect(find.text('Entrega · Física'), findsOneWidget);
      await cerrar(tester);
    },
  );

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

  group('Por revisar', () {
    Future<void> crearDictados() async {
      await db
          .into(db.dictados)
          .insert(
            DictadosCompanion.insert(
              rutaAudio: 'no_existe_1.wav',
              grabadoEn: DateTime.now(),
              estado: EstadoDictado.esperando,
              mensaje: const Value('Sin conexión con el servicio de IA.'),
            ),
          );
      await db
          .into(db.dictados)
          .insert(
            DictadosCompanion.insert(
              rutaAudio: 'no_existe_2.wav',
              grabadoEn: DateTime.now(),
              estado: EstadoDictado.listo,
              resultado: Value(
                jsonEncode({
                  'transcripcion': 'exposición de historia el viernes',
                  'tipo': 'exposicion',
                  'materia': 'Historia',
                }),
              ),
            ),
          );
    }

    testWidgets('sin dictados no se muestra el aviso', (tester) async {
      await abrirApp(tester);

      expect(find.textContaining('por revisar'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('el aviso cuenta los dictados y abre la lista', (tester) async {
      await crearDictados();
      await abrirApp(tester);

      expect(find.text('2 dictados por revisar'), findsOneWidget);
      expect(find.text('1 listo · 1 esperando conexión'), findsOneWidget);

      await tester.tap(find.text('2 dictados por revisar'));
      await tester.pumpAndSettle();
      expect(find.text('«exposición de historia el viernes»'), findsOneWidget);
      expect(find.text('Sin conexión con el servicio de IA.'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('un dictado listo abre la tarjeta con lo que entendió la IA', (
      tester,
    ) async {
      await crearDictados();
      await abrirApp(tester);
      await tester.tap(find.text('2 dictados por revisar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('«exposición de historia el viernes»'));
      // Antes de abrir la tarjeta se leen los cursos de la base; mientras
      // tanto no hay animación, así que se avanza el reloj a mano.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Revisar dictado'), findsOneWidget);
      expect(
        find.text('Entendí: «exposición de historia el viernes»'),
        findsOneWidget,
      );
      // "Historia" no está entre los cursos: ofrece crearlo.
      expect(
        find.textContaining('El curso «Historia» no existe'),
        findsOneWidget,
      );
      await cerrar(tester);
    });

    testWidgets('descartar pide confirmación y borra el dictado', (
      tester,
    ) async {
      await crearDictados();
      await abrirApp(tester);
      await tester.tap(find.text('2 dictados por revisar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Opciones').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar este dictado?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await tester.pumpAndSettle();

      expect(await db.select(db.dictados).get(), hasLength(1));
      await cerrar(tester);
    });
  });
}
