-- 2026-09-17 — O laudo de manutenção: três furos fechados
--
-- CONTEXTO
-- O laudo de manutenção JA EXISTIA e ja rodou ponta a ponta uma vez: o Jose
-- Antonio Bassetto (corretiva, 19/08) tem 35 fotos e videos, 1 apontamento
-- ("Limpeza nao realizada pois orcamento nao aprovado") e o termo assinado em
-- 07/09. A checklist de manutencao tem 11 itens proprios, o
-- get_relatorio_publico ja filtra por trilha, e o relatorio.html ja muda o
-- titulo para "Relatorio de Manutencao Corretiva".
--
-- O que faltava eram tres coisas, levantadas em 17/09 a pedido do Vitor.

-- ---------------------------------------------------------------------------
-- 1. Obrigatoriedade por tipo de manutencao
-- ---------------------------------------------------------------------------
-- Os 9 obrigatorios eram os mesmos para preventiva, corretiva e diagnostico.
-- O Jose Antonio ficou 8 de 9 porque "Limpeza executada" e cobrada mesmo numa
-- corretiva em que a limpeza NAO foi aprovada -- o proprio apontamento dele diz
-- isso. Item obrigatorio que nao se aplica vira cobranca falsa no grupo do
-- instalador, pela obras_cobranca_fotos().
--
--   alter table checklist_itens add column obrig_tipos text[];
--   checklist_exige(obrigatorio, obrig_tipos, tipo_manutencao)
--
-- Nulo em obrig_tipos = vale para todos os tipos (o comportamento de sempre).
-- So "Limpeza executada" foi marcada, com array['preventiva'].
--
-- A regra entrou nas TRES funcoes que liam ci.obrigatorio:
--   get_status_relatorio()   -- o contador do painel
--   obras_cobranca_fotos()   -- quem cobra o instalador no grupo
--   get_obra_instalador()    -- a estrela que ele ve no celular
--
-- Medido depois, como anon (o instalador nao tem login):
--   Jose Antonio, corretiva: 9 -> 8 obrigatorios, limpeza = false
--   Fatima Rino, preventiva: 9 obrigatorios, limpeza continua valendo

-- ---------------------------------------------------------------------------
-- 2. A visita do plano puxa o laudo da obra
-- ---------------------------------------------------------------------------
-- laudo_url era colado na mao ("cole o link do relatorio") e estava em ZERO das
-- visitas -- enquanto o sistema ja gera um laudo completo para a obra. Para
-- cliente de plano a ligacao e direta: plano_contratos.obra_id E a obra de
-- manutencao dele.
--
--   config.relatorio_base_url  = https://obras.polarisenergiasolar.com/relatorio.html
--   plano_visita_laudo_da_obra(visita) -> url, ou NULL se a obra nao tem foto
--   plano_visita_registrar(...)        -- cai nela quando ninguem colou link,
--                                         e devolve laudo_automatico: true
--
-- ⚠️ Relatorio SEM FOTO nao vira laudo de proposito: mandar o link seria pior
-- que nao mandar, porque o cliente abriria uma pagina vazia.
--
-- Testado em begin/rollback: com uma foto na obra do UNI AUTO, registrar a
-- visita sem colar link devolveu
--   laudo: https://obras.polarisenergiasolar.com/relatorio.html?id=uni-auto-posto-de-aracatuba-ltda
--   laudo_automatico: true
-- e sem foto devolve null, que e o estado real hoje. O rollback foi conferido
-- depois: 0 fotos, visita ainda 'prevista', laudo nulo.
--
-- ⚠️ LIMITE CONHECIDO: uma obra tem UM relatorio. Se o mesmo contrato tiver
-- visitas em anos diferentes, todas vao apontar para o mesmo link, que sera o
-- acumulado da obra. Resolve quando existir visita com relatorio proprio;
-- hoje ha 1 visita prevista no sistema inteiro, entao nao aperta.

