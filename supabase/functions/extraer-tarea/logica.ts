// Reglas de la función `extraer-tarea` que no dependen de internet: validar lo
// que manda la app, armar las instrucciones para Gemini y limpiar su respuesta.
// Al no hacer llamadas de red, se pueden probar con `logica_test.ts`.

/**
 * Modelo de Gemini. Cambiarlo aquí si en Google AI Studio
 * (https://aistudio.google.com/rate-limit) otro modelo tiene Free Tier.
 */
export const MODELO_GEMINI = "gemini-3.5-flash-lite";

/** Tipos de actividad válidos. Deben coincidir con `TipoActividad` en Flutter. */
export const TIPOS = [
  "entrega",
  "examen",
  "proyecto",
  "exposicion",
  "otro",
] as const;
export type Tipo = (typeof TIPOS)[number];

/** Formatos de audio que acepta Gemini. La app manda WAV de 16 kHz mono. */
export const MIME_AUDIO = [
  "audio/wav",
  "audio/mp3",
  "audio/mpeg",
  "audio/aac",
  "audio/ogg",
  "audio/flac",
  "audio/m4a",
  "audio/webm",
];

/**
 * Tamaño máximo del audio. Un WAV de 16 kHz mono ocupa unos 32 KB por segundo:
 * 30 s ≈ 960 KB. Se deja margen hasta ~45 s.
 */
export const MAX_AUDIO_BYTES = 1_500_000;
export const MAX_TEXTO = 500;
export const MAX_CURSOS = 50;

/** Lo que manda la app, ya validado. */
export interface Peticion {
  texto: string | null;
  audio: string | null;
  mimeType: string | null;
  /** Fecha de hoy en Lima, "YYYY-MM-DD". */
  hoy: string;
  cursos: string[];
}

/** El JSON que devuelve la función (el contrato con la app). */
export interface Resultado {
  transcripcion: string;
  materia: string | null;
  tipo: Tipo;
  titulo: string | null;
  fecha: string | null;
  hora: string | null;
  peso: number | null;
}

export type Validacion =
  | { ok: true; peticion: Peticion }
  | { ok: false; error: string };

const RE_FECHA = /^\d{4}-\d{2}-\d{2}$/;

/** Revisa que la petición de la app tenga lo necesario y no sea demasiado grande. */
export function validarPeticion(cuerpo: unknown): Validacion {
  if (typeof cuerpo !== "object" || cuerpo === null) {
    return { ok: false, error: "La petición debe ser un objeto JSON." };
  }
  const c = cuerpo as Record<string, unknown>;

  if (typeof c.hoy !== "string" || !esFechaValida(c.hoy)) {
    return { ok: false, error: "Falta «hoy» con formato YYYY-MM-DD." };
  }

  let cursos: string[] = [];
  if (c.cursos !== undefined) {
    if (
      !Array.isArray(c.cursos) ||
      c.cursos.length > MAX_CURSOS ||
      c.cursos.some((x) => typeof x !== "string" || x.length > 60)
    ) {
      return {
        ok: false,
        error: `«cursos» debe ser una lista de hasta ${MAX_CURSOS} nombres.`,
      };
    }
    cursos = (c.cursos as string[]).map((x) => x.trim()).filter(Boolean);
  }

  const tieneTexto = typeof c.texto === "string" && c.texto.trim() !== "";
  const tieneAudio = typeof c.audio === "string" && c.audio !== "";
  if (tieneTexto === tieneAudio) {
    return { ok: false, error: "Envía «texto» o «audio», uno de los dos." };
  }

  if (tieneTexto) {
    const texto = (c.texto as string).trim();
    if (texto.length > MAX_TEXTO) {
      return {
        ok: false,
        error: `El texto no puede pasar de ${MAX_TEXTO} caracteres.`,
      };
    }
    return {
      ok: true,
      peticion: { texto, audio: null, mimeType: null, hoy: c.hoy, cursos },
    };
  }

  const audio = c.audio as string;
  if (typeof c.mimeType !== "string" || !MIME_AUDIO.includes(c.mimeType)) {
    return {
      ok: false,
      error: `«mimeType» debe ser uno de: ${MIME_AUDIO.join(", ")}.`,
    };
  }
  // En base64, cada 4 caracteres son 3 bytes.
  if ((audio.length * 3) / 4 > MAX_AUDIO_BYTES) {
    return { ok: false, error: "El audio es demasiado largo (máximo ~30 s)." };
  }
  return {
    ok: true,
    peticion: {
      texto: null,
      audio,
      mimeType: c.mimeType,
      hoy: c.hoy,
      cursos,
    },
  };
}

