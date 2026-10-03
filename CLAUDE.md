# DiloIA — contexto del proyecto

Asistente de notas académicas por voz. Proyecto de curso universitario (no es tesis ni
producto comercial). Equipo pequeño trabajando con GitHub y VS Code.

**Idioma de trabajo: español.** Explicar cada paso importante en lenguaje sencillo: el
equipo debe entender el código para presentarlo en clase.

## Qué hace la app

El estudiante mantiene presionado un botón y dice una frase natural
(«tengo que entregar el laboratorio de física el martes a las 4 de la tarde y vale el 20%
de la nota parcial»). En segundos la app devuelve una tarjeta ya estructurada con curso,
tipo de actividad, fecha, hora y peso en la nota, lista para confirmar o corregir.

Flujo principal, el núcleo del proyecto, debe funcionar de punta a punta:

```
voz → transcripción y extracción con IA → tarjeta editable → guardado → recordatorio → detección de conflictos
```

Funciones secundarias: calendario con un color por curso y panel de carga académica
semanal (porcentaje de la nota en juego por semana). Solo si sobra tiempo: resumen
semanal leído en voz alta.

## Decisiones fijas (no cambiar ni proponer alternativas)

- **Solo Android.** No iOS, no web, no escritorio.
- **Simplicidad ante todo.** Es un proyecto de ciclo: que funcione. Nada de
  escalabilidad, Clean Architecture completa ni sobreingeniería.
- **Costo cero**: solo capas gratuitas.
- **Offline-first**: la base de datos local (Drift/SQLite) es la ÚNICA fuente de verdad.
  Las tareas viven solo en el celular. Sin sincronización en la nube, sin login, sin cuentas.
- **Sin internet debe funcionar**: ver pendientes, calendario, panel, recordatorios y
  detección de conflictos. Lo único que requiere internet es el dictado por voz; sin
  conexión el botón de voz avisa y ofrece el formulario manual.
- **Supabase se usa SOLO** para una Edge Function llamada `extraer-tarea` que esconde la
  API key de Gemini. Sin tablas de Supabase, sin Supabase Auth.
- **La API key de Gemini jamás aparece** en el código de Flutter ni en el repositorio.
  Vive solo como secreto en Supabase.
- **No usar**: React Native, Firebase, Whisper/OpenAI, Isar, ni generadores de código
  extra (p. ej. `riverpod_generator`). El único generador permitido es `build_runner`
  para Drift.

## Stack

| Área | Paquete |
|---|---|
| Estado | `flutter_riverpod` (sin code generation) |
| Audio y permisos | `record`, `permission_handler` |
| IA | Gemini API (entiende el audio y devuelve JSON), llamada **solo** desde la Edge Function |
| Backend | Supabase Edge Function (Deno/TypeScript) + `supabase_flutter` solo para invocarla |
| Base local | `drift`, `drift_flutter`, `path_provider` |
| Recordatorios | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| Red | `connectivity_plus` |
| UI | `table_calendar`, `intl` (fechas en español) |
| Opcionales finales | `fl_chart` (si no, barras de progreso normales), `flutter_tts` |

Instalar dependencias con `flutter pub add` para obtener versiones actuales. **Antes de
usar un paquete, consultar su documentación o README actual**, no la memoria: las APIs de
estos paquetes cambian entre versiones.

## Contrato de datos (lo que devuelve la Edge Function)

```json
{ "transcripcion": "...", "materia": "Física", "tipo": "entrega",
  "fecha": "2026-10-06", "hora": "16:00", "peso": 20 }
```

- `tipo` es uno de: `entrega`, `examen`, `proyecto`, `exposicion`, `otro`.
- `fecha` en `YYYY-MM-DD`, `hora` en `HH:mm` de 24 horas, `peso` es un número (porcentaje).
- Todo dato no mencionado llega como `null`. `transcripcion` y `tipo` siempre vienen.
- La app **envía** a la función: audio en base64 (WAV, 16 kHz, mono), `mimeType`, la fecha
  de hoy con zona horaria de Lima, y la lista de nombres de cursos del estudiante (la IA
  la usa para reconocer bien las materias). Para pruebas la función también acepta `texto`
  en lugar de audio.
- El nombre del modelo de Gemini va en una **constante fácil de cambiar**: hay que
  confirmar en Google AI Studio qué modelo tiene Free Tier.

## Reglas de negocio

**Tarjeta de confirmación editable.** El usuario puede corregir curso, tipo, fecha, hora y
peso antes de guardar. No se puede confirmar sin curso, tipo, fecha y hora. Si la materia
dictada no coincide con ningún curso existente, ofrecer crearlo.

**Duración por defecto** (para detectar conflictos): examen 2 horas; entrega y los demás
tipos, 1 hora.

