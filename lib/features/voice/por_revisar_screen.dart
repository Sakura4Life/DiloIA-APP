import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formato.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'abrir_dictado.dart';
import 'providers_voz.dart';

/// Recuadro en "Pendientes" que avisa cuántos dictados faltan revisar. Al
/// tocarlo abre la lista. No se muestra si la cola está vacía.
class AvisoPorRevisar extends ConsumerWidget {
  const AvisoPorRevisar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictados = ref.watch(dictadosProvider).value ?? const <Dictado>[];
    if (dictados.isEmpty) return const SizedBox.shrink();

    int cuantos(EstadoDictado estado) =>
        dictados.where((d) => d.estado == estado).length;
    final listos = cuantos(EstadoDictado.listo);
    final esperando = cuantos(EstadoDictado.esperando);
    final fallidos = cuantos(EstadoDictado.fallido);
    final detalle = [
      if (listos > 0) '$listos ${listos == 1 ? 'listo' : 'listos'}',
      if (esperando > 0) '$esperando esperando conexión',
      if (fallidos > 0) '$fallidos sin entender',
    ].join(' · ');

    final colores = Theme.of(context).colorScheme;
    final n = dictados.length;
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: colores.tertiaryContainer,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          Icons.record_voice_over,
          color: colores.onTertiaryContainer,
        ),
        title: Text(
          n == 1 ? '1 dictado por revisar' : '$n dictados por revisar',
          style: TextStyle(
            color: colores.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          detalle,
          style: TextStyle(color: colores.onTertiaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: colores.onTertiaryContainer),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PorRevisarScreen()),
        ),
      ),
    );
  }
}

/// Lista de dictados que todavía no son tareas, con lo que se puede hacer con
/// cada uno.
class PorRevisarScreen extends ConsumerWidget {
  const PorRevisarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictados = ref.watch(dictadosProvider).value ?? const <Dictado>[];
    final procesador = ref.watch(procesadorDictadosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Por revisar')),
      body: dictados.isEmpty
          ? const EmptyState(
              icono: Icons.done_all,
              titulo: 'Nada por revisar',
              mensaje:
                  'Aquí aparecen los dictados que esperan internet o tu '
                  'confirmación.',
            )
          // Se redibuja cuando un dictado empieza o termina de procesarse.
          : ValueListenableBuilder<Set<int>>(
              valueListenable: procesador.procesando,
              builder: (context, procesando, _) => ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final dictado in dictados)
                    _FilaDictado(
                      dictado: dictado,
                      procesando: procesando.contains(dictado.id),
                    ),
                ],
              ),
            ),
    );
  }
}

enum _Accion { revisar, reintentar, llenarAMano, descartar }

class _FilaDictado extends ConsumerWidget {
  const _FilaDictado({required this.dictado, required this.procesando});

  final Dictado dictado;
  final bool procesando;

  /// Lo que escuchó la IA, si ya lo procesó.
  String? get _transcripcion {
    final resultado = dictado.resultado;
    if (resultado == null) return null;
    final texto =
        (jsonDecode(resultado) as Map<String, dynamic>)['transcripcion'];
    return texto is String && texto.isNotEmpty ? texto : null;
  }

  void _avisar(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _hacer(
    BuildContext context,
    WidgetRef ref,
    _Accion accion,
  ) async {
    switch (accion) {
      case _Accion.revisar:
        await revisarDictado(context, ref, dictado);
      case _Accion.llenarAMano:
        await llenarDictadoAMano(context, dictado);
      case _Accion.reintentar:
        await _reintentar(context, ref);
      case _Accion.descartar:
        await _descartar(context, ref);
    }
  }

  Future<void> _reintentar(BuildContext context, WidgetRef ref) async {
    await ref.read(dictadosRepositoryProvider).volverAEsperar(dictado.id);
    if (!await ref.read(conectividadProvider).hayRed()) {
      if (context.mounted) {
        _avisar(context, 'Sin conexión. Lo intentaré cuando vuelva internet.');
      }
      return;
    }
    final resultado = await ref
        .read(procesadorDictadosProvider)
        .procesar(dictado.id);
    if (!context.mounted || resultado == null) return;
    if (resultado.estado != EstadoDictado.listo) {
      _avisar(context, resultado.mensaje ?? 'No se pudo procesar.');
    }
  }

  Future<void> _descartar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar este dictado?'),
        content: const Text(
          'Se borrará el audio y no se creará ninguna tarea.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await ref.read(dictadosRepositoryProvider).borrar(dictado.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final transcripcion = _transcripcion;
    final grabado =
        'Grabado: ${etiquetaDia(dictado.grabadoEn, hoy: DateTime.now())}, '
        '${textoHora(dictado.grabadoEn)}';

    final (
      Widget icono,
      String estado,
      _Accion principal,
      List<_Accion> menu,
    ) = switch (dictado.estado) {
      _ when procesando => (
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        'Procesando…',
        _Accion.revisar,
        const <_Accion>[],
      ),
      EstadoDictado.listo => (
        Icon(Icons.task_alt, color: colores.primary),
        'Toca para revisar y guardar',
        _Accion.revisar,
        const [_Accion.descartar],
      ),
      EstadoDictado.esperando => (
        Icon(Icons.cloud_off, color: colores.onSurfaceVariant),
        dictado.mensaje ?? 'Esperando conexión',
        _Accion.reintentar,
        const [_Accion.reintentar, _Accion.descartar],
      ),
      EstadoDictado.fallido => (
        Icon(Icons.error_outline, color: colores.error),
        dictado.mensaje ?? 'No se pudo entender',
        _Accion.llenarAMano,
        const [_Accion.reintentar, _Accion.llenarAMano, _Accion.descartar],
      ),
    };

    return ListTile(
      leading: icono,
      title: Text(
        transcripcion == null ? grabado : '«$transcripcion»',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(transcripcion == null ? estado : '$grabado\n$estado'),
      isThreeLine: transcripcion != null,
      // Mientras se procesa no se puede tocar, para no enviarlo dos veces.
      onTap: procesando ? null : () => _hacer(context, ref, principal),
      trailing: menu.isEmpty
          ? null
          : PopupMenuButton<_Accion>(
              tooltip: 'Opciones',
              onSelected: (accion) => _hacer(context, ref, accion),
              itemBuilder: (_) => [
                for (final accion in menu)
                  PopupMenuItem(
                    value: accion,
                    child: Text(switch (accion) {
                      _Accion.revisar => 'Revisar',
                      _Accion.reintentar => 'Reintentar ahora',
                      _Accion.llenarAMano => 'Llenar a mano',
                      _Accion.descartar => 'Descartar',
                    }),
                  ),
              ],
            ),
    );
  }
}
