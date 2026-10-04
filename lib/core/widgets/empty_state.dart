import 'package:flutter/material.dart';

/// Mensaje centrado para pantallas sin datos: un ícono, un título y una
/// explicación de qué aparecerá ahí.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 72, color: colores.primary),
            const SizedBox(height: 16),
            Text(titulo, style: textos.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: textos.bodyMedium?.copyWith(
                color: colores.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