**Conflicto.** Dos actividades chocan si `iniA < finB && iniB < finA`. Si hay choque,
mostrar la tarea en conflicto con dos opciones: «Guardar igual» o «Cambiar hora». Esta
lógica va en una **función Dart pura con pruebas unitarias**.

**Recordatorios según el peso:**

| Peso | Avisos |
|---|---|
| 20% o más | 3 días antes, 1 día antes, 2 horas antes |
| 10% a 19% | 1 día antes, 2 horas antes |
| menos de 10% | solo 2 horas antes |

Se programan al guardar y se cancelan o reprograman al editar, completar o borrar.

**Panel semanal.** Suma del peso de las tareas no completadas de cada semana (porcentaje
de nota en riesgo).

**Otros.** Limitar el dictado a unos 30 segundos. Reintento con espera (backoff) ante
errores 429 de Gemini, y mensajes de error claros para el usuario.

## Detalles técnicos que suelen romper el proyecto

- Agregar el permiso `INTERNET` en el **AndroidManifest principal** (no solo en el de
  debug), además de `RECORD_AUDIO`, notificaciones y alarmas exactas. Si no, el APK
  release no tendrá internet.
- Android 13+ exige pedir **permiso de notificaciones en tiempo de ejecución**; Android
  12+ puede exigir **permiso de alarmas exactas**.
- `flutter_local_notifications` requiere **configuración extra en Gradle (desugaring)**:
  seguir el README actual del paquete.
- Usar siempre la zona horaria **America/Lima** para programar notificaciones y calcular
  «hoy».
- La URL y la clave `anon` de Supabase **pueden** ir en el código (son públicas). Nunca la
  key de Gemini ni ningún otro secreto; nada de archivos `.env` en el repo.

## Estructura de carpetas

```
lib/
  main.dart
  core/            tema, constantes, configuración
  data/            base de datos Drift y repositorios
  features/
    voice/         grabación y tarjeta de confirmación
    tasks/         lista de pendientes y formulario manual
    calendar/
    dashboard/
    reminders/
  services/        cliente de la Edge Function, notificaciones, conectividad
supabase/functions/extraer-tarea/
test/
```

Tablas de Drift:

- `Courses`: id, nombre, color
- `Tasks`: id, courseId, tipo, inicio, duración en minutos, pesoPorcentaje, completada

## Reglas de trabajo en equipo (Git)

- **Nunca push directo a `main`.** Una rama por tarea (`feature/nombre-corto`), dejarla
  lista para abrir un Pull Request.
- Antes de cada commit: `flutter analyze` y los tests. **`main` siempre debe compilar.**
- **No ejecutar comandos destructivos** (`reset --hard`, `push --force`, borrar ramas) sin
  pedir confirmación.
- Si una tarea requiere algo que solo el dueño del proyecto puede hacer (crear el proyecto
  en supabase.com, crear la API key en aistudio.google.com, guardar el secreto, desplegar
  la función, aceptar permisos en el celular), **dar los pasos exactos y esperar**. No
  fingir que ya está hecho.
- Si el repo o el proyecto Flutter no están en el estado esperado, decirlo antes de
  continuar.

## Fases (una a la vez; al terminar cada una, detenerse y esperar confirmación)

1. **Esqueleto**: carpetas, dependencias, tema, navegación básica.
2. **Base local y formulario manual**: tablas Drift, CRUD de cursos y tareas, lista de
   pendientes. Esta fase ya da una app útil sin internet.
3. **Edge Function `extraer-tarea`** con Gemini y salida JSON estructurada; probarla con
   texto antes de usar audio.
4. **Voz en Flutter**: permisos, grabación manteniendo presionado el botón, llamada a la
   función, tarjeta editable, modo sin conexión.
5. **Detección de conflictos** con pruebas unitarias.
6. **Recordatorios locales.**
7. **Calendario y panel semanal.**
8. **Opcionales**: resumen hablado (`flutter_tts`), gráficos (`fl_chart`).
9. **APK release** (`flutter build apk --release`) y pruebas de usabilidad con estudiantes
   usando el cuestionario SUS.

## Notas del entorno (actualizar si cambia)

- Flutter 3.47.6 stable, Dart 3.13.5. Android SDK en
  `C:\Users\USER\AppData\Local\Android\sdk`, NDK 28.2.13676358 instalado a mano.
- La instalación automática del NDK falla porque el nuevo `android` CLI no entiende el id
  `ndk;<version>` que le pasa Gradle. Se instala con:
  `…\cmdline-tools\latest\bin\android.exe sdk install "ndk/28.2.13676358"`.
- Requiere **Instalar vía USB** y **Depuración USB (Ajustes de seguridad)** activados en Opciones
  de desarrollador, o `adb install` falla con `INSTALL_FAILED_USER_RESTRICTED`.
- Los avisos `WARNING: A restricted method in java.lang.System…` de Gradle son ruido de
  Java 25 y no afectan el build.
