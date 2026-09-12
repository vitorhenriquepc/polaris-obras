CREATE OR REPLACE FUNCTION public.salvar_causa(p_usina uuid, p_causa text, p_nota text DEFAULT NULL::text, p_avisado boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  update usinas
     set causa = nullif(p_causa,''),
         causa_nota = p_nota,
         causa_em = case when nullif(p_causa,'') is null then null else now() end,
         causa_por = coalesce(auth.email(),'equipe'),
         cliente_avisado_em = case when p_avisado is true then coalesce(cliente_avisado_em, now())
                                   when p_avisado is false then null
                                   else cliente_avisado_em end
   where id = p_usina;
  return json_build_object('ok', true);
end $function$
