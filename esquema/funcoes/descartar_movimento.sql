CREATE OR REPLACE FUNCTION public.descartar_movimento(p_id bigint, p_motivo text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;
  update extrato_movimentos
     set situacao='descartado', classificacao=coalesce(p_motivo,'descartado')
   where id=p_id and situacao='pendente';
  return json_build_object('ok', found);
end; $function$
