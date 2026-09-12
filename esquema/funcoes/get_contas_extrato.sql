CREATE OR REPLACE FUNCTION public.get_contas_extrato()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_financeiro() then return null; end if;
  select json_build_object(
    'fixas', (select coalesce(json_agg(json_build_object(
        'codigo',codigo,'nome',nome,'natureza',natureza) order by codigo),'[]'::json)
      from dre_plano_contas
      where nivel=3 and tipo in ('despesa','custo','financeiro')
        and not bloqueia_extrato and codigo not like '03.%'),
    'obra', (select coalesce(json_agg(json_build_object(
        'codigo',codigo,'nome',nome) order by codigo),'[]'::json)
      from dre_plano_contas
      where nivel=3 and (codigo like '03.%' or bloqueia_extrato)),
    'bloqueadas', (select coalesce(json_agg(json_build_object(
        'codigo',codigo,'nome',nome,'motivo','já entra pela ficha da obra')),'[]'::json)
      from dre_plano_contas where bloqueia_extrato)
  ) into v;
  return v;
end; $function$
