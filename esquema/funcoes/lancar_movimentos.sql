CREATE OR REPLACE FUNCTION public.lancar_movimentos(p_itens jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  it jsonb; m record; v_lid uuid; v_conta text; v_obra uuid; v_rat jsonb; r jsonb;
  v_soma numeric; v_padrao text; v_cls text;
  n_lanc int:=0; n_transf int:=0; n_erro int:=0; erros text[]:='{}'; v_user text;
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;
  v_user := coalesce(auth.jwt()->>'email','sistema');

  for it in select * from jsonb_array_elements(p_itens) loop
    begin
      select * into m from extrato_movimentos
       where id = (it->>'id')::bigint and situacao='pendente';
      if not found then continue; end if;

      v_cls   := coalesce(it->>'classificacao','indefinido');
      v_conta := nullif(it->>'conta','');
      v_obra  := nullif(it->>'obra','')::uuid;
      v_rat   := it->'rateio';

      if v_cls in ('transferencia','fatura_cartao','ignorar') then
        update extrato_movimentos set situacao='conciliado', classificacao=v_cls where id=m.id;
        n_transf := n_transf + 1; continue;
      end if;

      if v_rat is not null and jsonb_typeof(v_rat)='array' and jsonb_array_length(v_rat)>0 then
        select coalesce(sum((x->>'valor')::numeric),0) into v_soma from jsonb_array_elements(v_rat) x;
        if abs(v_soma - abs(m.valor)) > 0.02 then
          erros := erros || (left(m.memo,30)||': rateio não fecha');
          n_erro := n_erro + 1; continue;
        end if;
        for r in select * from jsonb_array_elements(v_rat) loop
          insert into dre_lancamentos (data_competencia,data_caixa,conta_codigo,obra_id,
                                       valor,descricao,origem,criado_por)
          values (m.data_mov,m.data_mov,r->>'conta',nullif(r->>'obra','')::uuid,
                  (r->>'valor')::numeric,m.memo,'extrato',v_user)
          returning id into v_lid;
          insert into extrato_rateio (movimento_id,lancamento_id,obra_id,conta_codigo,valor)
          values (m.id,v_lid,nullif(r->>'obra','')::uuid,r->>'conta',(r->>'valor')::numeric);
          n_lanc := n_lanc + 1;
        end loop;
      elsif v_conta is not null then
        insert into dre_lancamentos (data_competencia,data_caixa,conta_codigo,obra_id,
                                     valor,descricao,origem,criado_por)
        values (m.data_mov,m.data_mov,v_conta,v_obra,abs(m.valor),m.memo,'extrato',v_user)
        returning id into v_lid;
        insert into extrato_rateio (movimento_id,lancamento_id,obra_id,conta_codigo,valor)
        values (m.id,v_lid,v_obra,v_conta,abs(m.valor));
        n_lanc := n_lanc + 1;
      else
        continue;
      end if;

      update extrato_movimentos set situacao='conciliado', classificacao=v_cls where id=m.id;

      -- aprende
      v_padrao := trim(regexp_replace(
        upper(regexp_replace(m.memo,'[0-9]{2,}|[0-9]{2}/[0-9]{2}','','g')),'\s+',' ','g'));
      if length(v_padrao)>=6 and v_conta is not null then
        insert into extrato_regras (padrao,classificacao,conta_codigo,confirmacoes,valor_medio,costuma_ratear)
        values (left(v_padrao,60),v_cls,v_conta,1,abs(m.valor),
                (v_rat is not null and jsonb_array_length(coalesce(v_rat,'[]'::jsonb))>1))
        on conflict (padrao) do update
          set confirmacoes = extrato_regras.confirmacoes+1,
              valor_medio = (coalesce(extrato_regras.valor_medio,0)*extrato_regras.confirmacoes
                             + abs(m.valor))/(extrato_regras.confirmacoes+1),
              conta_codigo = excluded.conta_codigo;
      end if;
    exception when others then
      n_erro := n_erro+1; erros := erros || (left(coalesce(m.memo,'?'),30)||': '||SQLERRM);
    end;
  end loop;

  return json_build_object('lancamentos',n_lanc,'transferencias',n_transf,
                           'erros',n_erro,'detalhes',to_json(erros));
end; $function$
