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

/// En qué paso va el dictado.
enum _Fase {
  /// Solo se ve el botón del micrófono.
  libre,

  /// Revisando permisos y espacio en la cola antes de grabar.
  preparando,

  /// Grabando: se ve el panel con la onda de voz.
  grabando,

  /// Grabación en pausa (por el usuario o al llegar a los 30 s).
  pausado,

  /// Guardando el audio y enviándolo a la IA.
  enviando,
}

/// Botón de dictado, al estilo de los audios de WhatsApp: se toca una vez y
/// se puede hablar sin mantenerlo presionado.
///
/// Mientras graba, el botón se convierte en un panel con:
/// - el tiempo grabado y el límite ("0:07 / 0:30"),
/// - la onda de voz en vivo,
/// - 🗑 Descartar, ⏸ Pausar / ▶ Continuar y ➤ Enviar.
///
/// Al enviar, el dictado sigue el mismo camino de siempre:
/// 1. Se guarda en la cola de dictados (tabla Dictados): ya no se pierde.
/// 2. Si hay red, se envía a la IA y se abre la tarjeta con lo que entendió.
///    Si no, se procesará solo cuando vuelva la conexión.
class VoiceButton extends ConsumerStatefulWidget {
  const VoiceButton({super.key});

  @override
  ConsumerState<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends ConsumerState<VoiceButton>
    with WidgetsBindingObserver {
  /// Cada cuánto se actualizan el contador y la onda de voz.
  static const _paso = Duration(milliseconds: 100);

  /// Cuántas barras tiene la onda de voz.
  static const _barras = 40;

  _Fase _fase = _Fase.libre;
  String? _ruta;
  DateTime _inicio = DateTime.now();

  /// Tiempo grabado, sin contar las pausas.
  Duration _grabado = Duration.zero;

  /// `true` al llegar a los 30 s: ya no se puede continuar, solo enviar o
  /// descartar.
  bool _enLimite = false;

  /// Volumen de los últimos instantes, de 0 a 1, para dibujar la onda.
  final _niveles = <double>[];

  Timer? _reloj;

  /// Se lee una sola vez al crear el botón: en `dispose` ya no se puede usar
  /// `ref`, y ahí hace falta para cancelar una grabación a medias.
  late final Grabadora _grabadora;

  bool get _hayGrabacion => _fase == _Fase.grabando || _fase == _Fase.pausado;

  @override
  void initState() {
    super.initState();
    _grabadora = ref.read(grabadoraProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    // Si se cierra la pantalla a mitad de una grabación, se descarta.
    if (_hayGrabacion) unawaited(_grabadora.cancelar());
    super.dispose();
  }

  /// Si el usuario sale de la app mientras graba, se pausa: Android no deja
  /// usar el micrófono a una app que no está en pantalla.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.paused ||
        estado == AppLifecycleState.hidden) {
      _pausar();
    }
  }

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), action: accion));
  }

  void _volverALibre() {
    _reloj?.cancel();
    if (mounted) setState(() => _fase = _Fase.libre);
  }

  Future<void> _empezar() async {
    if (_fase != _Fase.libre) return;
    setState(() => _fase = _Fase.preparando);
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

      _ruta = await _grabadora.empezar();
      _inicio = DateTime.now();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _fase = _Fase.grabando;
        _grabado = Duration.zero;
        _enLimite = false;
        _niveles.clear();
      });
      _reloj = Timer.periodic(_paso, (_) => _avanzar());
    } catch (_) {
      _avisar('No se pudo usar el micrófono. Intenta de nuevo.');
      _volverALibre();
    }
  }

  /// Cada [_paso]: suma tiempo, agrega una barra a la onda y, al llegar a los
  /// 30 s, pausa sola la grabación.
  Future<void> _avanzar() async {
    if (_fase != _Fase.grabando) return;
    _grabado += _paso;
    var nivel = 0.0;
    try {
      nivel = await _grabadora.nivel();
    } catch (_) {
      // Sin volumen, la onda se ve plana, pero la grabación sigue.
    }
    if (!mounted || _fase != _Fase.grabando) return;
    setState(() {
      _niveles.add(nivel);
      if (_niveles.length > _barras) _niveles.removeAt(0);
    });
    if (_grabado >= duracionMaximaDictado) {
      _enLimite = true;
      await _pausar();
    }
  }

  Future<void> _pausar() async {
    if (_fase != _Fase.grabando) return;
    setState(() => _fase = _Fase.pausado);
    try {
      await _grabadora.pausar();
    } catch (_) {
      // Si no se pudo pausar, igual se dejó de contar el tiempo.
    }
  }

  Future<void> _continuar() async {
    if (_fase != _Fase.pausado || _enLimite) return;
    try {
      await _grabadora.reanudar();
      if (mounted) setState(() => _fase = _Fase.grabando);
    } catch (_) {
      _avisar('No se pudo continuar la grabación.');
    }
  }

  Future<void> _descartar() async {
    if (!_hayGrabacion) return;
    _volverALibre();
    try {
      await _grabadora.cancelar();
    } catch (_) {
      // El archivo quedó a medias; no afecta a la app.
    }
  }

  Future<void> _enviar() async {
    if (!_hayGrabacion) return;
    _reloj?.cancel();
    setState(() => _fase = _Fase.enviando);
    try {
      if (_grabado < duracionMinimaDictado) {
        await _grabadora.cancelar();
        _avisar('La grabación es muy corta. Habla un poco más.');
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

  /// Pide el permiso de micrófono si hace falta. Devuelve `true` si ya se
  /// puede grabar.
  Future<bool> _tienePermiso() async {
    if (await _grabadora.tienePermiso(pedir: false)) return true;
    // La primera vez Android muestra su ventana de permiso.
    if (await _grabadora.tienePermiso(pedir: true)) return true;
    await _explicarPermiso();
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
    if (_hayGrabacion) {
      return _PanelGrabacion(
        grabado: _grabado,
        pausado: _fase == _Fase.pausado,
        enLimite: _enLimite,
        niveles: _niveles,
        barras: _barras,
        onDescartar: _descartar,
        onPausar: _pausar,
        onContinuar: _continuar,
        onEnviar: _enviar,
      );
    }

    final colores = Theme.of(context).colorScheme;
    final enviando = _fase == _Fase.enviando;
    return Tooltip(
      message: 'Dictar una tarea',
      child: Semantics(
        button: true,
        label: 'Toca para dictar una tarea',
        child: GestureDetector(
          onTap: _empezar,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colores.primary,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 8,
                  offset: Offset(0, 3),
                  color: Colors.black26,
                ),
              ],
            ),
            child: enviando
                ? Padding(
                    padding: const EdgeInsets.all(22),
                    child: CircularProgressIndicator(color: colores.onPrimary),
                  )
                : Icon(Icons.mic, size: 36, color: colores.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// Panel que reemplaza al botón mientras se graba, como en WhatsApp.
class _PanelGrabacion extends StatelessWidget {
  const _PanelGrabacion({
    required this.grabado,
    required this.pausado,
    required this.enLimite,
    required this.niveles,
    required this.barras,
    required this.onDescartar,
    required this.onPausar,
    required this.onContinuar,
    required this.onEnviar,
  });

  final Duration grabado;
  final bool pausado;
  final bool enLimite;
  final List<double> niveles;
  final int barras;
  final VoidCallback onDescartar;
  final VoidCallback onPausar;
  final VoidCallback onContinuar;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final ancho = MediaQuery.sizeOf(context).width - 32;

    return SizedBox(
      width: ancho,
      child: Material(
        elevation: 6,
        color: colores.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Punto rojo mientras graba; ícono de pausa si está pausado.
                  Icon(
                    pausado ? Icons.pause_circle : Icons.fiber_manual_record,
                    size: 18,
                    color: pausado ? colores.onSurfaceVariant : colores.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_minutos(grabado)} / ${_minutos(duracionMaximaDictado)}',
                    style: textos.titleMedium?.copyWith(
                      // Números del mismo ancho: el texto no "baila".
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: CustomPaint(
                        painter: _OndaDeVoz(
                          niveles: niveles,
                          barras: barras,
                          color: pausado ? colores.outline : colores.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (enLimite)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Llegaste al límite de 30 s. Envía o descarta el audio.',
                    style: textos.bodySmall?.copyWith(color: colores.error),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Descartar',
                    iconSize: 28,
                    color: colores.error,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDescartar,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      // Al llegar al límite ya no se puede seguir grabando.
                      onPressed: enLimite
                          ? null
                          : (pausado ? onContinuar : onPausar),
                      icon: Icon(pausado ? Icons.mic : Icons.pause),
                      label: Text(pausado ? 'Continuar' : 'Pausar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    iconSize: 28,
                    icon: const Icon(Icons.send),
                    onPressed: onEnviar,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dibuja la onda de voz: una barra por instante, la más nueva a la derecha.
/// Las barras aún sin datos se ven como puntos.
class _OndaDeVoz extends CustomPainter {
  _OndaDeVoz({required this.niveles, required this.barras, required this.color})
    : _copia = List.of(niveles);

  final List<double> niveles;
  final int barras;
  final Color color;

  /// Copia para saber si cambió (la lista original se modifica en el lugar).
  final List<double> _copia;

  @override
  void paint(Canvas canvas, Size size) {
    final espacio = size.width / barras;
    final pincel = Paint()
      ..color = color
      ..strokeWidth = espacio * 0.6
      ..strokeCap = StrokeCap.round;
    final centro = size.height / 2;
    final vacias = barras - _copia.length;

    for (var i = 0; i < barras; i++) {
      final nivel = i < vacias ? 0.0 : _copia[i - vacias];
      final alto = (size.height * nivel).clamp(2.0, size.height) / 2;
      final x = espacio * i + espacio / 2;
      canvas.drawLine(
        Offset(x, centro - alto),
        Offset(x, centro + alto),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_OndaDeVoz anterior) =>
      anterior.color != color || !_iguales(anterior._copia, _copia);

  static bool _iguales(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 7 segundos → "0:07".
String _minutos(Duration duracion) {
  final s = duracion.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
