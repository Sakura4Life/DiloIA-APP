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
enum TipoActividad {
  entrega('Entrega', Duration(hours: 1)),
  examen('Examen', Duration(hours: 2)),
  proyecto('Proyecto', Duration(hours: 1)),
  exposicion('Exposición', Duration(hours: 1)),
  otro('Otro', Duration(hours: 1));

  const TipoActividad(this.etiqueta, this.duracionPorDefecto);

  /// Texto que se muestra en pantalla.
  final String etiqueta;

  /// Duración que se asume para detectar choques de horario.
  final Duration duracionPorDefecto;
}
