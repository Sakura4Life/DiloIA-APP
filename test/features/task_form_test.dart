import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/core/formato.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/dictados_repository.dart';
import 'package:diloia_app/data/providers.dart';
import 'package:diloia_app/features/tasks/task_draft.dart';
import 'package:diloia_app/features/tasks/task_form_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    Intl.defaultLocale = 'es';
  });

  group('BorradorTarea', () {
    test('lista los campos obligatorios que faltan', () {
      expect(BorradorTarea().faltantes, ['curso', 'tipo', 'fecha', 'hora']);
      expect(BorradorTarea(courseId: 1, tipo: TipoActividad.examen).faltantes, [
        'fecha',
        'hora',
      ]);
    });

    test('el peso no es obligatorio', () {
      final borrador = BorradorTarea(
        courseId: 1,
        tipo: TipoActividad.entrega,
        fecha: DateTime(2026, 10, 6),
        hora: const TimeOfDay(hour: 16, minute: 0),
      );
      expect(borrador.estaCompleto, isTrue);
    });

    test('junta la fecha y la hora en un solo momento', () {
      final borrador = BorradorTarea(
        fecha: DateTime(2026, 10, 6),
        hora: const TimeOfDay(hour: 16, minute: 30),
      );
      expect(borrador.inicio, DateTime(2026, 10, 6, 16, 30));
      expect(BorradorTarea(fecha: DateTime(2026, 10, 6)).inicio, isNull);
    });
  });

  group('yaPaso', () {
    final ahora = DateTime(2026, 10, 4, 10, 0);

    BorradorTarea con(DateTime fecha, int hora) => BorradorTarea(
      fecha: fecha,
      hora: TimeOfDay(hour: hora, minute: 0),
    );

    test('rechaza una hora de hoy que ya pasó', () {
      expect(con(DateTime(2026, 10, 4), 8).yaPaso(ahora: ahora), isTrue);
      expect(con(DateTime(2026, 10, 4), 12).yaPaso(ahora: ahora), isFalse);
    });

    test('rechaza días pasados y acepta días futuros', () {
      expect(con(DateTime(2026, 10, 1), 12).yaPaso(ahora: ahora), isTrue);
      expect(con(DateTime(2026, 10, 9), 8).yaPaso(ahora: ahora), isFalse);
    });

    test('permite editar una tarea vencida sin cambiarle la fecha', () {
      final vencida = con(DateTime(2026, 10, 1), 12);
      expect(
        vencida.yaPaso(ahora: ahora, inicioOriginal: DateTime(2026, 10, 1, 12)),
        isFalse,
      );
    });
  });

  group('peso', () {
    test('acepta coma o punto decimal y vacío', () {
      expect(leerPeso('20'), 20);
      expect(leerPeso('12,5'), 12.5);
      expect(leerPeso('12.5'), 12.5);
      expect(leerPeso('  '), isNull);
    });

    test('valida que esté entre 0 y 100', () {
      expect(validarPeso(''), isNull);
      expect(validarPeso('20'), isNull);
      expect(validarPeso('100'), isNull);
      expect(validarPeso('101'), isNotNull);
      expect(validarPeso('-1'), isNotNull);
      expect(validarPeso('veinte'), isNotNull);
    });
  });

  group('pantalla del formulario', () {
    late AppDatabase db;
    late int curso;

    setUp(() async {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      curso = await db
          .into(db.courses)
          .insert(CoursesCompanion.insert(nombre: 'Física', color: 0xFF4F46E5));
    });

    /// Abre una pantalla con un botón que lleva al formulario, para poder
    /// probar el "atrás".
    Future<void> abrir(
      WidgetTester tester, {
      BorradorTarea? borrador,
      DesdeDictado? dictado,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictadosRepositoryProvider.overrideWithValue(
              DictadosRepository(db, borrarArchivo: (_) async {}),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TaskFormScreen(borrador: borrador, dictado: dictado),
                  ),
                ),
                child: const Text('Inicio'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Inicio'));
      await tester.pumpAndSettle();
    }

    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    }

    testWidgets('guarda un borrador completo (el camino que usará la voz)', (
      tester,
    ) async {
      final enCincoDias = DateTime.now().add(const Duration(days: 5));
      final dia = DateTime(
        enCincoDias.year,
        enCincoDias.month,
        enCincoDias.day,
      );
      await abrir(
        tester,
        borrador: BorradorTarea(
          courseId: curso,
          tipo: TipoActividad.examen,
          fecha: dia,
          hora: const TimeOfDay(hour: 8, minute: 0),
          peso: 30,
        ),
      );

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final guardadas = await db.select(db.tasks).get();
      expect(guardadas, hasLength(1));
      expect(guardadas.single.tipo, TipoActividad.examen);
      expect(guardadas.single.inicio, dia.add(const Duration(hours: 8)));
      expect(guardadas.single.duracionMinutos, 120);
      expect(guardadas.single.pesoPorcentaje, 30);
      // Volvió a la pantalla anterior.
      expect(find.text('Inicio'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el selector de hora se abre y devuelve la hora elegida', (
      tester,
    ) async {
      final enCincoDias = DateTime.now().add(const Duration(days: 5));
      await abrir(
        tester,
        borrador: BorradorTarea(
          fecha: DateTime(enCincoDias.year, enCincoDias.month, enCincoDias.day),
        ),
      );

      await tester.tap(find.text('Hora'));
      await tester.pumpAndSettle();
      expect(find.text('Elegir hora'), findsOneWidget);
      expect(find.textContaining('Faltan'), findsOneWidget);

      // Sin mover las ruedas, acepta la hora inicial: 8:00 a. m.
      await tester.tap(find.byTooltip('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.text(textoHora(DateTime(2000, 1, 1, 8))), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('no guarda una fecha que ya pasó', (tester) async {
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      await abrir(
        tester,
        borrador: BorradorTarea(
          courseId: curso,
          tipo: TipoActividad.entrega,
          fecha: DateTime(ayer.year, ayer.month, ayer.day),
          hora: const TimeOfDay(hour: 8, minute: 0),
        ),
      );

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Esa fecha y hora ya pasaron'), findsOneWidget);
      expect(await db.select(db.tasks).get(), isEmpty);
      await cerrar(tester);
    });

    /// Simula el botón "atrás" del teléfono (no la flecha de la pantalla).
    Future<void> atrasDelTelefono(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('sin datos, el botón atrás sale sin preguntar', (tester) async {
      await abrir(tester);

      await atrasDelTelefono(tester);

      expect(find.text('Inicio'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('con una sola letra escrita, pregunta antes de salir', (
      tester,
    ) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextFormField).first, 'L');
      await tester.pump();

      await atrasDelTelefono(tester);
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);

      // "Seguir editando" se queda en el formulario con lo escrito.
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva tarea'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);

      // La flecha de arriba también pregunta, y "Descartar" sale.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsOneWidget);
      await cerrar(tester);
    });

    group('tarjeta de un dictado', () {
      late int dictado;

      setUp(() async {
        dictado = await db
            .into(db.dictados)
            .insert(
              DictadosCompanion.insert(
                rutaAudio: 'a.wav',
                grabadoEn: DateTime.now(),
                estado: EstadoDictado.listo,
              ),
            );
      });

      DateTime enCincoDias() {
        final dia = DateTime.now().add(const Duration(days: 5));
        return DateTime(dia.year, dia.month, dia.day);
      }

      testWidgets('muestra lo que entendió la IA', (tester) async {
        await abrir(
          tester,
          borrador: BorradorTarea(courseId: curso, tipo: TipoActividad.examen),
          dictado: DesdeDictado(
            id: dictado,
            transcripcion: 'examen de física el viernes',
          ),
        );

        expect(find.text('Revisar dictado'), findsOneWidget);
        expect(
          find.text('Entendí: «examen de física el viernes»'),
          findsOneWidget,
        );
        await cerrar(tester);
      });

      testWidgets('al guardar, el dictado sale de la cola', (tester) async {
        await abrir(
          tester,
          borrador: BorradorTarea(
            courseId: curso,
            tipo: TipoActividad.examen,
            fecha: enCincoDias(),
            hora: const TimeOfDay(hour: 8, minute: 0),
          ),
          dictado: DesdeDictado(id: dictado, transcripcion: 'x'),
        );

        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        expect(await db.select(db.tasks).get(), hasLength(1));
        expect(await db.select(db.dictados).get(), isEmpty);
        await cerrar(tester);
      });

      testWidgets('salir sin cambios no pregunta y conserva el dictado', (
        tester,
      ) async {
        await abrir(
          tester,
          borrador: BorradorTarea(courseId: curso, tipo: TipoActividad.examen),
          dictado: DesdeDictado(id: dictado, transcripcion: 'x'),
        );

        await atrasDelTelefono(tester);

        expect(find.text('Inicio'), findsOneWidget);
        expect(await db.select(db.dictados).get(), hasLength(1));
        await cerrar(tester);
      });

      testWidgets('ofrece crear el curso dictado con su nombre ya escrito', (
        tester,
      ) async {
        await abrir(
          tester,
          borrador: BorradorTarea(tipo: TipoActividad.exposicion),
          dictado: DesdeDictado(
            id: dictado,
            transcripcion: 'exposición de historia',
            materiaNueva: 'Historia',
          ),
        );
        expect(
          find.textContaining('El curso «Historia» no existe'),
          findsOneWidget,
        );

        await tester.tap(find.text('Crear curso'));
        await tester.pumpAndSettle();
        // Es un curso nuevo, con el nombre dictado ya escrito.
        expect(find.text('Nuevo curso'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Historia'), findsOneWidget);
        await tester.tap(find.text('Guardar').last);
        await tester.pumpAndSettle();

        // El curso quedó elegido y el aviso desaparece.
        final cursos = await db.select(db.courses).get();
        expect(cursos.map((c) => c.nombre), contains('Historia'));
        expect(find.textContaining('no existe'), findsNothing);
        await cerrar(tester);
      });
    });
  });
}
