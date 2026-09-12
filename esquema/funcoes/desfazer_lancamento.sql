CREATE OR REPLACE FUNCTION public.desfazer_lancamento(p_movimento bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record; n_lanc int:=0; n_par int:=0;
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;
  select * into m from extrato_movimentos where id=p_movimento and situacao='conciliado';
  if not found then return json_build_object('ok',false,'erro','movimento não está lançado'); end if;

  -- apaga os lançamentos do DRE gerados por ele
  delete from dre_lancamentos where id in (
    select lancamento_id from extrato_rateio
     where movimento_id=p_movimento and lancamento_id is not null);
  get diagnostics n_lanc = row_count;

  -- se foi recebimento, desfaz a baixa da parcela
  if m.classificacao='recebimento' then
    update obra_parcelas set recebida=false, recebida_em=null,
           observacao = nullif(replace(coalesce(observacao,''),'baixa pelo extrato',''),'')
     where obra_id in (select obra_id from extrato_rateio where movimento_id=p_movimento)
       and recebida and recebida_em = m.data_mov and abs(valor - m.valor) < 0.02;
    get diagnostics n_par = row_count;
    -- parcela criada pelo próprio extrato: apaga
    delete from obra_parcelas
     where obra_id in (select obra_id from extrato_rateio where movimento_id=p_movimento)
       and observacao='criada pelo extrato' and abs(valor - m.valor) < 0.02;
  end if;

  delete from extrato_rateio where movimento_id=p_movimento;
  update extrato_movimentos set situacao='pendente', classificacao=null where id=p_movimento;

  return json_build_object('ok',true,'lancamentos_apagados',n_lanc,'parcelas_reabertas',n_par);
end; $function$
