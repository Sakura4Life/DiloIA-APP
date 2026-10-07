import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'abrir_dictado.dart';
import 'grabadora.dart';
import 'providers_voz.dart';

/// En qué paso va el botón.
enum _Fase {
  /// Esperando a que lo presionen.
  libre,

  /// Revisando permisos y espacio en la cola antes de grabar.
  preparando,
  grabando,

  /// Guardando el audio y enviándolo a la IA.
  enviando,
}

/// Botón de dictado: se mantiene presionado para hablar y se suelta para
/// terminar.
///
/// El camino completo de un dictado:
/// 1. Graba un WAV (máximo 30 s) mientras el dedo está sobre el botón.
/// 2. Lo guarda en la cola de dictados (tabla Dictados). Desde aquí ya no se
///    pierde, pase lo que pase.
/// 3. Si hay red, lo envía a la IA y abre la tarjeta con lo que entendió.
///    Si no, avisa: se procesará solo cuando vuelva la conexión.
class VoiceButton extends ConsumerStatefulWidget {
  const VoiceButton({super.key});

  @override
  ConsumerState<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends ConsumerState<VoiceButton> {
  final _grabadora = Grabadora();
  _Fase _fase = _Fase.libre;

  /// `true` cuando el dedo ya se levantó. Preparar la grabación toma un
  /// momento, y el usuario puede soltar antes de que empiece.
  bool _soltado = false;

  String? _ruta;
  DateTime _inicio = DateTime.now();
  Duration _transcurrido = Duration.zero;

  /// Actualiza el contador en pantalla y corta a los 30 segundos.
  Timer? _reloj;

  @override
  void dispose() {
    _reloj?.cancel();
    _grabadora.dispose();
    super.dispose();
  }

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), action: accion));
  }

  void _alPresionar() {
    if (_fase != _Fase.libre) return;
    _fase = _Fase.preparando;
    _soltado = false;
    _empezar();
  }

  void _alSoltar() {
    _soltado = true;
    if (_fase == _Fase.grabando) _terminar();
  }

  Future<void> _empezar() async {
    try {
      final enCola = await ref.read(dictadosRepositoryProvider).contar();
      if (enCola >= maximoDictadosEnEspera) {
        _avisar(
          'Tienes $maximoDictadosEnEspera dictados por revisar. Revisa o '
          'descarta alguno antes de dictar otro.',
        );
        return _volverALibre();
      }
      if (!await _tienePermiso()) return _volverALibre();
      if (_soltado) {
        _avisar('Mantén presionado mientras hablas.');
        return _volverALibre();
      }

      _ruta = await _grabadora.empezar();
      _inicio = DateTime.now();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _fase = _Fase.grabando;
        _transcurrido = Duration.zero;
      });
      _reloj = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final transcurrido = DateTime.now().difference(_inicio);
        if (transcurrido >= duracionMaximaDictado) {
          _terminar();
        } else {
          setState(() => _transcurrido = transcurrido);
        }
      });
      // Soltó justo mientras arrancaba la grabación.
      if (_soltado) await _terminar();
    } catch (_) {
      _avisar('No se pudo usar el micrófono. Intenta de nuevo.');
      _volverALibre();
    }
  }

  void _volverALibre() {
    if (mounted) setState(() => _fase = _Fase.libre);
  }

  /// Pide el permiso de micrófono si hace falta. Devuelve `true` si ya se
  /// puede grabar.
  Future<bool> _tienePermiso() async {
    if (await _grabadora.tienePermiso(pedir: false)) return true;

    // La primera vez Android muestra su ventana de permiso. Mientras está
    // abierta el dedo se suelta, así que no se graba en este intento.
    if (await _grabadora.tienePermiso(pedir: true)) {
      _avisar('Listo. Ahora mantén presionado el micrófono para dictar.');
    } else {
      await _explicarPermiso();
    }
    return false;
  }

  /// Si el usuario negó el permiso dos veces, Android ya no vuelve a
  /// preguntar: solo se puede activar desde los Ajustes del celular.
  Future<void> _explicarPermiso() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso de micrófono'),
        content: const Text(
          'Para dictar tareas, DiloIA necesita el micrófono.\n\n'
          'Si no aparece la pregunta, actívalo en Ajustes → Apps → DiloIA → '
          'Permisos → Micrófono.\n\n'
          'Mientras tanto, puedes crear tareas a mano con el botón +.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _terminar() async {
    if (_fase != _Fase.grabando) return;
    _reloj?.cancel();
    setState(() => _fase = _Fase.enviando);

    try {
      final duracion = DateTime.now().difference(_inicio);
      if (duracion < duracionMinimaDictado) {
        await _grabadora.cancelar();
        _avisar('Mantén presionado mientras hablas.');
        return;
      }
      await _grabadora.terminar();
      HapticFeedback.lightImpact();

      final id = await ref
          .read(dictadosRepositoryProvider)
          .crear(rutaAudio: _ruta!, grabadoEn: _inicio);
      await _procesar(id);
    } catch (_) {
      _avisar('No se pudo guardar el dictado. Intenta de nuevo.');
    } finally {
      _volverALibre();
    }
  }

  Future<void> _procesar(int id) async {
    if (!await ref.read(conectividadProvider).hayRed()) {
      _avisar(
        'Sin conexión. Guardé tu dictado y lo proceso cuando vuelva internet.',
      );
      return;
    }

    final procesando = ref.read(procesadorDictadosProvider).procesar(id);
    final dictado = await _esperarConDialogo(procesando);
    if (dictado == null || !mounted) return;

    switch (dictado.estado) {
      case EstadoDictado.listo:
        final guardo = await revisarDictado(context, ref, dictado);
        if (!guardo) _avisar('El dictado quedó en «Por revisar».');
      case EstadoDictado.esperando:
        _avisar(
          '${dictado.mensaje ?? 'No se pudo procesar.'} Tu dictado quedó en '
          '«Por revisar» y lo intentaré de nuevo.',
        );
      case EstadoDictado.fallido:
        _avisar(
          dictado.mensaje ?? 'No se pudo entender el dictado.',
          accion: SnackBarAction(
            label: 'Llenar a mano',
            onPressed: () => llenarDictadoAMano(context, dictado),
          ),
        );
    }
  }

  /// Muestra "Entendiendo tu dictado…" mientras la IA trabaja. Devuelve el
  /// dictado procesado, o `null` si el usuario eligió "Revisar después" (el
  /// resultado igual llega a «Por revisar»).
  Future<Dictado?> _esperarConDialogo(Future<Dictado?> procesando) async {
    var cerradoPorUsuario = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogo) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Entendiendo tu dictado…')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cerradoPorUsuario = true;
                  Navigator.pop(dialogo);
                },
                child: const Text('Revisar después'),
              ),
            ],
          ),
        ),
      ),
    );

    final dictado = await procesando;
    if (cerradoPorUsuario) {
      _avisar('Cuando esté listo lo verás en «Por revisar».');
      return null;
    }
    if (mounted) Navigator.pop(context);
    return dictado;
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final grabando = _fase == _Fase.grabando;
    // Mientras graba, el botón crece y se pone rojo, y un anillo muestra
    // cuánto queda de los 30 segundos.
    final tamano = grabando ? 84.0 : 72.0;
    final fondo = grabando ? colores.error : colores.primary;
    final icono = grabando ? colores.onError : colores.onPrimary;
    final progreso =
        _transcurrido.inMilliseconds / duracionMaximaDictado.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (grabando)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: Icon(Icons.fiber_manual_record, color: colores.error),
              label: Text(
                '${_segundos(_transcurrido)} / '
                '${_segundos(duracionMaximaDictado)}',
              ),
            ),
          ),
        Semantics(
          button: true,
          label: 'Mantén presionado para dictar una tarea',
          child: GestureDetector(
            onTap: () => _avisar('Mantén presionado para dictar.'),
            onLongPressStart: (_) => _alPresionar(),
            onLongPressEnd: (_) => _alSoltar(),
            // Si el gesto se interrumpe (por ejemplo, una llamada entrante),
            // se trata como si hubiera soltado.
            onLongPressCancel: _alSoltar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: tamano,
                  height: tamano,
                  decoration: BoxDecoration(
                    color: fondo,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 8,
                        offset: Offset(0, 3),
                        color: Colors.black26,
                      ),
                    ],
                  ),
                  child: _fase == _Fase.enviando
                      ? Padding(
                          padding: const EdgeInsets.all(22),
                          child: CircularProgressIndicator(color: icono),
                        )
                      : Icon(
                          grabando ? Icons.graphic_eq : Icons.mic,
                          size: 36,
                          color: icono,
                        ),
                ),
                if (grabando)
                  SizedBox(
                    width: tamano + 10,
                    height: tamano + 10,
                    child: CircularProgressIndicator(
                      value: progreso.clamp(0, 1),
                      strokeWidth: 4,
                      color: colores.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 7 segundos → "0:07".
String _segundos(Duration duracion) {
  final s = duracion.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
