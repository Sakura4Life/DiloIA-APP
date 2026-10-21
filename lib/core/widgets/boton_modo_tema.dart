import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Botón de la barra superior que alterna entre modo claro y oscuro.
///
/// Muestra el ícono del modo al que se pasa al tocarlo (luna para pasar a
/// noche, sol para volver al día), con una rotación suave para que el cambio
/// se note sin llamar la atención. Ocupa lo mismo que los demás botones de la
/// barra, así que no desequilibra la fila.
///
/// Si el modo elegido es "seguir al sistema", el ícono refleja el brillo que
/// el teléfono tiene en ese momento.
class BotonModoTema extends ConsumerWidget {
  const BotonModoTema({super.key});

  /// Si el modo es el del sistema, hay que mirar el tema ya resuelto para
  /// saber si hoy se ve claro u oscuro.
  static bool _seVeOscuro(BuildContext context, ThemeMode modo) => switch (modo) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      Theme.of(context).brightness == Brightness.dark,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oscuro = _seVeOscuro(context, ref.watch(modoTemaProvider));

    return IconButton(
      tooltip: oscuro ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
      onPressed: () => ref
          .read(modoTemaProvider.notifier)
          .definir(oscuro ? ThemeMode.light : ThemeMode.dark),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        // Gira el ícono nuevo mientras sale el viejo: se lee como el sol y la
        // luna dándose la vuelta.
        transitionBuilder: (hijo, anim) => RotationTransition(
          turns: anim,
          child: FadeTransition(opacity: anim, child: hijo),
        ),
        child: Icon(
          oscuro ? Icons.light_mode : Icons.nights_stay_outlined,
          // La clave avisa a AnimatedSwitcher que el ícono cambió.
          key: ValueKey(oscuro),
        ),
      ),
    );
  }
}
