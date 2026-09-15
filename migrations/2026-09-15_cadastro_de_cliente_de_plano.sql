-- Cadastro de cliente de plano numa chamada so: cliente + obra + usinas +
-- contrato.
--
-- Por que uma funcao e nao quatro inserts na tela: sao quatro tabelas que
-- precisam existir juntas. Se a tela gravasse uma a uma e falhasse no meio,
-- sobraria cliente sem obra ou obra sem usina -- exatamente o tipo de orfao
-- que a limpeza de domingo existe para varrer. Aqui e tudo ou nada.
--
-- Tem modo `simular` porque a regra 3.2 manda simular antes de gravar, e
-- porque foi simulando o cadastro da Tays que apareceu a trava do financeiro
-- que ninguem tinha previsto.
--
-- O que a funcao decide sozinha, para nao depender de quem preenche:
--   trilha 'manutencao', etapa 4, cliente_externo = true, valor_projeto NULO
--   potencia e modulos da obra = soma das usinas
--   a ficha financeira nasce dispensada (pelo trigger abre_financeiro_obra)

create or replace function public.plano_cadastrar_cliente(
  p jsonb, p_simular boolean default true)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_erros  text[] := array[]::text[];
  v_avisos text[] := array[]::text[];
  c  jsonb := coalesce(p->'cliente',  '{}'::jsonb);
  ob jsonb := coalesce(p->'obra',     '{}'::jsonb);
  us jsonb := coalesce(p->'usinas',   '[]'::jsonb);
  kt jsonb := coalesce(p->'contrato', '{}'::jsonb);

  v_nome text := btrim(coalesce(c->>'nome',''));
  v_doc  text := nullif(regexp_replace(coalesce(c->>'documento',''),'\D','','g'),'');
  v_tel  text := nullif(regexp_replace(coalesce(c->>'telefone',''),'\D','','g'),'');
  v_origem text := nullif(btrim(coalesce(ob->>'sistema_origem','')),'');

  v_plano_cod  text := nullif(btrim(coalesce(kt->>'plano_codigo','')),'');
  v_plano_nome text;
  v_notadoc text := nullif(regexp_replace(coalesce(kt->>'nota_documento',''),'\D','','g'),'');
  v_valor   numeric := nullif(kt->>'valor','')::numeric;
  v_forma   text    := coalesce(nullif(btrim(coalesce(kt->>'forma','')),''),'anual');
  v_meses   int     := coalesce(nullif(kt->>'meses','')::int, 12);
  v_aguardando boolean := coalesce((kt->>'aguardando')::boolean, true);
  v_inicio  date    := nullif(kt->>'inicio','')::date;

  v_cliente_id uuid; v_cliente_novo boolean;
  v_obra_id uuid; v_contrato_id uuid;
  v_slug text; v_base text; v_n int := 1;
  v_kwp numeric := 0; v_mods int := 0; v_locais int;
  v_u jsonb; v_i int; v_uid uuid; v_alvo int;
  v_ids uuid[] := array[]::uuid[];
