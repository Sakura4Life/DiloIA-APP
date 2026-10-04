# DiloIA

Asistente de notas académicas por voz (proyecto de curso). Dices una frase como
«entregar el laboratorio de física el martes a las 4 y vale el 20%» y la app crea la
tarea con curso, tipo, fecha, hora y peso, te recuerda y avisa si choca con otra.

Solo Android. Funciona sin internet (excepto el dictado por voz).

> Contexto completo del proyecto, decisiones y reglas de negocio: [CLAUDE.md](CLAUDE.md).

## Requisitos

- Flutter estable (probado con 3.47.6) y Android SDK.
- Un celular Android con **Depuración USB** activada, o un emulador.
- Comprobar el entorno: `flutter doctor` (los avisos de Chrome y Visual Studio se pueden
  ignorar: solo compilamos para Android).

## Primeros pasos

```bash
git clone <URL-del-repo>
cd <nombre-del-repo>
flutter pub get
flutter run
```

| Comando | Qué hace |
|---|---|
| `git clone` | Descarga el proyecto desde GitHub a una carpeta nueva. |
| `cd` | Entra a esa carpeta (se llama igual que el repo). |
| `flutter pub get` | Descarga las dependencias de `pubspec.yaml`. |
| `flutter run` | Compila e instala la app en el celular conectado. La primera vez tarda varios minutos. |

Al abrir la carpeta en VS Code, acepta instalar las extensiones recomendadas (Dart y
Flutter).

### Cuándo volver a correr algo

| Situación | Comando |
|---|---|
| Alguien cambió las dependencias en `pubspec.yaml` | `flutter pub get` |
| Alguien cambió las tablas de la base de datos (desde la fase 2) | `dart run build_runner build` |
| Ver tus cambios mientras `flutter run` está abierto | tecla `r` (hot reload) |

### Si falla por el NDK (`Package ndk not found`)

El nuevo `android` CLI no entiende el id que le pasa Gradle. Instalarlo a mano
(ajustar la versión a la que pida el error):

```powershell
& "$env:LOCALAPPDATA\Android\sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk/28.2.13676358"
```

## Cómo trabajamos (Git)

- **Nunca** hacer push directo a `main`.
- Una rama por tarea: `feature/nombre-corto`. Al terminar, abrir un Pull Request.
- Antes de cada commit: `flutter analyze` y `flutter test`. `main` siempre debe compilar.
- **Jamás** subir la API key de Gemini ni archivos `.env`. La key vive solo como secreto en
  Supabase.

## Estructura

```
lib/
  main.dart            arranque de la app
  core/                tema, colores, constantes (tipos de actividad, duraciones, zona horaria)
  data/                base de datos local (Drift) y repositorios
  features/
    voice/             botón de voz y tarjeta de confirmación
    tasks/             lista de pendientes y formulario manual
    calendar/          calendario mensual
    dashboard/         panel de carga académica semanal
    reminders/         pantalla y ajustes de recordatorios
  services/            cliente de la Edge Function, notificaciones, conectividad
android/               proyecto Android (permisos y configuración de Gradle)
test/                  pruebas unitarias y de widgets
supabase/
  functions/
    extraer-tarea/     Edge Function (Deno) que llama a Gemini
```

Las carpetas vacías llevan un archivo `.gitkeep`: Git no versiona carpetas vacías, y ese
archivo solo existe para que la estructura viaje en el repo. Se puede borrar en cuanto la
carpeta tenga código de verdad.

Solo existe la carpeta `android/`: el alcance del proyecto es únicamente Android, así que
`ios/`, `web/`, `linux/`, `macos/` y `windows/` se eliminaron a propósito.
