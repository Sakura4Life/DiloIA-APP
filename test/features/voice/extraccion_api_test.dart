import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:diloia_app/features/voice/extraccion_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final audio = Uint8List.fromList([1, 2, 3]);

  /// Una función falsa que siempre responde [estado] con [cuerpo].
  ExtraccionApi apiQueResponde(int estado, Object cuerpo) => ExtraccionApi(
    cliente: MockClient(
      (_) async => http.Response(
        jsonEncode(cuerpo),
        estado,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );

  Future<ResultadoIA> extraer(ExtraccionApi api) =>
      api.extraer(audioWav: audio, hoy: '2026-10-06', cursos: ['Física I']);

  test('envía el audio en base64 con la fecha y los cursos', () async {
    late Map<String, dynamic> enviado;
    late Map<String, String> cabeceras;
    final api = ExtraccionApi(
      cliente: MockClient((peticion) async {
        enviado = jsonDecode(peticion.body) as Map<String, dynamic>;
        cabeceras = peticion.headers;
        return http.Response(
          jsonEncode({'transcripcion': 'x', 'tipo': 'otro'}),
          200,
        );
      }),
    );

    await extraer(api);

    expect(enviado['audio'], base64Encode(audio));
    expect(enviado['mimeType'], 'audio/wav');
    expect(enviado['hoy'], '2026-10-06');
    expect(enviado['cursos'], ['Física I']);
    // Solo la clave pública de Supabase; la de Gemini nunca sale del servidor.
    expect(cabeceras['apikey'], startsWith('sb_publishable_'));
  });

  test('devuelve lo que entendió la IA, con tildes intactas', () async {
    final api = apiQueResponde(200, {
      'transcripcion': 'exposición de física',
      'materia': 'Física I',
      'tipo': 'exposicion',
      'titulo': null,
      'fecha': '2026-10-09',
      'hora': '10:00',
      'peso': 15,
    });

    final r = await extraer(api);

    expect(r.transcripcion, 'exposición de física');
    expect(r.materia, 'Física I');
    expect(r.tipo, 'exposicion');
    expect(r.titulo, isNull);
    expect(r.peso, 15.0);
  });

  test('la IA ocupada (429) se reintenta más tarde', () async {
    final api = apiQueResponde(429, {
      'error': 'El servicio de IA está ocupado.',
      'codigo': 'ia_ocupada',
    });

    await expectLater(
      extraer(api),
      throwsA(
        isA<ErrorExtraccion>()
            .having(
              (e) => e.mensaje,
              'mensaje',
              'El servicio de IA está ocupado.',
            )
            .having((e) => e.reintentable, 'reintentable', true),
      ),
    );
  });

  test('si la IA no entendió el audio, no se reintenta solo', () async {
    final api = apiQueResponde(502, {
      'error': 'No se pudo entender la actividad.',
      'codigo': 'respuesta_invalida',
    });

    await expectLater(
      extraer(api),
      throwsA(
        isA<ErrorExtraccion>().having(
          (e) => e.reintentable,
          'reintentable',
          false,
        ),
      ),
    );
  });

  test('sin internet avisa y se reintenta más tarde', () async {
    final api = ExtraccionApi(
      cliente: MockClient((_) => throw http.ClientException('sin red')),
    );

    await expectLater(
      extraer(api),
      throwsA(
        isA<ErrorExtraccion>()
            .having((e) => e.reintentable, 'reintentable', true)
            .having((e) => e.mensaje, 'mensaje', contains('Sin conexión')),
      ),
    );
  });

  test('si la función no responde a tiempo, se rinde', () async {
    final api = ExtraccionApi(
      cliente: MockClient((_) => Completer<http.Response>().future),
      tiempoMaximo: const Duration(milliseconds: 10),
    );

    await expectLater(
      extraer(api),
      throwsA(isA<ErrorExtraccion>().having((e) => e.reintentable, 'r', true)),
    );
  });

  test('un error sin el formato de la función (proyecto pausado)', () async {
    final api = ExtraccionApi(
      cliente: MockClient((_) async => http.Response('<html>', 503)),
    );

    await expectLater(
      extraer(api),
      throwsA(isA<ErrorExtraccion>().having((e) => e.reintentable, 'r', true)),
    );
  });
}
