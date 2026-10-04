import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Botón de dictado: se mantiene presionado para hablar y se suelta para
/// terminar. Por ahora solo es la interfaz; la grabación y la llamada a la IA
/// se conectan en la fase 4.
class VoiceButton extends StatefulWidget {
  const VoiceButton({super.key});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  bool _presionado = false;

  void _empezar() {
    HapticFeedback.mediumImpact();
    setState(() => _presionado = true);
  }

  void _terminar() {
    setState(() => _presionado = false);
    _avisar('El dictado por voz estará disponible pronto.');
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    // Mientras se mantiene presionado, el botón crece y cambia de color para
    // que el usuario sepa que lo está escuchando.
    final tamano = _presionado ? 84.0 : 72.0;
    final fondo = _presionado ? colores.error : colores.primary;
    final icono = _presionado ? colores.onError : colores.onPrimary;

    return Semantics(
      button: true,
      label: 'Mantén presionado para dictar una tarea',
      child: GestureDetector(
        onTap: () => _avisar('Mantén presionado para dictar.'),
        onLongPressStart: (_) => _empezar(),
        onLongPressEnd: (_) => _terminar(),
        child: AnimatedContainer(
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
          child: Icon(
            _presionado ? Icons.graphic_eq : Icons.mic,
            size: 36,
            color: icono,
          ),
        ),
      ),
    );
  }
}
