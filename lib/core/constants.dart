/// Zona horaria de la app. Se usa para calcular "hoy" y para programar los
/// recordatorios, sin importar la zona configurada en el celular.
const zonaHorariaLima = 'America/Lima';

/// Tiempo máximo de grabación del dictado por voz.
const duracionMaximaDictado = Duration(seconds: 30);

/// Un dictado más corto que esto se descarta: seguramente fue un toque largo
/// sin querer, no alguien hablando.
const duracionMinimaDictado = Duration(seconds: 1);

/// Cuántos dictados pueden esperar a ser revisados a la vez. Cada audio pesa
/// hasta ~1 MB; el límite evita llenar el celular.
const maximoDictadosEnEspera = 10;

/// En qué paso va un dictado guardado en la cola.
enum EstadoDictado {
  /// Aún no lo procesa la IA: falta internet o la IA estaba ocupada.
  esperando,

  /// La IA ya lo entendió; falta que el usuario revise la tarjeta.
  listo,

  /// La IA no pudo entenderlo. El usuario puede reintentar o llenarlo a mano.
  fallido,
}

/// Tipos de actividad académica.
///
/// Los nombres del enum coinciden exactamente con el campo `tipo` del JSON que
/// devuelve la Edge Function, así que se convierten con
/// `TipoActividad.values.byName(json['tipo'])`.
///
/// Hay dos clases de actividad:
/// - **Plazo** (entrega): una fecha y hora límite, sin duración. Incluye
///   proyectos, informes, avances de tesis…; el título dice cuál es.
/// - **Eventos** (examen, exposición, reunión, otro): ocupan un lapso de
///   tiempo, por ejemplo un examen de 4:00 a 6:00 p. m.
///
/// Hasta la fase 5 existía "proyecto"; la versión 5 de la base lo convirtió
/// en entrega.
enum TipoActividad {
  entrega('Entrega', Duration.zero),
  examen('Examen', Duration(hours: 2)),
  exposicion('Exposición', Duration(hours: 1)),
  reunion('Reunión', Duration(hours: 1)),
  otro('Otro', Duration(hours: 1));

  const TipoActividad(this.etiqueta, this.duracionPorDefecto);

  /// Texto que se muestra en pantalla.
  final String etiqueta;

  /// Duración con la que empieza la tarjeta; el usuario la puede cambiar.
  /// Es cero en los plazos.
  final Duration duracionPorDefecto;

  /// `true` para la entrega: no tiene duración ni campo "Termina", y nunca
  /// choca con otras tareas.
  bool get esPlazo => this == entrega;
}
