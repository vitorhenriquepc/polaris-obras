CREATE OR REPLACE FUNCTION public.lancar_avulso(p_movimento bigint, p_cliente text, p_tipo text, p_obs text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record; t record; v_conta text; v_nat text; v_lid uuid; v_user text; v_id bigint;
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;
  v_user := coalesce(auth.jwt()->>'email','sistema');

  select * into m from extrato_movimentos where id=p_movimento and situacao='pendente';
  if not found then return json_build_object('ok',false,'erro','movimento não encontrado'); end if;

  select * into t from tipos_avulso where codigo=p_tipo and ativo;
  if not found then return json_build_object('ok',false,'erro','tipo inválido'); end if;

  if coalesce(trim(p_cliente),'')='' then
    return json_build_object('ok',false,'erro','informe o nome do cliente');
  end if;

  v_nat   := case when m.valor > 0 then 'receita' else 'despesa' end;
  v_conta := case when v_nat='receita' then t.conta_receita else t.conta_despesa end;
  if v_conta is null then return json_build_object('ok',false,'erro','tipo sem conta configurada'); end if;

  insert into dre_lancamentos (data_competencia, data_caixa, conta_codigo, valor,
                               descricao, origem, criado_por)
  values (m.data_mov, m.data_mov, v_conta, abs(m.valor),
          t.nome || ' — ' || trim(p_cliente), 'extrato', v_user)
  returning id into v_lid;

  insert into servicos_avulsos (cliente, tipo, natureza, valor, data_servico,
                                observacao, movimento_id, lancamento_id, criado_por)
  values (trim(p_cliente), p_tipo, v_nat, abs(m.valor), m.data_mov,
          nullif(trim(coalesce(p_obs,'')),''), p_movimento, v_lid, v_user)
  returning id into v_id;

  insert into extrato_rateio (movimento_id, lancamento_id, conta_codigo, valor)
  values (p_movimento, v_lid, v_conta, abs(m.valor));

  update extrato_movimentos set situacao='conciliado', classificacao='avulso'
   where id=p_movimento;

  return json_build_object('ok',true,'id',v_id,'cliente',trim(p_cliente),
    'tipo',t.nome,'natureza',v_nat,'valor',abs(m.valor),'conta',v_conta);
end; $function$
