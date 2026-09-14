-- APLICADA em 14/09/2026 (`nps_e_google_so_depois_da_ativacao`).
-- Pedido do Vitor: o NPS e o convite do Google têm de sair só depois da
-- ATIVAÇÃO, nunca depois da vistoria.

-- ============================================================
-- O que estava errado
-- ============================================================
-- `obras_para_nps()` tinha duas condições somadas por OR:
--
--   (1) etapa_numero >= 8 e data_conclusao há pelo menos 1 dia   ← ativação, certo
--   (2) aceite_em há pelo menos 2 dias                            ← termo assinado
--
-- O termo é assinado na VISTORIA. Na trilha padrão:
--
--   etapa 7 = "Vistoria e Conexão"
--   etapa 8 = "Sistema Ativo!"
--
-- Então a condição (2) fazia o NPS sair com o sistema ainda desligado.
--
-- NÃO ERA TEÓRICO — três obras receberam assim:
--   VALDETE LOPES RAMOS (4791) ..... etapa 7, NPS em 11/09, respondeu nota 10
--   SANDRA M. F. BARCDUCCI (4739) .. etapa 7, NPS em 12/09, sem resposta
--   Jose Antonio Bassetto Junior ... trilha manutenção, etapa 4
--
-- E o Google vinha atrás: `nps_para_lembrete_google()` só exigia nota >= 9,
-- então a VALDETE já estava na fila para receber o convite de avaliar no
-- Google com a usina dela desligada.

-- ============================================================
-- Por que não bastava apagar a condição (2)
-- ============================================================
-- A trilha `manutencao` vai de 0 a 4 — não existe etapa 8 nela. Um corte seco
-- em ">= 8" faria manutenção NUNCA mais receber NPS, em silêncio. O caso do
-- Bassetto estava CERTO: manutenção não tem ativação, o fim dela é a etapa 4
-- ("Concluída").

-- ============================================================
-- A regra nova
-- ============================================================
-- A obra chegou na ÚLTIMA ETAPA DA PRÓPRIA TRILHA:
--
--   padrao ....... 8   "Sistema Ativo!"
--   eletroposto .. 8   "Eletroposto em Operação!"
--   manutencao ... 4   "Concluída"
--
-- Conserta a padrão, preserva a manutenção, e não quebra se amanhã uma trilha
-- nova tiver outra quantidade de etapas.
--
-- E a data? `data_conclusao` está NULA nas três obras acima, inclusive na de
-- manutenção. Então a espera de 1 dia passa a contar de
-- coalesce(data_conclusao, quando entrou na última etapa), lido do
-- `etapas_historico` — que existe para todas.
--
-- SIMULADO ANTES (transação + rollback):
--   fila do NPS ....... 0 antes, 0 depois (ninguém novo dispara)
--   fila do Google .... 2 antes, 1 depois — a VALDETE saiu; ficou só o
--                       Bassetto, manutenção concluída de verdade
-- CONFERIDO DEPOIS DE APLICAR: idêntico.

create or replace function public.obras_para_nps()
 returns table(id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id
  from obras o
  cross join lateral (
    select coalesce((select max(e.numero) from etapas e where e.trilha = o.trilha), 8) as etapa_final
  ) t
  where o.nps_enviado_em is null
    and o.whatsapp_grupo_id is not null
    -- chegou na última etapa da trilha dela (a ativação, na padrão)
    and o.etapa_numero >= t.etapa_final
    -- e já faz pelo menos 1 dia
    and coalesce(o.data_conclusao,
                 (select max(h.entrou_em)::date from etapas_historico h
                   where h.obra_id = o.id and h.etapa_numero >= t.etapa_final))
        <= current_date - 1
  limit 20;
$function$;

create or replace function public.nps_para_lembrete_google()
 returns table(obra_id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text, brinde text, voucher text, lembretes smallint)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id,
         n.brinde, n.voucher, n.lembretes_google
  from nps n
  join obras o on o.id = n.obra_id
  cross join lateral (
    select coalesce((select max(e.numero) from etapas e where e.trilha = o.trilha), 8) as etapa_final
  ) t
  where n.nota >= 9
    -- trava nova: não pede Google antes da obra chegar no fim da trilha dela.
    -- Protege quem recebeu o NPS cedo pelo bug acima.
    and o.etapa_numero >= t.etapa_final
    and n.avaliou_google_em is null
    and o.whatsapp_grupo_id is not null
    and n.lembretes_google < (select valor::int from config where chave = 'lembrete_google_max')
    and coalesce(n.lembrete_google_em, n.criado_em)
        <= now() - ((select valor::int from config where chave = 'lembrete_google_dias') || ' days')::interval
  limit 20;
$function$;

-- ============================================================
-- O que NÃO foi feito, de propósito — decisão do Vitor
-- ============================================================
-- As duas obras da trilha padrão que receberam o NPS cedo continuam com
-- `nps_enviado_em` preenchido, então nunca mais receberão. Zerar o campo faria
-- o sistema mandar uma SEGUNDA mensagem ao cliente, e pela regra 3.5 isso não
-- sai sem decisão humana. Os dois casos são diferentes:
--
--   SANDRA (4739), sem resposta — faz sentido perguntar de novo depois de
--   ativar. Para reabrir:
--     update obras set nps_enviado_em = null where contrato = '4739';
--
--   VALDETE (4791), já respondeu nota 10 — perguntar de novo seria estranho.
--   O convite do Google para ela volta sozinho quando a obra chegar na etapa 8.
