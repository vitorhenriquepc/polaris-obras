-- 22/09/2026 — A usina ganha um lugar para ser corrigida.
--
-- ⚠️ ACHADO QUE MOTIVOU ESTA MIGRAÇÃO.
-- O Vitor cadastrou as duas usinas da TAYS VALESE DIAS DO PRADO no SolarView e
-- foi editar o nome e a potência aqui — e descobriu que **não existia campo**.
-- Nenhuma tela do sistema editava usina. Cadastrar tinha caminho
-- (`plano_cadastrar_cliente`, `usina_adicionar`); corrigir, nenhum.
--
-- O estrago medido em 22/09, nas duas dela:
--
--   | | no banco | certo |
--   |---|---|---|
--   | Açougue | "…AÇOUGUE" 29,25 kWp, instalada 15/03/2025 | 20,00 kWp, 10/12/2025 |
--   | Rancho  | "…RANCHO"  40,95 kWp, instalada 15/03/2025 | 38,50 kWp, 11/09/2025 |
--
-- E o furo maior, que ninguém tinha visto: **nenhuma das duas tinha linha em
-- `usina_monitoramento`**. Sem ela a usina não recebe geração do SolarView, e
-- o `solarview-vincular` nunca as alcançaria — ele só olha obra que ainda não
-- tem NENHUMA usina em `obra_usina`, e a Tays já tinha as duas ligadas. O
-- vínculo faltando pesava mais que o nome errado.
--
-- Depois de aplicado e puxada a geração: a obra dela saiu de "sem dado" para
-- **62.657 kWh · R$ 49.925 de economia · 82% de desempenho · 11 meses**.
--
-- A potência não é enfeite: ela entra no kWh/kWp que o cliente lê, e em
-- cliente de plano pesa na faixa de preço do Completo. O endereço também não:
-- é `count(distinct endereco)` que decide quantas visitas o Completo gera e
-- quantos R$ 200/ano de endereço adicional são cobrados (armadilha do §4,
-- "Endereço escrito de dois jeitos vira endereço a mais"). Por isso a função
-- devolve `avisos` dizendo cada uma dessas consequências em português, e a
-- tela simula antes de gravar (regra 3.2).
--
-- Chave ausente no json **não sobrescreve nada** (`p_json ? 'campo'`), então
-- mandar só `{usina, apelido}` mexe só no nome.

