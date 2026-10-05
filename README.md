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
| Hiciste `git pull` y cambió `pubspec.yaml` | `flutter pub get` |
| **Tú** cambiaste las tablas en `lib/data/database.dart` | `dart run build_runner build` (ver [Base de datos](#base-de-datos)) |
| Ver tus cambios mientras `flutter run` está abierto | tecla `r` (hot reload); `R` reinicia la app |

El código generado por Drift (`lib/data/database.g.dart`) **se sube al repo**: al hacer
`git pull` ya llega listo y no hace falta generarlo.

### Sin celular: usar el emulador

```bash
flutter emulators                      # lista los emuladores disponibles
flutter emulators --launch <id>        # lo abre (la primera vez tarda 1–2 minutos)
flutter devices                        # anota el id, por ejemplo emulator-5554
flutter run -d emulator-5554
```

Si no tienes ninguno, créalo en Android Studio → *Device Manager*. Los datos del emulador
son independientes de los de tu celular.

### Pruebas

```bash
flutter analyze   # revisa errores y estilo
flutter test      # corre todas las pruebas de test/
```

Ambos deben pasar sin errores antes de subir una rama.

### Si falla por el NDK (`Package ndk not found`)

El nuevo `android` CLI no entiende el id que le pasa Gradle. Instalarlo a mano
(ajustar la versión a la que pida el error):

```powershell
& "$env:LOCALAPPDATA\Android\sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk/28.2.13676358"
```

## Cómo trabajamos (Git)

### Flujo de cada tarea

1. Antes de empezar, actualizar `main`: `git switch main` y `git pull`.
2. Crear la rama de la tarea: `git switch -c feature/nombre-corto`.
3. Trabajar y hacer commits en esa rama.
4. Si `main` avanzó mientras trabajabas, traerlo a tu rama: `git merge main` (los conflictos
   se resuelven en tu rama, nunca en `main`).
5. Antes de subir: `flutter analyze` y `flutter test`. `main` siempre debe compilar.
6. Subir la rama. La **primera vez** hay que crearla en GitHub y enlazarla:
   `git push -u origin feature/nombre-corto`. Desde ahí, basta con `git push`.
7. **Avisar al responsable del repo.** Quien subió la rama no abre el Pull Request: el
   responsable lo abre, revisa y lo fusiona a `main` (con *Squash*).
8. Cuando se fusione, todos: `git switch main`, `git pull` y borrar la rama local vieja.

### Reglas

- **Nunca** hacer push directo a `main`: GitHub lo bloquea, todo entra por Pull Request.
- Ramas pequeñas, un tema por rama. Si dos personas tocan el mismo archivo se generan
  conflictos; los archivos compartidos (`pubspec.yaml`, `lib/app.dart`,
  `AndroidManifest.xml`) conviene cambiarlos en ramas cortas.
- **Jamás** subir la API key de Gemini ni archivos `.env`. La key vive solo como secreto en
  Supabase.

## Base de datos

Las tareas y cursos se guardan **solo en el celular**, en una base SQLite manejada con
[Drift](https://drift.simonbinder.eu/). No hay nube ni cuentas: cada teléfono tiene sus
propios datos.

### Si cambias una tabla

Los teléfonos de todos ya tienen la base creada con la estructura anterior. Si cambias
una tabla sin migración, **la app se cierra al abrirse** en esos teléfonos. Siempre:

1. Cambia la tabla en `lib/data/database.dart`.
2. Sube `schemaVersion` en uno y anótalo en el historial que está encima.
3. Agrega el paso en `onUpgrade` (por ejemplo `m.addColumn(...)`).
4. Corre `dart run build_runner build` y sube también el `database.g.dart` regenerado.
5. Agrega una prueba de la migración en `test/data/repositories_test.dart`, como las que
   ya existen.

### Empezar con la base vacía

Desinstala la app del celular (o `adb uninstall com.diloia.app`) y vuelve a correr
`flutter run`. Se borran todos los cursos y tareas de ese teléfono.

## Estructura

```
lib/
  main.dart            arranque de la app
  app.dart             tema, idioma y navegación principal (pestañas)
  core/                tema, colores, constantes y formato de fechas, horas y peso
  data/                base de datos local (Drift), repositorios y providers
  features/
    voice/             botón de voz y tarjeta de confirmación
    tasks/             lista de pendientes, filtro, formulario y selector de hora
    courses/           crear, editar, ordenar y borrar cursos
    calendar/          calendario mensual
    dashboard/         panel de carga académica semanal
    reminders/         pantalla y ajustes de recordatorios
  services/            cliente de la Edge Function, notificaciones, conectividad
android/               proyecto Android (permisos y configuración de Gradle)
test/                  pruebas (core/, data/ y features/ siguen la estructura de lib/)
supabase/
  functions/
    extraer-tarea/     Edge Function (Deno) que llama a Gemini
```

Las carpetas vacías llevan un archivo `.gitkeep`: Git no versiona carpetas vacías, y ese
archivo solo existe para que la estructura viaje en el repo. Se puede borrar en cuanto la
carpeta tenga código de verdad.

Solo existe la carpeta `android/`: el alcance del proyecto es únicamente Android, así que
`ios/`, `web/`, `linux/`, `macos/` y `windows/` se eliminaron a propósito.
