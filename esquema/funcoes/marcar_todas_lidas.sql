CREATE OR REPLACE FUNCTION public.marcar_todas_lidas(p_obra uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if p_obra is null and not is_admin() then
    return json_build_object('erro','sem obra informada, so administrador pode marcar tudo');
  end if;
  update mensagens_recebidas
     set lida_em = now(),
         respondida_por = coalesce(respondida_por, coalesce(auth.email(),'equipe'))
   where da_equipe = false and lida_em is null
     and (p_obra is null or obra_id = p_obra);
  get diagnostics n = row_count;
  return json_build_object('ok', true, 'marcadas', n);
end $function$
