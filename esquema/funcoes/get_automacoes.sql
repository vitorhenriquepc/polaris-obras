CREATE OR REPLACE FUNCTION public.get_automacoes()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(json_build_object(
    'chave', a.chave, 'nome', a.nome, 'descricao', a.descricao,
    'grupo', a.grupo, 'ligada', coalesce(c.valor,'0')='1'
  ) order by a.grupo, a.ordem),'[]'::json) into v
  from automacoes a left join config c on c.chave=a.chave
  where a.visivel;
  return v;
end $function$