-- ---------------------------------------------------------------------------
-- 3. Os textos do laudo (em relatorio.html, nao aqui)
-- ---------------------------------------------------------------------------
-- A capa dizia "INSTALACAO 17/08/2026" num laudo de manutencao. Mais tres:
-- o aviso de foto faltando, a nota dos apontamentos ("antes ou durante a
-- instalacao") e o termo pendente. E a mensagem de WhatsApp que leva o link
-- falava em "dados tecnicos da usina e termo de conclusao".
-- Medido depois no Chromium: laudo de manutencao com ZERO ocorrencias de
-- "instalacao"; o de instalacao segue com as 5 de sempre.

alter table checklist_itens add column if not exists obrig_tipos text[];

comment on column checklist_itens.obrig_tipos is
  'Quando o item e obrigatorio SO em alguns tipos de manutencao. Nulo = vale para todos os tipos.';

create or replace function public.checklist_exige(p_obrigatorio boolean,
                                                  p_obrig_tipos text[],
                                                  p_tipo_manutencao text)
returns boolean
language sql immutable
as $function$
  select coalesce(p_obrigatorio,false)
     and (p_obrig_tipos is null or p_tipo_manutencao = any(p_obrig_tipos));
$function$;

revoke execute on function public.checklist_exige(boolean, text[], text) from public;
revoke execute on function public.checklist_exige(boolean, text[], text) from anon;
grant  execute on function public.checklist_exige(boolean, text[], text) to authenticated;

update checklist_itens set obrig_tipos = array['preventiva']
 where trilha='manutencao' and titulo='Limpeza executada';

insert into config (chave, valor)
select 'relatorio_base_url', 'https://obras.polarisenergiasolar.com/relatorio.html'
where not exists (select 1 from config where chave='relatorio_base_url');

-- As definicoes completas de get_status_relatorio, obras_cobranca_fotos,
-- get_obra_instalador, plano_visita_laudo_da_obra e plano_visita_registrar
-- foram aplicadas pelo MCP e estao no banco; ver pg_get_functiondef.

-- ---------------------------------------------------------------------------
-- 4. Cada visita com a SUA obra (17/09, decisao do Vitor no mesmo dia)
-- ---------------------------------------------------------------------------
-- O limite do item 2 -- uma obra, um relatorio, entao visitas de anos
-- diferentes cairiam no mesmo link -- foi resolvido em vez de documentado.
--
-- Nao precisou de relatorio de visita: obra de manutencao JA tem link do
-- instalador, checklist de 11 itens, fotos, apontamentos e relatorio publico.
-- A visita so precisava de uma obra para chamar de sua.
--
--   plano_visita.obra_id -> obras(id)
--   plano_visita_abrir_obra(visita, simular)
--   plano_visita_laudo_da_obra() agora olha a obra DA VISITA primeiro, e so
--     cai na obra do contrato quando a visita ainda nao tem a dela
--   get_plano_visitas() devolve obra_visita, o slug, e quantos itens
--     obrigatorios ja tem foto -- e 'sem_obra' no resumo
--
-- Seguro do lado financeiro: abre_financeiro_obra() nasce com dispensado=true
-- para QUALQUER obra de trilha 'manutencao'.
--
-- Testado em begin/rollback, com a visita real do UNI AUTO (16/12/2026):
--   abrir .................. slug uni-auto-...-visita-2026-12
--   abrir 2x ............... recusado, nomeando a obra que ja existe
--   a obra criada .......... trilha manutencao, etapa 1, preventiva,
--                            grupo herdado, token do instalador gerado,
--                            ficha dispensada, endereco e data da visita
--   laudo sem foto ......... nulo
--   laudo com foto ......... relatorio.html?id=uni-auto-...-visita-2026-12
--   registrar a visita ..... laudo_automatico: true
-- Rollback conferido depois: 0 obras de visita, visita ainda 'prevista'.

alter table plano_visita add column if not exists obra_id uuid references obras(id);

comment on column plano_visita.obra_id is
  'A obra de manutencao desta visita. E dela que sai o laudo. Nula = visita ainda nao aberta como obra.';

-- plano_visita_abrir_obra, a nova plano_visita_laudo_da_obra e a
-- get_plano_visitas foram aplicadas pelo MCP; ver pg_get_functiondef.
