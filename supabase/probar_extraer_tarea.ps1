# Prueba la Edge Function `extraer-tarea` ya desplegada, con frases de ejemplo
# en texto (sin audio). Muestra lo que entendió la IA para compararlo con lo
# esperado.
#
# Uso (desde la carpeta del proyecto, en PowerShell):
#   .\supabase\probar_extraer_tarea.ps1 -Proyecto <id-del-proyecto> -Clave <publishable-key>
#
# - <id-del-proyecto>: lo que va antes de .supabase.co en la URL del proyecto.
# - <publishable-key>: Supabase → Project Settings → API Keys → Publishable key
#   (empieza con sb_publishable_). Es pública; NO uses la secret key.
#
# Si PowerShell bloquea el script, ejecútalo así:
#   powershell -ExecutionPolicy Bypass -File .\supabase\probar_extraer_tarea.ps1 -Proyecto ... -Clave ...

param(
    [Parameter(Mandatory = $true)][string]$Proyecto,
    [Parameter(Mandatory = $true)][string]$Clave
)

$url = "https://$Proyecto.supabase.co/functions/v1/extraer-tarea"

# "Hoy" en hora de Lima ("SA Pacific Standard Time" es el nombre de esa zona en Windows).
$lima = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'SA Pacific Standard Time')
$hoy = $lima.ToString('yyyy-MM-dd')
$cursos = @('Física I', 'Cálculo II', 'Química General', 'Programación')

# Cada frase con lo que se espera, para revisar a ojo.
$casos = @(
    @{ Frase = 'tengo que entregar el laboratorio de física el martes a las 4 de la tarde y vale el 20% de la nota parcial'; Esperado = 'entrega, Física I, próximo martes, 16:00, 20' }
    @{ Frase = 'examen parcial de cálculo el viernes a las 8, vale 30 por ciento'; Esperado = 'examen, Cálculo II, próximo viernes, 08:00, 30' }
    @{ Frase = 'exposición de historia pasado mañana a las 10 de la mañana'; Esperado = 'exposicion, Historia (no está en la lista), +2 días, 10:00' }
    @{ Frase = 'informe 2 de química para mañana a las 11 de la noche'; Esperado = 'entrega, Química General, mañana, 23:00, título "Informe 2"' }
    @{ Frase = 'proyecto final de programación el 15 a las 6 de la tarde, vale 4 puntos'; Esperado = 'entrega, Programación, día 15, 18:00, 20, título "Proyecto final"' }
    @{ Frase = 'práctica calificada de física el lunes de la próxima semana a las 2'; Esperado = 'examen, Física I, lunes de la otra semana, 14:00' }
    @{ Frase = 'entregar el ensayo de filosofía el miércoles'; Esperado = 'entrega, Filosofía, próximo miércoles, hora null' }
    @{ Frase = 'tengo examen de arte'; Esperado = 'examen, Arte, fecha y hora null' }
    @{ Frase = 'reunión con el grupo de trabajo el jueves a las 5'; Esperado = 'reunion, sin curso, próximo jueves, 17:00' }
    @{ Frase = 'hola cómo estás'; Esperado = 'otro, casi todo null' }
    @{ Frase = 'examen de física de 4 hasta las 5 el lunes'; Esperado = 'examen, Física I, próximo lunes, 16:00 a 17:00' }
    @{ Frase = 'exposición de química de 3 horas el jueves a las 9 de la mañana'; Esperado = 'exposicion, Química General, próximo jueves, 09:00 a 12:00' }
)

Write-Host "Hoy en Lima: $hoy ($($lima.ToString('dddd', [Globalization.CultureInfo]'es-PE')))"
Write-Host "Función: $url`n"

$resultados = foreach ($caso in $casos) {
    $cuerpo = @{ texto = $caso.Frase; hoy = $hoy; cursos = $cursos } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri $url -Method Post `
            -Headers @{ apikey = $Clave; Authorization = "Bearer $Clave" } `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo))
        [pscustomobject]@{
            Frase    = $caso.Frase
            Tipo     = $r.tipo
            Materia  = $r.materia
            Titulo   = $r.titulo
            Fecha    = $r.fecha
            Hora     = $r.hora
            HoraFin  = $r.horaFin
            Peso     = $r.peso
            Esperado = $caso.Esperado
        }
    } catch {
        # En PowerShell 5.1 el cuerpo del error no siempre llega en ErrorDetails:
        # se lee directamente de la respuesta.
        $detalle = $_.ErrorDetails.Message
        $respuesta = $_.Exception.Response
        if (-not $detalle -and $respuesta) {
            $lector = New-Object IO.StreamReader($respuesta.GetResponseStream())
            $detalle = $lector.ReadToEnd()
        }
        if ($respuesta) { $detalle = "HTTP $([int]$respuesta.StatusCode): $detalle" }
        [pscustomobject]@{ Frase = $caso.Frase; Tipo = 'ERROR'; Error = $detalle; Esperado = $caso.Esperado }
    }
    # Pausa para no pasar el límite de peticiones por minuto del Free Tier.
    Start-Sleep -Milliseconds 1500
}

$resultados | Format-List
