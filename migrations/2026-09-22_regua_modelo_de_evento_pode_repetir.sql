-- 22/09/2026 — Mensagem de EVENTO volta a poder acontecer de novo.
--
-- ⚠️ O QUE ESTAVA ERRADO
-- `regua_contatos` tinha `UNIQUE (obra_id, modelo)`: uma mensagem de cada tipo
-- por obra, PARA SEMPRE. Isso é exatamente certo para a régua de calendário —
-- é o que impede boas-vindas de repetir, e o CLAUDE.md registra como recurso.
-- Só que o índice não distinguia as duas famílias de modelo:
--
--   CALENDÁRIO  d2_boasvindas … d365_aniversario, reconexao_setembro,
--               relatorio_aceite — 10 modelos, 471 linhas. Acontecem uma vez
--               na vida da obra. O índice está CERTO neles.
--
--   EVENTO      usina_wifi, usina_parada, geracao_baixa, geracao_recorde,
--               geracao_resumo, retorno_marco — 6 modelos, 14 linhas.
--               São condições que VOLTAM. A usina pode parar de novo no ano
--               que vem. O índice os calava para sempre depois do primeiro.
--
-- Medido em 22/09: **9 obras** já tinham `usina_wifi` (6 enviadas, 3 puladas)
-- e nunca mais poderiam receber outro aviso de usina sem comunicar. O GILBERTO
-- teve uma `geracao_baixa` recusada em 15/09 e estava mudo desde então.
--
-- Provado, não deduzido: insert de uma segunda `usina_wifi` na mesma obra
-- devolvia `duplicate key value violates unique constraint
-- "regua_contatos_obra_id_modelo_key"`.
--
-- ⚠️ E a falha era SILENCIOSA. O `mensagens-usina-auto` só deduplica olhando
-- os últimos 7 dias (`data_programada >= desde`), então depois desse prazo ele
-- TENTA inserir de novo, leva o unique_violation, joga em `erros[]` e devolve
-- 200. O cron usa `net.http_post`, que não lê a resposta. Ninguém saberia.
--
-- ⚠️ E havia uma mina para outubro: `geracao_resumo` (o resumo mensal, cron do
-- dia 5) tem ZERO linhas porque nunca rodou. A primeira rodada inseriria uma
-- por obra — e TODO mês seguinte falharia calado, para sempre. Uma mensagem
-- "mensal" que acontece uma vez por obra na vida.
--
-- ✅ SEGURANÇA: os 6 modelos de evento são todos `precisa_aprovacao = true`
-- (conferido). Destravar não põe nada na frente de cliente nenhum sem a Lívia.
-- A regra 3.5 continua inteira. Quem segura a repetição é a janela do
-- `mensagens-usina-auto`: `msg_ia_intervalo_urgente` (7 dias) para os urgentes
-- e `msg_ia_intervalo_dias` (20) para os de cortesia.

-- 1. A propriedade mora no MODELO, não no código.
alter table regua_modelos add column if not exists repetivel boolean not null default false;

comment on column regua_modelos.repetivel is
  'true = a condição volta (a usina parou de novo, novo marco de retorno, resumo do mês seguinte). '
  'false = acontece uma vez na vida da obra (boas-vindas, aniversário de 1 ano). '
  'É este campo que decide se o índice único (obra_id, modelo) vale para o modelo.';

update regua_modelos set repetivel = true
 where codigo in ('usina_wifi','usina_parada','geracao_baixa',
                  'geracao_recorde','geracao_resumo','retorno_marco');

-- 2. Espelho em regua_contatos: índice parcial não consegue ler outra tabela.
alter table regua_contatos add column if not exists repetivel boolean not null default false;

update regua_contatos c
   set repetivel = m.repetivel
  from regua_modelos m
 where m.codigo = c.modelo
   and c.repetivel is distinct from m.repetivel;

create or replace function public.trg_regua_repetivel()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  select coalesce(m.repetivel, false) into new.repetivel
    from regua_modelos m where m.codigo = new.modelo;
  new.repetivel := coalesce(new.repetivel, false);
  return new;
end $function$;

revoke execute on function public.trg_regua_repetivel() from public;
revoke execute on function public.trg_regua_repetivel() from anon;

drop trigger if exists trg_regua_repetivel on regua_contatos;
create trigger trg_regua_repetivel
before insert or update of modelo on regua_contatos
for each row execute function public.trg_regua_repetivel();

-- 3. O índice único passa a valer só para quem acontece uma vez.
alter table regua_contatos drop constraint if exists regua_contatos_obra_id_modelo_key;
drop index if exists public.regua_contatos_obra_id_modelo_key;

create unique index regua_contatos_uma_por_obra
  on regua_contatos (obra_id, modelo) where not repetivel;

comment on index public.regua_contatos_uma_por_obra is
  'Uma mensagem por modelo por obra — para os modelos de CALENDÁRIO. '
  'É o que impede a régua de repetir boas-vindas. Modelo de EVENTO (repetivel = true) '
  'fica de fora: a usina pode parar de novo. Quem segura a repetição deles é a janela '
  'do mensagens-usina-auto (msg_ia_intervalo_urgente / msg_ia_intervalo_dias).';

-- ── Conferência (comando SEPARADO, depois — armadilha 2) ────────────────────
-- índice novo   CREATE UNIQUE INDEX regua_contatos_uma_por_obra ... WHERE (NOT repetivel)
-- índice velho  0 (sumiu)
-- modelos repetíveis 6 · linhas marcadas 14 · divergentes 0 · trigger no ar 1
-- ACL do trigger  {postgres=X/postgres, authenticated=X/postgres, service_role=X/postgres}
--                 — o gabarito da armadilha 10, sem anon
--
-- Teste dos dois lados, dentro de bloco que deu rollback, sem gravar nada:
--   usina_wifi    INSERIU ✓ (trigger marcou repetivel = true)
--   d2_boasvindas BLOQUEADO ✓ (proteção do calendário intacta)
