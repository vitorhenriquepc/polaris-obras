CREATE OR REPLACE FUNCTION public.registrar_google_enviado(p_nps bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update nps set lembrete_google_em = now(),
                 lembretes_google = coalesce(lembretes_google,0) + 1,
                 google_agendado_para = null
   where id = p_nps;
$function$
