import '../../core/constants.dart';
import '../../data/tasks_repository.dart';

/// El horario de una actividad, lo único que importa para saber si choca.
///
/// - Un **evento** (examen, exposición, reunión, otro) ocupa desde [inicio]
///   hasta [inicio] + [duracion].
/// - Un **plazo** (entrega) es un solo instante: [inicio]. Su duración se
///   ignora.
typedef Horario = ({DateTime inicio, Duration duracion, TipoActividad tipo});

/// Momento en que termina un horario. En un plazo es el mismo [inicio].
DateTime finDe(Horario h) =>
    h.tipo.esPlazo ? h.inicio : h.inicio.add(h.duracion);

/// Si dos actividades chocan.
///
/// - **Una entrega nunca choca** con nada: es solo una fecha y hora límite,
///   se puede entregar antes y desde cualquier lugar.
/// - **Dos eventos** chocan si sus lapsos se cruzan
///   (`iniA < finB && iniB < finA`). Si uno termina justo cuando empieza el
///   otro, no chocan.
bool chocan(Horario a, Horario b) {
  if (a.tipo.esPlazo || b.tipo.esPlazo) return false;
  return a.inicio.isBefore(finDe(b)) && b.inicio.isBefore(finDe(a));
}

/// Horario de una tarea guardada.
Horario horarioDe(TareaConCurso item) => (
  inicio: item.tarea.inicio,
  duracion: Duration(minutes: item.tarea.duracionMinutos),
  tipo: item.tarea.tipo,
);

/// Las tareas de [existentes] que chocan con [nueva], en el mismo orden.
///
/// No cuentan las tareas completadas ni la tarea con id [ignorarId] (la que
/// se está editando: una tarea no choca consigo misma).
///
/// Es una función pura: no lee la base de datos ni la pantalla, así que se
/// prueba con datos inventados (ver test/features/tasks/conflictos_test.dart).
List<TareaConCurso> detectarConflictos(
  Horario nueva,
  List<TareaConCurso> existentes, {
  int? ignorarId,
}) {
  return [
    for (final item in existentes)
      if (!item.tarea.completada &&
          item.tarea.id != ignorarId &&
          chocan(nueva, horarioDe(item)))
        item,
  ];
}
