CREATE OR REPLACE FUNCTION public.importar_extrato(p_itens jsonb, p_conta uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; v_mid bigint; n_novo int:=0; n_ja int:=0; v_user text;
        v_dup json; n_dup int:=0; v_cls json;
begin
  if not is_financeiro() then raise exception 'sem permissão'; end if;
  v_user := coalesce(auth.jwt()->>'email','sistema');

  for it in select * from jsonb_array_elements(p_itens) loop
    v_cls := classificar_movimento(it->>'memo', (it->>'valor')::numeric);

    insert into extrato_movimentos (conta_id, fitid, data_mov, valor, memo, tipo_ofx,
                                    situacao, classificacao, importado_por)
    values (p_conta, it->>'fitid', (it->>'data')::date, (it->>'valor')::numeric,
            left(coalesce(it->>'memo',''),300), it->>'tipo',
            'pendente', v_cls->>'classificacao', v_user)
    on conflict (conta_id, fitid) do nothing
    returning id into v_mid;

    if v_mid is null then n_ja := n_ja + 1; continue; end if;
    n_novo := n_novo + 1;

    -- já existe lançamento manual parecido? marca para a tela avisar
    v_dup := buscar_duplicata((it->>'data')::date, (it->>'valor')::numeric);
    if (v_dup->>'achou')::boolean then
      update extrato_movimentos
         set duplicata_de = (v_dup->>'id')::uuid
       where id = v_mid;
      n_dup := n_dup + 1;
    end if;
  end loop;

  return json_build_object('novos',n_novo,'ja_existiam',n_ja,'possiveis_duplicatas',n_dup);
end; $function$
