/// Zona horaria de la app. Se usa para calcular "hoy" y para programar los
/// recordatorios, sin importar la zona configurada en el celular.
const zonaHorariaLima = 'America/Lima';

/// Tiempo máximo de grabación del dictado por voz.
const duracionMaximaDictado = Duration(seconds: 30);

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
