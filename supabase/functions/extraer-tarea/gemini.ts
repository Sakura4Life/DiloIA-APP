// Llamada a la API de Gemini (generateContent) con reintentos.
import {
  construirInstrucciones,
  ESQUEMA_RESPUESTA,
  MODELO_GEMINI,
  type Peticion,
} from "./logica.ts";

const URL_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

/** Códigos que la app puede usar para decidir qué mensaje mostrar. */
export type CodigoError =
  | "ia_ocupada" // Gemini respondió 429: cuota agotada o demasiadas peticiones.
  | "ia_no_disponible" // Gemini falló o no respondió a tiempo.
  | "respuesta_invalida"; // Gemini respondió algo que no es el JSON esperado.

export class ErrorGemini extends Error {
  constructor(
    readonly codigo: CodigoError,
    mensaje: string,
    readonly estadoHttp?: number,
  ) {
    super(mensaje);
  }
}

export interface Opciones {
  apiKey: string;
  /** Se inyecta para poder probar sin internet. */
  fetch?: typeof fetch;
  /** Espera entre reintentos; las pruebas la reemplazan para no esperar. */
  esperar?: (ms: number) => Promise<void>;
  /** Cuántas veces reintentar ante un 429 o un error del servidor. */
  reintentos?: number;
}

const dormir = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Arma el cuerpo de la petición a Gemini. */
export function cuerpoGemini(peticion: Peticion) {
  const partes: Record<string, unknown>[] = [];
  if (peticion.audio !== null) {
    partes.push({
      inlineData: { mimeType: peticion.mimeType, data: peticion.audio },
    });
    partes.push({ text: "Extrae los datos de la actividad dictada en el audio." });
  } else {
    partes.push({ text: peticion.texto });
  }

  return {
    systemInstruction: {
      parts: [{ text: construirInstrucciones(peticion.hoy, peticion.cursos) }],
    },
    contents: [{ role: "user", parts: partes }],
    generationConfig: {
      // Obliga a Gemini a responder solo con un JSON que cumpla el esquema.
      responseMimeType: "application/json",
      responseJsonSchema: ESQUEMA_RESPUESTA,
      // 0 = respuestas lo más consistentes posible, sin "creatividad".
      temperature: 0,
    },
  };
}

/**
 * Tiempo máximo que se espera a Gemini en cada intento. Normalmente responde
 * en pocos segundos; si tarda más, suele estar trabado y conviene reintentar
 * antes. Peor caso total: 3 intentos × 8 s + esperas de 1 s y 2 s ≈ 27 s.
 */
export const TIEMPO_POR_INTENTO_MS = 8_000;

/**
 * Envía la petición a Gemini y devuelve el JSON que respondió (sin validar:
 * eso lo hace `normalizarResultado`).
 *
 * Reintenta con espera creciente (1 s, luego 2 s) cuando:
 * - Gemini responde 429 (cuota o demasiadas peticiones) o 5xx (por ejemplo
 *   503, servidores saturados, frecuente en el nivel gratuito).
 * - La conexión falla o Gemini tarda más de `TIEMPO_POR_INTENTO_MS`.
 * Si sigue fallando, lanza `ErrorGemini`.
 */
export async function llamarGemini(
  peticion: Peticion,
  opciones: Opciones,
): Promise<unknown> {
  const hacerFetch = opciones.fetch ?? fetch;
  const esperar = opciones.esperar ?? dormir;
  const reintentos = opciones.reintentos ?? 2;
  const url = `${URL_BASE}/${MODELO_GEMINI}:generateContent`;
  const cuerpo = JSON.stringify(cuerpoGemini(peticion));

  for (let intento = 0;; intento++) {
    let respuesta: Response;
    try {
      respuesta = await hacerFetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // La key va en una cabecera y no en la URL, para que no quede en logs.
          "x-goog-api-key": opciones.apiKey,
        },
        body: cuerpo,
        signal: AbortSignal.timeout(TIEMPO_POR_INTENTO_MS),
      });
    } catch (e) {
      // Falló la conexión o Gemini no respondió a tiempo: se reintenta igual
      // que con un 503.
      console.error(`Gemini sin respuesta (intento ${intento + 1})`, e);
      if (intento < reintentos) {
        await esperar(1000 * 2 ** intento);
        continue;
      }
      throw new ErrorGemini(
        "ia_no_disponible",
        "El servicio de IA no respondió. Revisa tu conexión e intenta de nuevo.",
      );
    }

    const reintentable = respuesta.status === 429 || respuesta.status >= 500;
    if (reintentable && intento < reintentos) {
      await respuesta.body?.cancel();
      await esperar(1000 * 2 ** intento);
      continue;
    }

    if (respuesta.status === 429) {
      throw new ErrorGemini(
        "ia_ocupada",
        "El servicio de IA está ocupado. Intenta de nuevo en un minuto.",
        429,
      );
    }
    if (!respuesta.ok) {
      // Se registra el detalle para revisarlo en los logs de Supabase, pero al
      // usuario solo le llega un mensaje simple.
      console.error("Gemini", respuesta.status, await respuesta.text());
      throw new ErrorGemini(
        "ia_no_disponible",
        "El servicio de IA no está disponible en este momento.",
        respuesta.status,
      );
    }

    const datos = await respuesta.json();
    const texto = datos?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text ?? "")
      .join("");
    if (!texto) {
      console.error("Gemini sin contenido", JSON.stringify(datos));
      throw new ErrorGemini(
        "respuesta_invalida",
        "No se pudo entender la actividad. Intenta decirlo de otra forma.",
      );
    }
    try {
      return JSON.parse(texto);
    } catch (_) {
      console.error("Gemini devolvió algo que no es JSON", texto);
      throw new ErrorGemini(
        "respuesta_invalida",
        "No se pudo entender la actividad. Intenta decirlo de otra forma.",
      );
    }
  }
}
