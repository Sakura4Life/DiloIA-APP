import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/data/courses_repository.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/dictados_repository.dart';
import 'package:diloia_app/features/voice/extraccion_api.dart';
import 'package:diloia_app/features/voice/procesador_dictados.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;
  late DictadosRepository dictados;
  late List<Map<String, dynamic>> peticiones;
  late List<Duration> pausas;

  /// Lo que responderá la función falsa en cada llamada, en orden.
  late List<FutureOr<http.Response> Function()> respuestas;

  // Como la función real: JSON en UTF-8, para que las tildes lleguen bien.
  http.Response ok(Map<String, dynamic> json) => http.Response(
    jsonEncode(json),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response sinRed() => throw http.ClientException('sin red');

  ProcesadorDictados crearProcesador({
    Future<Uint8List> Function(String)? leerAudio,
  }) {
    final api = ExtraccionApi(
      cliente: MockClient((peticion) async {
        peticiones.add(jsonDecode(peticion.body) as Map<String, dynamic>);
        return respuestas.removeAt(0)();
      }),
    );
    return ProcesadorDictados(
      dictados: dictados,
      cursos: CoursesRepository(db),
      api: api,
      leerAudio: leerAudio ?? (_) async => Uint8List.fromList([1, 2, 3]),
      esperar: (pausa) async => pausas.add(pausa),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Sin disco: borrar un audio no hace nada.
    dictados = DictadosRepository(db, borrarArchivo: (_) async {});
    peticiones = [];
    pausas = [];
    respuestas = [];
    await CoursesRepository(db).crear(nombre: 'Física I', color: 0);
  });

  tearDown(() => db.close());

  test('un dictado entendido queda listo con la respuesta de la IA', () async {
    final id = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime.now(),
    );
    respuestas.add(
      () => ok({'transcripcion': 'examen de física', 'tipo': 'examen'}),
    );

    final dictado = await crearProcesador().procesar(id);

    expect(dictado!.estado, EstadoDictado.listo);
    final guardado = jsonDecode(dictado.resultado!) as Map<String, dynamic>;
    expect(guardado['transcripcion'], 'examen de física');
    // Le pasa a la IA los cursos del estudiante.
    expect(peticiones.single['cursos'], ['Física I']);
  });

  test('envía la fecha en que se grabó, no la de hoy', () async {
    // Grabado el lunes 5 al mediodía (hora de Lima = UTC − 5).
    final id = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime.utc(2026, 10, 5, 17),
    );
    respuestas.add(() => ok({'transcripcion': 'x', 'tipo': 'otro'}));

    await crearProcesador().procesar(id);

    expect(peticiones.single['hoy'], '2026-10-05');
  });

  test('sin internet, sigue esperando con un mensaje', () async {
    final id = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime.now(),
    );
    respuestas.add(sinRed);

    final dictado = await crearProcesador().procesar(id);

    expect(dictado!.estado, EstadoDictado.esperando);
    expect(dictado.mensaje, contains('Sin conexión'));
  });

  test('si la IA no entiende el audio, queda como fallido', () async {
    final id = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime.now(),
    );
    respuestas.add(
      () => http.Response(
        jsonEncode({
          'error': 'No se pudo entender la actividad.',
          'codigo': 'respuesta_invalida',
        }),
        502,
      ),
    );

    final dictado = await crearProcesador().procesar(id);

    expect(dictado!.estado, EstadoDictado.fallido);
    expect(dictado.mensaje, 'No se pudo entender la actividad.');
  });

  test(
    'si el audio ya no existe, queda como fallido sin llamar a la IA',
    () async {
      final id = await dictados.crear(
        rutaAudio: 'a.wav',
        grabadoEn: DateTime.now(),
      );

      final dictado = await crearProcesador(
        leerAudio: (ruta) => throw FileSystemException('no existe', ruta),
      ).procesar(id);

      expect(dictado!.estado, EstadoDictado.fallido);
      expect(peticiones, isEmpty);
    },
  );

  test('no envía dos veces el mismo dictado al mismo tiempo', () async {
    final id = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: DateTime.now(),
    );
    respuestas.add(() => ok({'transcripcion': 'x', 'tipo': 'otro'}));
    final procesador = crearProcesador();

    // Por ejemplo: el botón de voz y la cola automática a la vez.
    final [a, b] = await Future.wait([
      procesador.procesar(id),
      procesador.procesar(id),
    ]);

    expect(peticiones, hasLength(1));
    expect(a!.estado, EstadoDictado.listo);
    expect(b!.estado, EstadoDictado.listo);
  });

  test('la cola se procesa en orden, con pausa entre cada dictado', () async {
    final ahora = DateTime.now();
    final segundo = await dictados.crear(rutaAudio: 'b.wav', grabadoEn: ahora);
    final primero = await dictados.crear(
      rutaAudio: 'a.wav',
      grabadoEn: ahora.subtract(const Duration(minutes: 5)),
    );
    respuestas
      ..add(() => ok({'transcripcion': 'primero', 'tipo': 'otro'}))
      ..add(() => ok({'transcripcion': 'segundo', 'tipo': 'otro'}));

    await crearProcesador().procesarPendientes();

    final estados = {
      for (final d in await db.select(db.dictados).get()) d.id: d.estado,
    };
    expect(estados, {
      primero: EstadoDictado.listo,
      segundo: EstadoDictado.listo,
    });
    expect(pausas, [const Duration(seconds: 4)]);
  });

  test('si se corta internet, deja el resto para la próxima vez', () async {
    await dictados.crear(rutaAudio: 'a.wav', grabadoEn: DateTime.now());
    await dictados.crear(rutaAudio: 'b.wav', grabadoEn: DateTime.now());
    respuestas.add(sinRed);

    await crearProcesador().procesarPendientes();

    // Solo intentó el primero; los dos siguen esperando.
    expect(peticiones, hasLength(1));
    expect(await dictados.esperando(), hasLength(2));
  });

  test('borrar un dictado borra también su audio', () async {
    final borrados = <String>[];
    final repo = DictadosRepository(
      db,
      borrarArchivo: (ruta) async => borrados.add(ruta),
    );
    final id = await repo.crear(rutaAudio: 'a.wav', grabadoEn: DateTime.now());

    await repo.borrar(id);

    expect(await repo.contar(), 0);
    expect(borrados, ['a.wav']);
  });
}