begin
  if not is_autorizado() then
    return json_build_object('ok', false, 'erros', json_build_array('Sem permissao.'));
  end if;

  -- ------------------------------------------------------------------ erros
  if v_nome = '' then
    v_erros := v_erros || array['Informe o nome do cliente.'];
  end if;
  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 11 then
    v_erros := v_erros || array['Telefone precisa ter 10 ou 11 digitos, com DDD.'];
  end if;
  if v_doc is not null and length(v_doc) not in (11,14) then
    v_erros := v_erros || array['Documento do cliente precisa ser CPF (11) ou CNPJ (14 digitos).'];
  end if;
  if v_notadoc is not null and length(v_notadoc) not in (11,14) then
    v_erros := v_erros || array['Documento da nota precisa ser CPF (11) ou CNPJ (14 digitos).'];
  end if;
  if jsonb_array_length(us) = 0 then
    v_erros := v_erros || array['Cadastre pelo menos uma usina.'];
  end if;

  for v_i in 0 .. jsonb_array_length(us)-1 loop
    v_u := us->v_i;
    if btrim(coalesce(v_u->>'apelido','')) = '' then
      v_erros := v_erros || array[('Usina '||(v_i+1)||': de um apelido, como "Acougue — Aracatuba".')];
    end if;
    if coalesce(nullif(v_u->>'potencia_kwp','')::numeric, 0) <= 0 then
      v_erros := v_erros || array[('Usina '||(v_i+1)||': informe a potencia em kWp.')];
    end if;
    -- a cidade define a vizinhanca de comparacao de desempenho
    if btrim(coalesce(v_u->>'cidade','')) = '' then
      v_erros := v_erros || array[('Usina '||(v_i+1)||': informe a cidade.')];
    end if;
  end loop;

  if v_plano_cod is not null then
    select nome into v_plano_nome from planos where codigo = v_plano_cod;
    if v_plano_nome is null then
      v_erros := v_erros || array['Plano nao encontrado.'];
    end if;
    if v_forma <> 'cortesia' and coalesce(v_valor,0) <= 0 then
      v_erros := v_erros || array['Informe o valor do contrato.'];
    end if;
    if not v_aguardando and v_inicio is null then
      v_erros := v_erros || array['Informe a data de inicio, ou marque que comeca no 1o pagamento.'];
    end if;
  end if;

  if array_length(v_erros,1) > 0 then
    return json_build_object('ok', false, 'erros', to_json(v_erros));
  end if;

  -- --------------------------------------------- o cliente ja esta na base?
  if v_doc is not null then
    select id into v_cliente_id from clientes
     where regexp_replace(coalesce(documento,''),'\D','','g') = v_doc limit 1;
  end if;
  if v_cliente_id is null then
    select id into v_cliente_id from clientes
     where unaccent_simples(nome) = unaccent_simples(v_nome) limit 1;
  end if;
  v_cliente_novo := v_cliente_id is null;
  if not v_cliente_novo then
    v_avisos := v_avisos || array[('Ja existe um cliente com esse '
      || case when v_doc is not null then 'documento' else 'nome' end
      || '. As usinas e o contrato vao para ele, sem duplicar o cadastro.')];
  end if;

  -- ----------------------------------------------------------------- somas
  for v_i in 0 .. jsonb_array_length(us)-1 loop
    v_kwp  := v_kwp  + coalesce(nullif(us->v_i->>'potencia_kwp','')::numeric, 0);
    v_mods := v_mods + coalesce(nullif(us->v_i->>'modulos','')::int, 0);
  end loop;

  select count(distinct coalesce(nullif(btrim(coalesce(x->>'endereco','')),''), x->>'cidade'))
    into v_locais from jsonb_array_elements(us) x;

  -- ------------------------------------------------------------------ slug
  v_base := regexp_replace(regexp_replace(unaccent_simples(v_nome),
              '[^a-z0-9]+','-','g'), '(^-|-$)','','g');
  v_base := left(nullif(v_base,''), 40);
  if v_base is null then v_base := 'cliente-de-plano'; end if;
  v_slug := v_base;
  while exists (select 1 from obras where slug = v_slug) loop
    v_n := v_n + 1; v_slug := v_base||'-'||v_n;
  end loop;

  -- ------------------------------------------------------------- simulacao
  if p_simular then
    return json_build_object(
      'ok', true, 'simulado', true,
      'avisos', to_json(v_avisos),
      'cliente_novo', v_cliente_novo,
      'slug', v_slug,
      'kwp', v_kwp, 'modulos', nullif(v_mods,0),
      'usinas', jsonb_array_length(us),
      'enderecos', v_locais,
      'plano', v_plano_nome,
      'valor', v_valor,
      'status_contrato', case when v_plano_cod is null then null
                              when v_aguardando then 'aguardando_pagamento'
                              else 'ativo' end);
  end if;

  -- -------------------------------------------------------------- gravacao
  if v_cliente_novo then
    insert into clientes (nome, documento, telefone, cidade,
                          nascimento_dia, nascimento_mes)
    values (v_nome, v_doc, v_tel,
            nullif(btrim(coalesce(c->>'cidade','')),''),
            nullif(c->>'nascimento_dia','')::int,
            nullif(c->>'nascimento_mes','')::int)
    returning id into v_cliente_id;
  end if;

  insert into obras (cliente, cliente_id, slug, trilha, etapa_numero, status,
                     cliente_externo, sistema_origem, tipo_manutencao,
                     categoria, ramo, cidade, endereco, telefone,
                     whatsapp_grupo_id, potencia_kwp, qtd_modulos,
                     valor_projeto, observacoes)
  values (v_nome, v_cliente_id, v_slug, 'manutencao', 4, 'Finalizado',
          true, v_origem, 'preventiva',
          nullif(btrim(coalesce(ob->>'categoria','')),''),
          nullif(btrim(coalesce(ob->>'ramo','')),''),
          nullif(btrim(coalesce(ob->>'cidade','')),''),
          nullif(btrim(coalesce(ob->>'endereco','')),''),
          v_tel,
          nullif(btrim(coalesce(ob->>'grupo','')),''),
          nullif(v_kwp,0), nullif(v_mods,0), null,
          nullif(btrim(coalesce(ob->>'observacoes','')),''))
  returning id into v_obra_id;

  for v_i in 0 .. jsonb_array_length(us)-1 loop
    v_u := us->v_i;
    insert into usinas (cliente_id, apelido, potencia_kwp, cidade, endereco,
                        data_instalacao, data_estimada, instalador_terceiro, ativa)
    values (v_cliente_id, btrim(v_u->>'apelido'),
            nullif(v_u->>'potencia_kwp','')::numeric,
            btrim(v_u->>'cidade'),
            nullif(btrim(coalesce(v_u->>'endereco','')),''),
            nullif(v_u->>'data_instalacao','')::date,
            coalesce((v_u->>'data_estimada')::boolean, false),
            v_origem, true)
    returning id into v_uid;
    v_ids := v_ids || v_uid;

    -- a usina tambem precisa do vinculo com a obra. 24 funcoes do pos-venda
    -- leem obra_usina, e nao usinas.cliente_id: sem esta linha a usina nasce
    -- meio conectada e some da geracao, da lista e das pendencias.
    insert into obra_usina (obra_id, usina_id, papel, medicao, principal, entrou_em)
    values (v_obra_id, v_uid, 'herdada', 'inversor_proprio', v_i = 0,
            nullif(v_u->>'data_instalacao','')::date);
  end loop;

  -- quem manda credito para quem. So depois de todas criadas, porque o alvo
  -- pode ser uma usina que ainda nao existia quando a primeira foi inserida.
  for v_i in 0 .. jsonb_array_length(us)-1 loop
    v_alvo := nullif(us->v_i->>'compensa_em_indice','')::int;
    if v_alvo is not null
       and v_alvo between 1 and coalesce(array_length(v_ids,1),0)
       and v_alvo <> v_i+1 then
      update usinas set compensa_em = v_ids[v_alvo] where id = v_ids[v_i+1];
    end if;
  end loop;

  if v_plano_cod is not null then
    insert into plano_contratos (obra_id, plano_codigo, inicio, meses, fim,
                                 valor, forma, status,
                                 nota_documento, nota_nome, observacao)
    values (v_obra_id, v_plano_cod,
            case when v_aguardando then null else v_inicio end,
            v_meses,
            case when v_aguardando then null
                 else (v_inicio + (v_meses||' months')::interval)::date end,
            v_valor, v_forma,
            case when v_aguardando then 'aguardando_pagamento' else 'ativo' end,
            v_notadoc,
            nullif(btrim(coalesce(kt->>'nota_nome','')),''),
            nullif(btrim(coalesce(kt->>'observacao','')),''))
    returning id into v_contrato_id;
  end if;

  return json_build_object('ok', true, 'simulado', false,
    'avisos', to_json(v_avisos),
    'cliente_id', v_cliente_id, 'obra_id', v_obra_id,
    'contrato_id', v_contrato_id, 'slug', v_slug,
    'usinas', coalesce(array_length(v_ids,1),0));
end;
$function$;

-- Armadilha 10: os DOIS revokes. O de public e o do anon direto.
revoke execute on function public.plano_cadastrar_cliente(jsonb, boolean) from public;
revoke execute on function public.plano_cadastrar_cliente(jsonb, boolean) from anon;
grant  execute on function public.plano_cadastrar_cliente(jsonb, boolean) to authenticated;
