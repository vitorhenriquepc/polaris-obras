-- =====================================================================
-- 2026-09-12 — Chaves de config que as telas liam sem receber, e os
--              três parâmetros do recorde que não existiam
--
-- JÁ APLICADO em dakubhcgohiwzyqiegqf, registrado no histórico do
-- Supabase como 'config_chaves_de_tela_e_parametros_recorde'.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Duas chaves que as telas leem e nunca recebiam
-- ---------------------------------------------------------------------
-- A policy da config é allowlist. painel.html lê iptu_envio_ativo e
-- financeiro.html lê provisao_posvenda_desde — as duas caíam fora da
-- lista, então o select devolvia zero linhas e a tela recebia null sem
-- erro nenhum. No painel o IPTU aparecia sempre desligado; no financeiro
-- a provisão de pós-venda ficava sem data de corte.
--
-- Continua allowlist, não denylist: cron_token, github_token,
-- anthropic_key, deploy_secret, solarview_senha e webhook_token seguem
-- fora e invisíveis para usuário logado. Conferido depois de aplicar:
-- das 117 chaves, o papel authenticated enxerga exatamente 4.

drop policy if exists config_leitura_equipe on public.config;
create policy config_leitura_equipe on public.config
  for select to authenticated
  using (
    public.is_autorizado()
    and chave = any (array[
      'agenda_token',
      'grupo_fixos',
      'iptu_envio_ativo',          -- painel.html
      'provisao_posvenda_desde'    -- financeiro.html
    ])
  );

-- ---------------------------------------------------------------------
-- 2. Três parâmetros que a função lia e que não existiam
-- ---------------------------------------------------------------------
-- recorde_do_dia() lê estas três chaves com coalesce para um número
-- chumbado. Como não existiam, o número do código sempre vencia e ninguém
-- conseguia calibrar. Os valores são exatamente os defaults que já
-- valiam, então não muda comportamento — só passa a permitir ajuste.

insert into public.config (chave, valor) values
  ('recorde_min_dias',        '90'),
  ('recorde_margem',          '0.08'),
  ('recorde_intervalo_meses', '6')
on conflict (chave) do nothing;

-- ---------------------------------------------------------------------
-- Lembrete para quem mexer aqui depois
-- ---------------------------------------------------------------------
-- A config NÃO tem policy de escrita, de propósito. Update direto vindo
-- da tela não altera nada e ainda devolve sucesso — foi assim que o
-- interruptor da régua ficou quebrado sem ninguém perceber. Para gravar,
-- use ligar_automacao(), que é security definer e confere permissão.