const DIAS = [
  "domingo",
  "lunes",
  "martes",
  "miércoles",
  "jueves",
  "viernes",
  "sábado",
];

/** Suma días a una fecha "YYYY-MM-DD" sin depender de la zona horaria. */
export function sumarDias(fecha: string, dias: number): string {
  const [a, m, d] = fecha.split("-").map(Number);
  const f = new Date(Date.UTC(a, m - 1, d + dias));
  return f.toISOString().slice(0, 10);
}

/** Nombre del día de la semana de una fecha "YYYY-MM-DD". */
export function diaSemana(fecha: string): string {
  const [a, m, d] = fecha.split("-").map(Number);
  return DIAS[new Date(Date.UTC(a, m - 1, d)).getUTCDay()];
}

/**
 * Instrucciones para Gemini. Incluyen un calendario de las próximas dos
 * semanas ya calculado, para que el modelo no tenga que hacer cuentas de
 * fechas (es donde más se equivocan los modelos pequeños).
 */
export function construirInstrucciones(hoy: string, cursos: string[]): string {
  const calendario = Array.from({ length: 15 }, (_, i) => {
    const fecha = sumarDias(hoy, i);
    const etiqueta = i === 0 ? " (hoy)" : i === 1 ? " (mañana)" : "";
    return `- ${diaSemana(fecha)} ${fecha}${etiqueta}`;
  }).join("\n");

  const listaCursos = cursos.length
    ? cursos.map((c) => `- ${c}`).join("\n")
    : "(el estudiante aún no tiene cursos registrados)";

  return `Eres el asistente de DiloIA, una agenda académica para universitarios de Perú.
El estudiante te dicta una actividad académica en español. Extrae sus datos.

Calendario (zona horaria de Lima):
${calendario}

Cursos del estudiante:
${listaCursos}

Reglas:
- transcripcion: lo que dijo el estudiante, palabra por palabra.
- materia: si el curso dictado coincide con uno de la lista (aunque lo diga
  abreviado, sin tildes o con otras palabras, ej. "cálculo" por "Cálculo II"),
  escribe el nombre EXACTO de la lista. Si no coincide con ninguno, escribe el
  nombre tal como lo dijo, con mayúscula inicial. null si no menciona curso.
- tipo: uno de entrega, examen, proyecto, exposicion, otro.
  * examen: examen, parcial, final, práctica calificada, PC, quiz, control.
  * entrega: tarea, informe, laboratorio, trabajo para entregar, ensayo.
  * proyecto: proyecto, trabajo final o de investigación de varias semanas.
  * exposicion: exposición, presentación oral, sustentación.
  * otro: cualquier otra cosa.
- titulo: nombre corto (máximo 6 palabras) que distinga la actividad, ej.
  "Laboratorio 3", "Informe de química orgánica", "Segundo parcial",
  "Proyecto final". Si el tipo es parte del nombre, consérvalo ("proyecto
  final" = "Proyecto final", nunca solo "Final"). No repitas el nombre del
  curso. null si solo dice el tipo (ej. "examen de cálculo").
- fecha: YYYY-MM-DD, usando el calendario de arriba.
  * Un día de la semana sin más ("el martes") es el próximo a partir de
    mañana. "El martes de la próxima semana" es el de la semana siguiente.
  * "Hoy", "mañana" y "pasado mañana" según el calendario.
  * Una fecha con número ("el 15") es la próxima vez que llegue ese día.
  * null si no menciona fecha.
- hora: HH:mm en formato de 24 horas.
  * "4 de la tarde" = 16:00, "8 de la noche" = 20:00, "mediodía" = 12:00.
  * Sin mañana/tarde/noche, elige la hora entre 07:00 y 22:59 (ej. "a las 4"
    = 16:00, "a las 8" = 08:00, "a las 10" = 10:00).
  * null si no menciona hora.
- peso: porcentaje de la nota como número (ej. "vale 20%" = 20). Si lo dice en
  puntos sobre 20, conviértelo (ej. "vale 4 puntos" = 20). null si no lo dice.
- No inventes datos: lo que no se mencione va como null.`;
}

