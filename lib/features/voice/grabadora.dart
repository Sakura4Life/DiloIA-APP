import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Graba el micrófono en un archivo WAV listo para enviar a la IA.
class Grabadora {
  /// Se crea recién al grabar por primera vez (así las pruebas de pantalla,
  /// que no tienen micrófono, no lo tocan).
  AudioRecorder? _creado;
  AudioRecorder get _recorder => _creado ??= AudioRecorder();

  /// WAV de 16 kHz y un canal (mono): suficiente para la voz y liviano.
  /// 30 segundos pesan unos 960 KB, debajo del límite de la Edge Function.
  static const _formato = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  /// Si la app tiene permiso de micrófono. Con [pedir], muestra la ventana de
  /// Android para pedirlo (si el usuario ya lo negó dos veces, Android ya no
  /// la muestra y devuelve `false` directamente).
  Future<bool> tienePermiso({required bool pedir}) =>
      _recorder.hasPermission(request: pedir);

  /// Empieza a grabar en un archivo nuevo dentro de la carpeta de la app y
  /// devuelve su ruta. No se usa la carpeta temporal porque Android puede
  /// vaciarla, y el audio debe sobrevivir mientras espera internet.
  Future<String> empezar() async {
    final documentos = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${documentos.path}/dictados');
    await carpeta.create(recursive: true);
    final ruta =
        '${carpeta.path}/dictado_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(_formato, path: ruta);
    return ruta;
  }

  /// Termina la grabación y deja el archivo guardado.
  Future<void> terminar() => _recorder.stop();

  /// Termina la grabación y borra el archivo.
  Future<void> cancelar() => _recorder.cancel();

  Future<void> dispose() async => _creado?.dispose();
}
