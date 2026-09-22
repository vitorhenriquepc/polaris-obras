-- 22/09/2026 — A Lívia passa a ver, todo dia, a usina que parou.
--
-- ⚠️ O VÃO
-- O aviso das 8h cobria mensagem sem resposta, Google pendente, brinde, NPS,
-- aniversário e indicação. **Não tinha nenhuma seção de usina parada.**
--
-- O que mais se parecia com isso era `geracao_faltando`, e ela é outra coisa:
-- obra ativa há **31 a 60 dias** e sem NENHUMA linha em `usina_geracao` — ou
-- seja, furo de cadastro. Tem teto de 60 dias, então o caso do João Vitor
-- (57 dias sem gerar) ia sumir do aviso no dia 61, sem ninguém ter agido.
--
-- Medido em 22/09: das três usinas com problema real, **só uma** aparecia no
-- aviso diário. LUCINEI BOMFIM (Votuporanga, nunca gerou em 5 meses) e
-- JOAO JOSE DE SOUZA (Araçatuba 6,20, parada desde 22/08) não apareciam em
-- lugar nenhum. E as três foram avisadas ao cliente em **10/09** — doze dias
-- sem desfecho, sem nada cobrando.
--
-- Pior: até a correção do índice único (migração desta mesma data), as três
-- já tinham gasto a única `usina_wifi` da vida em 10/09 e **não podiam nem
-- receber outra mensagem**. O sistema tinha ficado sem caminho nenhum para
-- levantá-las.
--
-- ✅ `usinas_paradas` usa a `usina_estado` como fonte única — não reimplementa
-- critério — e traz `avisado_ha`, que é a pergunta que faltava: "o cliente já
-- foi avisado, e faz quanto tempo?".
--
-- ⚠️ Duas decisões de propósito:
--
-- 1. **`dias` fica NULO em usina que nunca foi medida.** Para as quatro do
--    UNI AUTO e da Tays a conta por `data_instalacao` daria "1666 dias sem
--    gerar" — número que mente: elas não pararam, elas nunca existiram no
--    SolarView. Nulo ali é a resposta honesta (mesma lição da armadilha 5).
--
-- 2. **Cliente de plano NÃO é excluído aqui**, ao contrário de todas as outras
--    seções. Monitorar a usina é exatamente o que ele paga — calar a usina da
--    Tays seria calar o produto. Por isso não há `cliente_externo` no filtro.
--
-- O corte é `parada_avisa_dias` (7), para o ruído de datalogger do dia não
-- entrar: em 22/09 havia cinco usinas em "sem comunicação" que geraram ontem.
--
-- A `alerta-pendencias` foi republicada junto (`verify_jwt: false` conferido,
-- curl com token errado devolvendo 403) para desenhar a seção — dado que a
-- tela não lê é a armadilha 17 ao contrário.

insert into config (chave, valor)
select 'parada_avisa_dias', '7'
where not exists (select 1 from config where chave='parada_avisa_dias');