-- ── 1. usina_editar ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.usina_editar(p_json jsonb, p_simular boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_antes record;
  v_avisos text[] := '{}';
  v_mud text[] := '{}';
  v_sv text;
  v_dono uuid;
  v_ends_antes int; v_ends_depois int;
  v_novo_end text; v_nova_pot numeric;
begin
  if not public.is_autorizado() then
    return json_build_object('erro','Sem permissão para editar usina');
  end if;

  v_id := nullif(p_json->>'usina','')::uuid;
  if v_id is null then return json_build_object('erro','Falta o id da usina'); end if;

  select u.*, m.id_externo as sv_atual
    into v_antes
    from usinas u
    left join usina_monitoramento m on m.usina_id = u.id and m.ativo
   where u.id = v_id;
  if not found then return json_build_object('erro','Usina não encontrada'); end if;

  -- ── o que muda, campo a campo ──────────────────────────────────────────
  if p_json ? 'apelido' and coalesce(p_json->>'apelido','') is distinct from coalesce(v_antes.apelido,'') then
    v_mud := array_append(v_mud, ('nome: "' || coalesce(v_antes.apelido,'—') || '" → "' || coalesce(p_json->>'apelido','—') || '"'));
  end if;

  if p_json ? 'potencia_kwp' then
    v_nova_pot := nullif(p_json->>'potencia_kwp','')::numeric;
    if v_nova_pot is distinct from v_antes.potencia_kwp then
      v_mud := array_append(v_mud, ('potência: ' || coalesce(v_antes.potencia_kwp::text,'—') || ' → ' || coalesce(v_nova_pot::text,'—') || ' kWp'));
      v_avisos := array_append(v_avisos, 'A potência entra no cálculo de kWh/kWp — o desempenho que o cliente lê muda junto.'::text);
      if exists (select 1 from obra_usina ou join obras o on o.id=ou.obra_id
                  where ou.usina_id=v_id and ou.saiu_em is null
                    and coalesce(o.cliente_externo,false)) then
        v_avisos := array_append(v_avisos, 'Este é cliente de plano: a potência também pesa na faixa de preço do Completo.'::text);
      end if;
    end if;
  end if;

  if p_json ? 'data_instalacao' then
    if nullif(p_json->>'data_instalacao','')::date is distinct from v_antes.data_instalacao then
      v_mud := array_append(v_mud, ('instalada em: ' || coalesce(v_antes.data_instalacao::text,'—')
        || ' → ' || coalesce(nullif(p_json->>'data_instalacao','')::date::text,'—')));
      v_avisos := array_append(v_avisos, 'A data de instalação corta os meses anteriores a ela na geração e vale a carência de usina recém-ligada.'::text);
    end if;
  end if;

  if p_json ? 'cidade' and coalesce(p_json->>'cidade','') is distinct from coalesce(v_antes.cidade,'') then
    v_mud := array_append(v_mud, ('cidade: "' || coalesce(v_antes.cidade,'—') || '" → "' || coalesce(p_json->>'cidade','—') || '"'));
  end if;

  if p_json ? 'endereco' then
    v_novo_end := nullif(btrim(p_json->>'endereco'),'');
    if v_novo_end is distinct from v_antes.endereco then
      v_mud := array_append(v_mud, ('endereço: "' || coalesce(v_antes.endereco,'—') || '" → "' || coalesce(v_novo_end,'—') || '"'));
      -- quantos endereços distintos o cliente tem, antes e depois
      select count(distinct coalesce(u.endereco, u.cidade))
        into v_ends_antes
        from usinas u where u.cliente_id = v_antes.cliente_id and u.ativa;
      select count(distinct coalesce(case when u.id=v_id then v_novo_end else u.endereco end, u.cidade))
        into v_ends_depois
        from usinas u where u.cliente_id = v_antes.cliente_id and u.ativa;
      if v_ends_depois is distinct from v_ends_antes then
        v_avisos := array_append(v_avisos, ('Endereços distintos deste cliente: ' || v_ends_antes || ' → ' || v_ends_depois
          || '. Isso muda quantas visitas o plano Completo gera e quantos R$ de endereço adicional são cobrados.'));
      end if;
    end if;
  end if;

  -- ── o vínculo com o SolarView ──────────────────────────────────────────
  if p_json ? 'solarview_id' then
    v_sv := nullif(btrim(p_json->>'solarview_id'),'');
    if v_sv is distinct from v_antes.sv_atual then
      if v_sv is not null then
        select m.usina_id into v_dono from usina_monitoramento m
         where m.plataforma='solarview' and m.id_externo = v_sv and m.ativo and m.usina_id <> v_id limit 1;
        if v_dono is not null then
          return json_build_object('erro',
            'Essa usina do SolarView já está vinculada a outra usina daqui ('
            || coalesce((select apelido from usinas where id=v_dono),'sem nome') || ').');
        end if;
      end if;
      v_mud := array_append(v_mud, ('SolarView: ' || coalesce(v_antes.sv_atual,'sem vínculo') || ' → ' || coalesce(v_sv,'sem vínculo')));
      if v_sv is not null and v_antes.sv_atual is null then
        v_avisos := array_append(v_avisos, 'Com o vínculo, a usina passa a receber geração do SolarView na próxima rodada (diária).'::text);
      end if;
      if v_sv is null then
        v_avisos := array_append(v_avisos, 'Sem vínculo, a usina para de receber dado novo e some do monitoramento.'::text);
      end if;
    end if;
  end if;

  if array_length(v_mud,1) is null then
    return json_build_object('ok',true,'sem_mudanca',true,'usina',v_antes.apelido);
  end if;

  if p_simular then
    return json_build_object('ok',true,'simular',true,'nada_gravado',true,
      'usina',v_antes.apelido, 'mudancas',to_jsonb(v_mud), 'avisos',to_jsonb(v_avisos));
  end if;

  update usinas set
    apelido      = case when p_json ? 'apelido'      then nullif(btrim(p_json->>'apelido'),'') else apelido end,
    potencia_kwp = case when p_json ? 'potencia_kwp' then nullif(p_json->>'potencia_kwp','')::numeric else potencia_kwp end,
    cidade       = case when p_json ? 'cidade'       then nullif(btrim(p_json->>'cidade'),'') else cidade end,
    endereco     = case when p_json ? 'endereco'     then nullif(btrim(p_json->>'endereco'),'') else endereco end,
    data_instalacao = case when p_json ? 'data_instalacao' then nullif(p_json->>'data_instalacao','')::date else data_instalacao end,
    data_estimada   = case when p_json ? 'data_instalacao' then false else data_estimada end
  where id = v_id;

  if p_json ? 'solarview_id' then
    v_sv := nullif(btrim(p_json->>'solarview_id'),'');
    if v_sv is null then
      update usina_monitoramento set ativo=false where usina_id=v_id and ativo;
    else
      if exists (select 1 from usina_monitoramento where usina_id=v_id) then
        update usina_monitoramento set plataforma='solarview', id_externo=v_sv, ativo=true where usina_id=v_id;
      else
        insert into usina_monitoramento(usina_id, plataforma, id_externo, ativo)
        values (v_id, 'solarview', v_sv, true);
      end if;
    end if;
  end if;

  return json_build_object('ok',true,'usina',
    (select apelido from usinas where id=v_id),
    'mudancas',to_jsonb(v_mud), 'avisos',to_jsonb(v_avisos));
end $function$;

-- Armadilha 10: são DOIS revokes, não um. `revoke from public` não tira o
-- EXECUTE que o Supabase dá direto ao anon por `alter default privileges`.
revoke execute on function public.usina_editar(jsonb, boolean) from public;
revoke execute on function public.usina_editar(jsonb, boolean) from anon;
grant  execute on function public.usina_editar(jsonb, boolean) to authenticated;

-- ── 2. get_usina_detalhe devolve o que o lápis edita ─────────────────────────
-- Faltavam `endereco` e o id do SolarView. Sem eles a tela abriria o painel de
-- edição com os dois campos em branco — e gravar apagaria o endereço e tiraria
-- o vínculo de quem já tinha. Só isso mudou na função.

CREATE OR REPLACE FUNCTION public.get_usina_detalhe(p_usina uuid, p_dias integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_tarifa numeric;
begin
  if not is_autorizado() then return null; end if;
  select coalesce((select valor::numeric from config where chave='economia_por_kwh'),0.73) into v_tarifa;
  select json_build_object(
    'usina', json_build_object(
       'id', u.id, 'apelido', u.apelido, 'kwp', u.potencia_kwp,
       'instalada', u.data_instalacao, 'cidade', u.cidade,
       'status', u.status_atual, 'fator', u.fator_local,
       'endereco', u.endereco,
       'solarview_id', (select m.id_externo from usina_monitoramento m
                          where m.usina_id=u.id and m.ativo limit 1),
       'fator_origem', u.fator_origem, 'nota', u.nota_geracao),
    'cliente', json_build_object('id', c.id, 'nome', c.nome, 'cidade', c.cidade),
    'estado', (select json_build_object('estado', e.estado, 'motivo', e.motivo, 'gravidade', e.gravidade)
               from usina_estado(u.id) e),
    'causa', get_usina_causa(u.id),
    'obra', (select json_build_object('id', o.id, 'contrato', o.contrato, 'papel', ou.papel,
                     'conta_retorno', (fracao_polaris(o.id,u.id) > 0),
                     'saiu', (o.optout_em is not null))
             from obra_usina ou join obras o on o.id=ou.obra_id
             where ou.usina_id=u.id and ou.saiu_em is null order by ou.principal desc limit 1),
    'janela', p_dias,
    'resumo', json_build_object(
       'kwh', (select round(coalesce(sum(d.kwh),0)) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date),
       'economia', (select round(coalesce(sum(d.kwh),0) * v_tarifa) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date),
       'pct_1d', (select round(x.razao*100) from usina_dias(u.id, 3) x
                  where x.dia < current_date order by x.dia desc limit 1),
       'pct_7d', (select round(avg(x.razao)*100) from usina_dias(u.id, 7) x where x.razao is not null),
       'pct_30d', (select round(avg(x.razao)*100) from usina_dias(u.id, 30) x where x.razao is not null),
       'pct_mes', (select x.pct from usina_meses(u.id) x
                   where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
                   order by x.referencia desc limit 1)),
    'meses', (select coalesce(json_agg(json_build_object(
                 'mes', m.mes, 'previsto', m.kwh_previsto, 'fonte', m.fonte,
                 'ajustado', round(m.kwh_previsto * coalesce(u.fator_local,1)),
                 'real', (select round(g.kwh) from usina_geracao g
                          where g.usina_id=u.id and extract(month from g.referencia)=m.mes
                            and g.referencia >= date_trunc('year', current_date) limit 1)
               ) order by m.mes),'[]'::json)
              from usina_previsao m where m.usina_id=u.id),
    'historico', (select coalesce(json_agg(json_build_object(
                 'ref', to_char(x.referencia,'MM/YYYY'), 'kwh', round(x.kwh),
                 'previsto', x.previsto_ajustado, 'pct', x.pct, 'completo', x.completo
               ) order by x.referencia desc),'[]'::json)
              from usina_meses(u.id) x where x.kwh > 0),
    'dias_serie', (select coalesce(json_agg(json_build_object(
                 'dia', d.dia, 'kwh', round(d.kwh,1), 'razao', d.razao,
                 'anormal', d.anormal, 'tempo', d.tempo, 'chuva', d.chuva_mm, 'sol', d.sol_horas,
                 'esperado', round(d.esperado * coalesce(u.potencia_kwp,0), 1)
               ) order by d.dia),'[]'::json)
              from usina_dias(u.id, p_dias) d where d.dia < current_date),
    'mensagens', (select coalesce(json_agg(json_build_object(
                 'quando', t.quando, 'tipo', t.tipo) order by t.quando desc),'[]'::json)
              from (
                select o2.nps_enviado_em as quando, 'Pedido de nota' as tipo
                  from obra_usina ou2 join obras o2 on o2.id=ou2.obra_id
                 where ou2.usina_id=u.id and o2.nps_enviado_em is not null
                union all
                select n.agradecido_em, 'Agradecimento pela nota'
                  from obra_usina ou2 join nps n on n.obra_id=ou2.obra_id
                 where ou2.usina_id=u.id and n.agradecido_em is not null
                union all
                select n.lembrete_google_em, 'Pedido de avaliação'
                  from obra_usina ou2 join nps n on n.obra_id=ou2.obra_id
                 where ou2.usina_id=u.id and n.lembrete_google_em is not null
              ) t)
  ) into v
  from usinas u join clientes c on c.id=u.cliente_id
  where u.id=p_usina;
  return v;
end $function$;

-- ── 3. Conferência ───────────────────────────────────────────────────────────
-- Armadilha 2: conferido em comando SEPARADO, depois do DDL. 22/09:
--
--   ACL de usina_editar → {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   has_function_privilege('anon', 'usina_editar(jsonb,boolean)', 'execute') → false
--   get_usina_detalhe contém 'endereco' e 'solarview_id' → true / true
--
-- Simulações rodadas dentro de begin/rollback, com claims de e-mail autorizado,
-- nada gravado:
--
--   · só o endereço mudando        → 1 mudança, 0 avisos
--   · roubar o id 971574 do Açougue → erro "já está vinculada a outra usina
--                                      daqui (TAYS VALESE DIAS DO PRADO AÇOUGUE)"
--   · potência apagada             → mudança "38.5 → —" + os DOIS avisos
--                                      (kWh/kWp e faixa do Completo)
--   · json só com o id             → sem_mudanca: true
--   · usina inexistente            → erro "Usina não encontrada"
