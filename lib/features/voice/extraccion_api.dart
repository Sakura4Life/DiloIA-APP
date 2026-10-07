import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/supabase_config.dart';

/// Lo que entendió la IA de un dictado. Es el "contrato" de la Edge Function:
/// todo lo que no se dijo llega como `null`.
class ResultadoIA {
  const ResultadoIA({
    required this.transcripcion,
    required this.tipo,
    this.materia,
    this.titulo,
    this.fecha,
    this.hora,
    this.peso,
  });

  /// Lee el JSON de la función. Si algún campo viene con otro tipo de dato, se
  /// toma como no dicho en vez de fallar.
  factory ResultadoIA.desdeJson(Map<String, dynamic> json) {
    String? texto(String campo) {
      final valor = json[campo];
      return valor is String && valor.trim().isNotEmpty ? valor.trim() : null;
    }

    final peso = json['peso'];
    return ResultadoIA(
      transcripcion: texto('transcripcion') ?? '',
      tipo: texto('tipo') ?? 'otro',
      materia: texto('materia'),
      titulo: texto('titulo'),
      fecha: texto('fecha'),
      hora: texto('hora'),
      peso: peso is num ? peso.toDouble() : null,
    );
  }

  /// Para guardarlo en la cola (columna `resultado`) mientras espera revisión.
  Map<String, dynamic> aJson() => {
    'transcripcion': transcripcion,
    'tipo': tipo,
    'materia': materia,
    'titulo': titulo,
    'fecha': fecha,
    'hora': hora,
    'peso': peso,
  };

  /// Lo que escuchó la IA, palabra por palabra.
  final String transcripcion;

  /// "entrega", "examen", "proyecto", "exposicion" u "otro".
  final String tipo;
  final String? materia;
  final String? titulo;

  /// `YYYY-MM-DD`.
  final String? fecha;

  /// `HH:mm`, de 24 horas.
  final String? hora;

  /// Porcentaje de la nota.
  final double? peso;
}

/// Error al pedirle a la IA que entienda un dictado.
class ErrorExtraccion implements Exception {
  const ErrorExtraccion(this.mensaje, {required this.reintentable});

  /// Texto listo para mostrarle al usuario.
  final String mensaje;

  /// `true` si vale la pena intentarlo de nuevo más tarde con el mismo audio
  /// (sin internet, IA ocupada…). `false` si el problema es el audio en sí.
  final bool reintentable;

  @override
  String toString() => 'ErrorExtraccion($mensaje)';
}

/// Envía el audio a la Edge Function `extraer-tarea` y devuelve lo que
/// entendió la IA.
class ExtraccionApi {
  ExtraccionApi({
    http.Client? cliente,
    Uri? url,
    this.tiempoMaximo = const Duration(seconds: 40),
  }) : _cliente = cliente ?? http.Client(),
       _url = url ?? urlExtraerTarea;

  final http.Client _cliente;
  final Uri _url;

  /// La función reintenta con Gemini hasta 3 veces (peor caso ≈ 27 s), así
  /// que se espera un poco más que eso antes de rendirse.
  final Duration tiempoMaximo;

  static const _sinConexion = ErrorExtraccion(
    'Sin conexión con el servicio de IA.',
    reintentable: true,
  );

  /// [hoy] es la fecha en que se grabó (`YYYY-MM-DD`, hora de Lima) y
  /// [cursos] los nombres de los cursos del estudiante.
  Future<ResultadoIA> extraer({
    required Uint8List audioWav,
    required String hoy,
    required List<String> cursos,
  }) async {
    final cuerpo = jsonEncode({
      'audio': base64Encode(audioWav),
      'mimeType': 'audio/wav',
      'hoy': hoy,
      'cursos': cursos,
    });

    final http.Response respuesta;
    try {
      respuesta = await _cliente
          .post(
            _url,
            headers: {
              'Content-Type': 'application/json',
              'apikey': clavePublicaSupabase,
              'Authorization': 'Bearer $clavePublicaSupabase',
            },
            body: cuerpo,
          )
          .timeout(tiempoMaximo);
    } on TimeoutException {
      throw _sinConexion;
    } on http.ClientException {
      // Sin internet, sin señal o el servidor no respondió.
      throw _sinConexion;
    }

    final json = _leerJson(respuesta);
    if (respuesta.statusCode == 200 && json != null) {
      return ResultadoIA.desdeJson(json);
    }
    throw _error(respuesta.statusCode, json);
  }

  static Map<String, dynamic>? _leerJson(http.Response respuesta) {
    try {
      final datos = jsonDecode(utf8.decode(respuesta.bodyBytes));
      return datos is Map<String, dynamic> ? datos : null;
    } on FormatException {
      return null;
    }
  }

  /// Convierte la respuesta de error de la función en un [ErrorExtraccion].
  /// La función responde `{ "error": "<mensaje>", "codigo": "..." }`.
  static ErrorExtraccion _error(int estado, Map<String, dynamic>? json) {
    final mensaje = json?['error'];
    final codigo = json?['codigo'];
    if (mensaje is String && codigo is String) {
      return ErrorExtraccion(
        mensaje,
        // "respuesta_invalida": la IA no entendió el audio; repetirlo daría lo
        // mismo. "entrada_invalida": el audio no sirve (vacío, muy largo).
        reintentable:
            codigo != 'respuesta_invalida' && codigo != 'entrada_invalida',
      );
    }
    // Sin el formato de la función: por ejemplo, el proyecto de Supabase está
    // pausado o la función no está desplegada.
    return ErrorExtraccion(
      'El servicio de IA no está disponible en este momento.',
      reintentable: estado >= 500,
    );
  }

  void cerrar() => _cliente.close();
}
