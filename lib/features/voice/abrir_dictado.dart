import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../tasks/task_form_screen.dart';
import 'borrador_desde_ia.dart';
import 'extraccion_api.dart';

/// Abre la tarjeta de confirmación con lo que entendió la IA de un dictado
/// `listo`. Devuelve `true` si el usuario guardó la tarea.
Future<bool> revisarDictado(
  BuildContext context,
  WidgetRef ref,
  Dictado dictado,
) async {
  final resultado = ResultadoIA.desdeJson(
    jsonDecode(dictado.resultado!) as Map<String, dynamic>,
  );
  final cursos = await ref.read(coursesRepositoryProvider).todos();
  final deVoz = borradorDesdeIA(
    resultado,
    cursos: cursos,
    ahora: DateTime.now(),
  );
  if (!context.mounted) return false;
  final guardo = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => TaskFormScreen(
        borrador: deVoz.borrador,
        dictado: DesdeDictado(
          id: dictado.id,
          transcripcion: resultado.transcripcion,
          materiaNueva: deVoz.materiaNueva,
        ),
      ),
    ),
  );
  return guardo ?? false;
}

/// Abre la tarjeta vacía para un dictado que la IA no entendió. Al guardar,
/// el dictado también sale de la cola.
Future<bool> llenarDictadoAMano(BuildContext context, Dictado dictado) async {
  final guardo = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => TaskFormScreen(dictado: DesdeDictado(id: dictado.id)),
    ),
  );
  return guardo ?? false;
}
