// Pruebas de gemini.ts con un Gemini simulado: no usan internet ni la cuota.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { cuerpoGemini, ErrorGemini, llamarGemini } from "./gemini.ts";
import type { Peticion } from "./logica.ts";

const peticion: Peticion = {
  texto: "examen de física el viernes a las 8",
  audio: null,
  mimeType: null,
  hoy: "2026-10-05",
  cursos: ["Física I"],
};

/** Respuesta con la forma que usa Gemini. */
function respuestaGemini(json: unknown): Response {
  return new Response(
    JSON.stringify({
      candidates: [{ content: { parts: [{ text: JSON.stringify(json) }] } }],
    }),
    { status: 200 },
  );
}

/** Un fetch falso que devuelve las respuestas en orden y cuenta las llamadas. */
function fetchFalso(respuestas: Response[]) {
  const llamadas: RequestInit[] = [];
  const f = ((_url: string, init: RequestInit) => {
    llamadas.push(init);
    return Promise.resolve(respuestas.shift()!);
  }) as unknown as typeof fetch;
  return { f, llamadas };
}

const sinEsperar = () => Promise.resolve();

Deno.test("devuelve el JSON que respondió Gemini", async () => {
  const { f, llamadas } = fetchFalso([respuestaGemini({ tipo: "examen" })]);
  const r = await llamarGemini(peticion, {
    apiKey: "clave",
    fetch: f,
    esperar: sinEsperar,
  });
  assertEquals(r, { tipo: "examen" });
  assertEquals(llamadas.length, 1);
  // La key va en la cabecera, no en la URL.
  assertEquals(
    (llamadas[0].headers as Record<string, string>)["x-goog-api-key"],
    "clave",
  );
});

Deno.test("ante un 429 reintenta con espera creciente y luego funciona", async () => {
  const esperas: number[] = [];
  const { f, llamadas } = fetchFalso([
    new Response("cuota", { status: 429 }),
    new Response("cuota", { status: 429 }),
    respuestaGemini({ tipo: "examen" }),
  ]);
  const r = await llamarGemini(peticion, {
    apiKey: "clave",
    fetch: f,
    esperar: (ms) => {
      esperas.push(ms);
      return Promise.resolve();
    },
  });
  assertEquals(r, { tipo: "examen" });
  assertEquals(llamadas.length, 3);
  assertEquals(esperas, [1000, 2000]);
});

Deno.test("si el 429 persiste, avisa que la IA está ocupada", async () => {
  const { f, llamadas } = fetchFalso([
    new Response("", { status: 429 }),
    new Response("", { status: 429 }),
    new Response("", { status: 429 }),
  ]);
  const error = await assertRejects(
    () =>
      llamarGemini(peticion, { apiKey: "k", fetch: f, esperar: sinEsperar }),
    ErrorGemini,
  );
  assertEquals(error.codigo, "ia_ocupada");
  assertEquals(llamadas.length, 3);
});

Deno.test("un 503 (servidores saturados) se reintenta", async () => {
  const { f, llamadas } = fetchFalso([
    new Response("saturado", { status: 503 }),
    respuestaGemini({ tipo: "entrega" }),
  ]);
  const r = await llamarGemini(peticion, {
    apiKey: "k",
    fetch: f,
    esperar: sinEsperar,
  });
  assertEquals(r, { tipo: "entrega" });
  assertEquals(llamadas.length, 2);
});

Deno.test("si la conexión falla o tarda demasiado, reintenta", async () => {
  let llamadas = 0;
  const f = (() => {
    llamadas++;
    if (llamadas < 3) {
      return Promise.reject(new DOMException("timeout", "TimeoutError"));
    }
    return Promise.resolve(respuestaGemini({ tipo: "examen" }));
  }) as unknown as typeof fetch;

  const r = await llamarGemini(peticion, {
    apiKey: "k",
    fetch: f,
    esperar: sinEsperar,
  });
  assertEquals(r, { tipo: "examen" });
  assertEquals(llamadas, 3);
});

Deno.test("si la conexión sigue fallando, se rinde con un mensaje claro", async () => {
  let llamadas = 0;
  const f = (() => {
    llamadas++;
    return Promise.reject(new TypeError("sin red"));
  }) as unknown as typeof fetch;

  const error = await assertRejects(
    () =>
      llamarGemini(peticion, { apiKey: "k", fetch: f, esperar: sinEsperar }),
    ErrorGemini,
  );
  assertEquals(error.codigo, "ia_no_disponible");
  assertEquals(llamadas, 3);
});

Deno.test("un error 400 no se reintenta", async () => {
  const { f, llamadas } = fetchFalso([new Response("mal", { status: 400 })]);
  const error = await assertRejects(
    () =>
      llamarGemini(peticion, { apiKey: "k", fetch: f, esperar: sinEsperar }),
    ErrorGemini,
  );
  assertEquals(error.codigo, "ia_no_disponible");
  assertEquals(llamadas.length, 1);
});

Deno.test("una respuesta que no es JSON se reporta como inválida", async () => {
  const { f } = fetchFalso([
    new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: "no es json" }] } }],
      }),
    ),
  ]);
  const error = await assertRejects(
    () =>
      llamarGemini(peticion, { apiKey: "k", fetch: f, esperar: sinEsperar }),
    ErrorGemini,
  );
  assertEquals(error.codigo, "respuesta_invalida");
});

Deno.test("el audio se envía como inlineData con su formato", () => {
  const cuerpo = cuerpoGemini({
    ...peticion,
    texto: null,
    audio: "UklGRg==",
    mimeType: "audio/wav",
  });
  const partes = cuerpo.contents[0].parts;
  assertEquals(partes[0], {
    inlineData: { mimeType: "audio/wav", data: "UklGRg==" },
  });
  assertEquals(cuerpo.generationConfig.responseMimeType, "application/json");
});
