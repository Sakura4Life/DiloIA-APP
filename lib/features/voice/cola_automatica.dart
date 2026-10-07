import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers_voz.dart';

/// Procesa solo los dictados que esperan, sin que el usuario haga nada:
/// - al abrir la app,
/// - cada vez que vuelve la red,
/// - cada vez que el usuario regresa a la app (estaba en otra app).
///
/// Solo funciona con la app abierta. Procesar con la app cerrada y avisar con
/// una notificación queda para la fase 6.
class ColaAutomatica extends ConsumerStatefulWidget {
  const ColaAutomatica({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ColaAutomatica> createState() => _ColaAutomaticaState();
}

class _ColaAutomaticaState extends ConsumerState<ColaAutomatica>
    with WidgetsBindingObserver {
  StreamSubscription<bool>? _cambiosDeRed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cambiosDeRed = ref.read(conectividadProvider).cambios.listen((hayRed) {
      if (hayRed) _procesar();
    });
    // Al abrir la app, apenas se dibuja la primera pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _procesar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cambiosDeRed?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _procesar();
  }

  Future<void> _procesar() async {
    try {
      if (!mounted || !await ref.read(conectividadProvider).hayRed()) return;
      if (!mounted) return;
      await ref.read(procesadorDictadosProvider).procesarPendientes();
    } catch (e) {
      // Si falla, el dictado sigue en la cola y se reintenta la próxima vez.
      debugPrint('No se pudo procesar la cola de dictados: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
