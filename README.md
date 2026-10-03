# DiloIA

Asistente de notas académicas por voz (proyecto de curso). Dices una frase como
«entregar el laboratorio de física el martes a las 4 y vale el 20%» y la app crea la
tarea con curso, tipo, fecha, hora y peso, te recuerda y avisa si choca con otra.

Solo Android. Funciona sin internet (excepto el dictado por voz).

> Contexto completo del proyecto, decisiones y reglas de negocio: [CLAUDE.md](CLAUDE.md).

## Requisitos

- Flutter estable (probado con 3.47.6) y Android SDK.
- Un celular Android con **Depuración USB** activada, o un emulador.
  - En Xiaomi/Redmi activar también **Instalar vía USB** y **Depuración USB
    (Ajustes de seguridad)** en Opciones de desarrollador.
- Comprobar el entorno: `flutter doctor` (los avisos de Chrome y Visual Studio se pueden
  ignorar: solo compilamos para Android).

## Primeros pasos

```bash
git clone <URL-del-repo>
cd diloia_app
flutter pub get
dart run build_runner build   # genera el código de Drift (cuando exista la base de datos)
flutter run
```

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
  core/        tema y constantes
  data/        base de datos local (Drift) y repositorios
  features/    voice, tasks, calendar, dashboard, reminders
  services/    cliente de la Edge Function, notificaciones, conectividad
supabase/functions/extraer-tarea/   función que llama a Gemini
```
