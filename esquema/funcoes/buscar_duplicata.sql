CREATE OR REPLACE FUNCTION public.buscar_duplicata(p_data date, p_valor numeric, p_conta text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if not is_financeiro() then return null; end if;
  select l.id, l.data_competencia, l.valor, l.descricao, c.nome as conta, l.criado_por
    into v
  from dre_lancamentos l join dre_plano_contas c on c.codigo = l.conta_codigo
  where l.origem <> 'extrato'
    and abs(l.valor - abs(p_valor)) < 0.02
    and l.data_competencia between p_data - 3 and p_data + 3
    and (p_conta is null or l.conta_codigo = p_conta)
  limit 1;
  if not found then return json_build_object('achou', false); end if;
  return json_build_object('achou', true, 'id', v.id, 'data', v.data_competencia,
    'valor', v.valor, 'conta', v.conta, 'descricao', v.descricao, 'por', v.criado_por);
end; $function$
