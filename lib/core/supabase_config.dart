/// Datos para llamar a la Edge Function `extraer-tarea` de Supabase.
///
/// Ambos son públicos y pueden estar en el código: la clave *publishable* solo
/// permite llamar a la función. La API key de Gemini NO va aquí: vive como
/// secreto dentro de Supabase y la app nunca la ve.
library;

/// Id del proyecto de Supabase (lo que va antes de `.supabase.co`).
const idProyectoSupabase = 'zblgivqbffwziiypzszq';

/// Supabase → Project Settings → API Keys → Publishable key.
const clavePublicaSupabase = 'sb_publishable_d0Cr4pqIw76vE1aETR1xcQ_EFerOKu0';

final urlExtraerTarea = Uri.parse(
  'https://$idProyectoSupabase.supabase.co/functions/v1/extraer-tarea',
);
