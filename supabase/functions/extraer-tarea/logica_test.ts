// Pruebas de logica.ts. Correr con:
//   npx deno test supabase/functions/extraer-tarea
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  construirInstrucciones,
  diaSemana,
  MAX_AUDIO_BYTES,
  normalizarResultado,
  type Peticion,
  sumarDias,
  validarPeticion,
} from "./logica.ts";

const base: Peticion = {
  texto: "x",
  audio: null,
  mimeType: null,
  hoy: "2026-10-05",
  cursos: ["Física I", "Cálculo II"],
};

Deno.test("acepta una petición con texto", () => {
  const v = validarPeticion({
    texto: "  examen de física el viernes  ",
    hoy: "2026-10-05",
    cursos: ["Física I"],
  });
  assert(v.ok);
  assertEquals(v.peticion.texto, "examen de física el viernes");
  assertEquals(v.peticion.cursos, ["Física I"]);
});

Deno.test("acepta audio con un formato permitido", () => {
  const v = validarPeticion({
    audio: "UklGRg==",
    mimeType: "audio/wav",
    hoy: "2026-10-05",
  });
  assert(v.ok);
  assertEquals(v.peticion.cursos, []);
});

Deno.test("rechaza peticiones incompletas o inválidas", () => {
  const casos: unknown[] = [
    null,
    "texto suelto",
    { texto: "hola" }, // falta hoy
    { texto: "hola", hoy: "05/10/2026" }, // formato de fecha
    { texto: "hola", hoy: "2026-02-30" }, // fecha imposible
    { hoy: "2026-10-05" }, // ni texto ni audio
    { texto: "  ", hoy: "2026-10-05" }, // texto vacío
    { texto: "a", audio: "b", mimeType: "audio/wav", hoy: "2026-10-05" }, // ambos
    { audio: "UklGRg==", hoy: "2026-10-05" }, // audio sin mimeType
    { audio: "UklGRg==", mimeType: "video/mp4", hoy: "2026-10-05" },
    { texto: "a".repeat(501), hoy: "2026-10-05" },
    { texto: "hola", hoy: "2026-10-05", cursos: "Física" },
  ];
  for (const caso of casos) {
    assertEquals(validarPeticion(caso).ok, false, JSON.stringify(caso));
  }
});

Deno.test("rechaza un audio de más de ~30 segundos", () => {
  const largo = "A".repeat(Math.ceil((MAX_AUDIO_BYTES * 4) / 3) + 8);
  const v = validarPeticion({
    audio: largo,
    mimeType: "audio/wav",
    hoy: "2026-10-05",
  });
  assertEquals(v.ok, false);
});

Deno.test("calcula días de la semana y suma días, también entre meses", () => {
  assertEquals(diaSemana("2026-10-05"), "lunes");
  assertEquals(diaSemana("2026-10-10"), "sábado");
  assertEquals(sumarDias("2026-10-30", 3), "2026-11-02");
  assertEquals(sumarDias("2026-12-31", 1), "2027-01-01");
});

Deno.test("las instrucciones incluyen el calendario y los cursos", () => {
  const texto = construirInstrucciones("2026-10-05", ["Física I"]);
  assertStringIncludes(texto, "- lunes 2026-10-05 (hoy)");
  assertStringIncludes(texto, "- martes 2026-10-06 (mañana)");
  assertStringIncludes(texto, "- lunes 2026-10-19");
  assertStringIncludes(texto, "- Física I");
});

Deno.test("normaliza una respuesta correcta sin cambiarla", () => {
  const r = normalizarResultado({
    transcripcion: "laboratorio de física el martes a las 4, vale 20",
    materia: "Física I",
    tipo: "entrega",
    titulo: "Laboratorio",
    fecha: "2026-10-06",
    hora: "16:00",
    peso: 20,
  }, base);
  assertEquals(r, {
    transcripcion: "laboratorio de física el martes a las 4, vale 20",
    materia: "Física I",
    tipo: "entrega",
    titulo: "Laboratorio",
    fecha: "2026-10-06",
    hora: "16:00",
    peso: 20,
  });
});

Deno.test("usa el nombre exacto del curso aunque cambien tildes o mayúsculas", () => {
  const r = normalizarResultado({ tipo: "examen", materia: "calculo ii" }, base);
  assertEquals(r.materia, "Cálculo II");
});

Deno.test("conserva una materia que no está en la lista", () => {
  const r = normalizarResultado({ tipo: "examen", materia: "Historia" }, base);
  assertEquals(r.materia, "Historia");
});

Deno.test("descarta valores mal formados en vez de pasarlos a la app", () => {
  const r = normalizarResultado({
    transcripcion: "algo",
    materia: "  ",
    tipo: "parcial", // no es un tipo válido
    titulo: "null",
    fecha: "2026-13-01",
    hora: "4pm",
    peso: 150,
  }, base);
  assertEquals(r.materia, null);
  assertEquals(r.tipo, "otro");
  assertEquals(r.titulo, null);
  assertEquals(r.fecha, null);
  assertEquals(r.hora, null);
  assertEquals(r.peso, null);
});

Deno.test("completa la hora con cero y acepta el peso como texto", () => {
  const r = normalizarResultado({ tipo: "examen", hora: "8:30", peso: "12.5" }, base);
  assertEquals(r.hora, "08:30");
  assertEquals(r.peso, 12.5);
});

Deno.test("si falta la transcripción, usa el texto enviado", () => {
  const r = normalizarResultado({ tipo: "otro" }, {
    ...base,
    texto: "reunión del grupo",
  });
  assertEquals(r.transcripcion, "reunión del grupo");
});
