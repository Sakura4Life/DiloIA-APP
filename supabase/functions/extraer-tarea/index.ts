// Edge Function `extraer-tarea`.
//
// Recibe una actividad dictada (texto o audio), le pide a Gemini que extraiga
// curso, tipo, título, fecha, hora y peso, y devuelve ese JSON a la app.
// La API key de Gemini vive solo aquí, como secreto de Supabase
// (GEMINI_API_KEY); la app nunca la conoce.
//
// Petición (POST, JSON):
//   { "texto": "...", "hoy": "2026-10-05", "cursos": ["Física", ...] }
//   o bien
//   { "audio": "<base64>", "mimeType": "audio/wav", "hoy": "...", "cursos": [...] }
//
// Respuesta 200:
//   { "transcripcion", "materia", "tipo", "titulo", "fecha", "hora", "peso" }
// Respuesta de error (400, 429, 500 o 502):
//   { "error": "mensaje para el usuario", "codigo": "..." }

import { ErrorGemini, llamarGemini } from "./gemini.ts";
import { normalizarResultado, validarPeticion } from "./logica.ts";

const CABECERAS = {
  "Content-Type": "application/json; charset=utf-8",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function responder(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: CABECERAS,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CABECERAS });
  if (req.method !== "POST") {
    return responder(405, { error: "Usa POST.", codigo: "entrada_invalida" });
  }

  let cuerpo: unknown;
  try {
    cuerpo = await req.json();
  } catch (_) {
    return responder(400, {
      error: "La petición no es un JSON válido.",
      codigo: "entrada_invalida",
    });
  }

  const validacion = validarPeticion(cuerpo);
  if (!validacion.ok) {
    return responder(400, {
      error: validacion.error,
      codigo: "entrada_invalida",
    });
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("Falta el secreto GEMINI_API_KEY");
    return responder(500, {
      error: "El servicio no está configurado.",
      codigo: "configuracion",
    });
  }

  try {
    const crudo = await llamarGemini(validacion.peticion, { apiKey });
    return responder(200, normalizarResultado(crudo, validacion.peticion));
  } catch (e) {
    if (e instanceof ErrorGemini) {
      const estado = e.codigo === "ia_ocupada" ? 429 : 502;
      return responder(estado, { error: e.message, codigo: e.codigo });
    }
    console.error("Error inesperado", e);
    return responder(500, {
      error: "Ocurrió un error inesperado.",
      codigo: "ia_no_disponible",
    });
  }
});