CREATE OR REPLACE FUNCTION public.pendencias_posvenda()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'respostas', (select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contexto', m.contexto,
        'horas', round(extract(epoch from (now()-m.recebida_em))/3600)
      ) order by m.recebida_em), '[]'::json)
      from mensagens_recebidas m join obras o on o.id = m.obra_id
      where m.lida_em is null and m.da_equipe = false),

    -- A usina que parou. Fonte unica do estado: usina_estado.
    -- `dias` nulo = nunca foi medida (nao existe no SolarView), nao "parada ha
    -- N dias" — numero por data_instalacao ali seria invencao.
    -- Cliente de plano NAO e excluido: monitorar a usina e o que ele paga.
    'usinas_paradas', (select coalesce(json_agg(t order by
                                t.avisado_ha desc nulls last, t.dias desc nulls last), '[]'::json) from (
      select o.cliente, o.contrato, u.apelido as usina, u.potencia_kwp as kwp,
             e.estado,
             (current_date - max(d.dia) filter (where d.kwh > 0.5))        as dias,
             (max(d.dia) filter (where d.kwh > 0.5) is null)               as nunca_gerou,
             (current_date - u.cliente_avisado_em::date)                   as avisado_ha
      from usinas u
      join obra_usina ou on ou.usina_id = u.id and ou.saiu_em is null
      join obras o on o.id = ou.obra_id
      left join usina_dia d on d.usina_id = u.id
      left join lateral public.usina_estado(u.id) e on true
      where u.ativa
        and e.estado in ('parada','nunca gerou','crítico','sem comunicação','sem dado')
      group by o.cliente, o.contrato, u.apelido, u.potencia_kwp,
               u.data_instalacao, u.cliente_avisado_em, e.estado
      having coalesce(
               current_date - max(d.dia) filter (where d.kwh > 0.5),
               current_date - u.data_instalacao
             ) >= coalesce((select valor::int from config where chave='parada_avisa_dias'), 7)
      limit 15) t),

    'geracao_faltando', (select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'dias', current_date - public.obra_ativa_em(o.id)
      ) order by public.obra_ativa_em(o.id)), '[]'::json)
      from obras o
      where public.obra_ativa(o.id)
        and not coalesce(o.cliente_externo, false)
        and public.obra_ativa_em(o.id) is not null
        and (current_date - public.obra_ativa_em(o.id)) between 31 and 60
        and not exists (select 1 from obra_usina ou join usina_geracao g on g.usina_id = ou.usina_id
                        where ou.obra_id = o.id)),

    'sem_aniversario', (select count(*) from obras o
      where public.obra_ativa(o.id)
        and not coalesce(o.cliente_externo, false)
        and o.nascimento_dia is null),

    'sem_nps', (select count(*) from obras o
      where public.obra_ativa(o.id)
        and not coalesce(o.cliente_externo, false)
        and public.obra_ativa_em(o.id) is not null
        and (current_date - public.obra_ativa_em(o.id)) > 10
        and not exists (select 1 from nps n where n.obra_id = o.id)),

    'sem_nps_lista', (select coalesce(json_agg(t order by t.dias desc), '[]'::json) from (
      select o.cliente, o.contrato, (current_date - public.obra_ativa_em(o.id)) as dias
      from obras o
      where public.obra_ativa(o.id)
        and not coalesce(o.cliente_externo, false)
        and public.obra_ativa_em(o.id) is not null
        and (current_date - public.obra_ativa_em(o.id)) > 10
        and not exists (select 1 from nps n where n.obra_id = o.id)
      limit 10) t),

    'brindes_pendentes', (select count(*) from nps n
      where n.voucher is not null and n.entregue_em is null),

    'brindes_lista', (select coalesce(json_agg(t order by t.dias desc), '[]'::json) from (
      select o.cliente, o.contrato, n.brinde, n.voucher,
             (current_date - n.brinde_em::date) as dias,
             (n.avaliou_google_em is not null) as avaliou
      from nps n join obras o on o.id = n.obra_id
      where n.voucher is not null and n.entregue_em is null
      limit 10) t),

    'google_pendente', (select count(*) from nps n join obras o on o.id = n.obra_id
      where n.nota >= 9 and n.avaliou_google_em is null
        and not coalesce(o.cliente_externo, false)
        and public.obra_ativa(o.id)
        and n.criado_em <= now() - ((select valor::int from config where chave='lembrete_google_dias') || ' days')::interval),

    'google_lista', (select coalesce(json_agg(t order by t.dias desc), '[]'::json) from (
      select o.cliente, o.contrato, n.nota,
             (current_date - n.criado_em::date) as dias,
             n.brinde, n.voucher,
             (n.lembrete_google_em is not null) as ja_convidado
      from nps n join obras o on o.id = n.obra_id
      where n.nota >= 9 and n.avaliou_google_em is null
        and not coalesce(o.cliente_externo, false)
        and public.obra_ativa(o.id)
        and n.criado_em <= now() - ((select valor::int from config where chave='lembrete_google_dias') || ' days')::interval
      limit 10) t),

    'indicacoes_pendentes', (select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'indicado', m.nome_indicado,
        'horas', round(extract(epoch from (now()-m.recebida_em))/3600)
      ) order by m.recebida_em), '[]'::json)
      from mensagens_recebidas m join obras o on o.id = m.obra_id
      where m.lida_em is null and m.da_equipe = false and m.contexto = 'indicacao')
  );
$function$;

-- ── Conferência (comando SEPARADO, depois — armadilha 2) ────────────────────
-- 'usinas_paradas' na definição gravada .... true
-- 'parada_avisa_dias' na definição ......... true
-- 'google_lista' ainda lá (resto intacto) .. true
-- config.parada_avisa_dias ................. 7
--
-- Saída real em 22/09, dentro de begin/rollback: 7 linhas, as três de
-- problema real primeiro (avisado_ha = 12 nas três), depois as quatro de
-- cadastro pendente com dias = null.
--
-- Texto final conferido pelo `simular` da alerta-pendencias, sem enviar:
--   🛑 *7 usinas sem gerar*
--   • JOAO JOSE DE SOUZA #4321 — Araçatuba 6,2 kWp · parada há 31 dias · avisado há 12 dias
--   • LUCINEI BOMFIM DOS SANTOS #4201 — Votuporanga 6,25 kWp · nunca gerou · avisado há 12 dias
--   • João Vitor Torres Pozzeti #4425 — Araçatuba 8,68 kWp · nunca gerou · avisado há 12 dias
--   • UNI AUTO POSTO — USINA 1 105,4 kWp · não existe no SolarView · _cliente ainda não avisado_
