CREATE OR REPLACE FUNCTION public.receber_do_extrato(p_movimento bigint, p_obra uuid, p_parcela bigint DEFAULT NULL::bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record; o record; v_par record; v_num int; v_val numeric; v_achou boolean := false;
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;

  select * into m from extrato_movimentos where id=p_movimento and situacao='pendente';
  if not found then return json_build_object('ok',false,'erro','movimento não encontrado'); end if;
  if m.valor <= 0 then return json_build_object('ok',false,'erro','não é entrada'); end if;
  v_val := m.valor;

  select * into o from obras where id=p_obra;
  if not found then return json_build_object('ok',false,'erro','obra não encontrada'); end if;

  if p_parcela is not null then
    select * into v_par from obra_parcelas where id=p_parcela and obra_id=p_obra and not recebida;
    v_achou := found;
  else
    select * into v_par from obra_parcelas
     where obra_id=p_obra and not recebida and abs(valor - v_val) < 0.02
     order by vencimento limit 1;
    v_achou := found;
  end if;

  if v_achou then
    update obra_parcelas
       set recebida=true, recebida_em=m.data_mov,
           observacao = coalesce(observacao||' · ','') || 'baixa pelo extrato'
     where id=v_par.id;
  else
    select coalesce(max(numero),0)+1 into v_num from obra_parcelas where obra_id=p_obra;
    insert into obra_parcelas (obra_id, numero, valor, vencimento, recebida, recebida_em, observacao)
    values (p_obra, v_num, v_val, m.data_mov, true, m.data_mov, 'criada pelo extrato')
    returning * into v_par;
  end if;

  update extrato_movimentos set situacao='conciliado', classificacao='recebimento'
   where id=p_movimento;

  insert into extrato_rateio (movimento_id, obra_id, valor)
  values (p_movimento, p_obra, v_val);

  return json_build_object('ok',true,'cliente',o.cliente,'contrato',o.contrato,
    'parcela',v_par.numero,'valor',v_val,'baixou_existente',v_achou,
    'total_recebido',(select coalesce(sum(valor),0) from obra_parcelas where obra_id=p_obra and recebida),
    'preco',(select preco_negociado from obra_financeiro where obra_id=p_obra));
end; $function$