/** Esquema JSON que Gemini debe respetar (structured output). */
export const ESQUEMA_RESPUESTA = {
  type: "object",
  properties: {
    transcripcion: { type: "string" },
    materia: { type: ["string", "null"] },
    tipo: { type: "string", enum: [...TIPOS] },
    titulo: { type: ["string", "null"] },
    fecha: { type: ["string", "null"], description: "YYYY-MM-DD" },
    hora: { type: ["string", "null"], description: "HH:mm, 24 horas" },
    peso: { type: ["number", "null"], description: "Porcentaje, 0 a 100" },
  },
  required: [
    "transcripcion",
    "materia",
    "tipo",
    "titulo",
    "fecha",
    "hora",
    "peso",
  ],
};

/** Minúsculas y sin tildes, para comparar nombres de cursos. */
export function claveDeOrden(texto: string): string {
  return texto.trim().toLowerCase().normalize("NFD").replace(
    /[̀-ͯ]/g,
    "",
  );
}

function esFechaValida(fecha: string): boolean {
  if (!RE_FECHA.test(fecha)) return false;
  const [a, m, d] = fecha.split("-").map(Number);
  const f = new Date(Date.UTC(a, m - 1, d));
  // Rechaza fechas imposibles como 2026-02-30.
  return f.getUTCFullYear() === a && f.getUTCMonth() === m - 1 &&
    f.getUTCDate() === d;
}

function textoONulo(valor: unknown, max: number): string | null {
  if (typeof valor !== "string") return null;
  const limpio = valor.trim();
  if (limpio === "" || limpio.toLowerCase() === "null") return null;
  return limpio.slice(0, max);
}

/**
 * Revisa y corrige la respuesta de Gemini antes de enviarla a la app. Aunque
 * el esquema obliga a Gemini a respetar el formato, un modelo puede devolver
 * una fecha imposible o una hora como "4pm"; aquí se descartan esos valores
 * para que la app reciba siempre datos válidos o null.
 */
export function normalizarResultado(
  crudo: unknown,
  peticion: Peticion,
): Resultado {
  const r = (typeof crudo === "object" && crudo !== null ? crudo : {}) as Record<
    string,
    unknown
  >;

  const tipo = TIPOS.includes(r.tipo as Tipo) ? (r.tipo as Tipo) : "otro";

  // Si la materia coincide con un curso (sin importar tildes ni mayúsculas),
  // se usa el nombre exacto del curso para que la app lo reconozca.
  let materia = textoONulo(r.materia, 60);
  if (materia !== null) {
    const clave = claveDeOrden(materia);
    materia = peticion.cursos.find((c) => claveDeOrden(c) === clave) ??
      materia;
  }

  const fechaCruda = textoONulo(r.fecha, 10);
  const fecha = fechaCruda !== null && esFechaValida(fechaCruda)
    ? fechaCruda
    : null;

  let hora: string | null = null;
  const horaCruda = textoONulo(r.hora, 5);
  const partes = horaCruda?.match(/^(\d{1,2}):(\d{2})$/);
  if (partes) {
    const h = Number(partes[1]);
    const m = Number(partes[2]);
    if (h <= 23 && m <= 59) {
      hora = `${String(h).padStart(2, "0")}:${partes[2]}`;
    }
  }

  let peso: number | null = null;
  const pesoCrudo = typeof r.peso === "string" ? Number(r.peso) : r.peso;
  if (
    typeof pesoCrudo === "number" && Number.isFinite(pesoCrudo) &&
    pesoCrudo >= 0 && pesoCrudo <= 100
  ) {
    peso = pesoCrudo;
  }

  return {
    // Con texto, la "transcripción" es el texto mismo.
    transcripcion: textoONulo(r.transcripcion, 1000) ?? peticion.texto ?? "",
    materia,
    tipo,
    titulo: textoONulo(r.titulo, 80),
    fecha,
    hora,
    peso,
  };
}
