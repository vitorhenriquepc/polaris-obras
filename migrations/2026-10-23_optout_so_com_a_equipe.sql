-- Opt-out só com a equipe (Vitor, 23/10: "pode fazer a sua recomendação").
--
-- Até aqui, quando a IA do webhook lia uma mensagem como `sair`, o
-- registrar_optout rodava na hora, sem ninguém confirmar. Os 3 opt-outs
-- automáticos da história eram falsos: RENATO WATANABE (4582) com "Vou sair daqui
-- a pouco" (14/08) e "Hoje vou sair" (18/09) — avisava que não estaria em casa —
-- e JOAO RILLO (4220) com "Por favor, mantenha-me informado" (21/10). Os dois
-- ficaram fora da régua e da escada da Isabela.
--
-- O webhook (v6, publicado junto) para de tirar o cliente: a IA só marca o recado
-- como `sair` e a pós-venda é avisada no privado. Aqui, no banco:
--
--   1. regua_bloqueio segura a régua por `optout_ia_segura_dias` (3) depois de um
--      recado `sair` do cliente, enquanto a equipe não decide. Se ele pediu mesmo,
--      nada sai por cima até a Lívia registrar a saída; se não pediu, a régua
--      volta sozinha. Qualquer registro em `consentimentos` depois do recado (a
--      saída confirmada, ou a saída desfeita) encerra a espera na hora.
--
--   2. registrar_optin_manual vira também o "desfazer saída" da ficha:
--      · quem já tinha autorizado (termo, WhatsApp) mantém a data e a origem da
--        autorização — antes ela era trocada por "agora, manual";
--      · a régua cancelada por causa do opt-out (bloqueio_motivo "cliente pediu
--        para sair…") e ainda no prazo volta para `pendente`. Mensagem com o prazo
--        vencido fica como está;
--      · o registro em `consentimentos` diz que é a saída sendo desfeita, e de
--        quando era o opt-out.
--      A assinatura não muda: a ficha chama com (p_obra, p_origem).
--
-- Testado antes num Postgres descartável com as linhas reais do Renato e do JOAO
-- RILLO (régua, recados e consentimentos): Renato volta com 5 mensagens (d75 de
-- 26/10 em diante; o d30 e o d45 já venceram), JOAO RILLO volta sem mexer na régua
-- (o d365 dele nunca foi cancelado), a autorização original dos dois fica, e a
-- espera de 3 dias funciona e se encerra com o registro da equipe.

insert into config (chave, valor)
values ('optout_ia_segura_dias', '3')
on conflict (chave) do nothing;

create or replace function public.regua_bloqueio(p_obra uuid, p_modelo text)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_o record; v_m record; v_meses int;
begin
  select * into v_o from obras where id = p_obra;
  select * into v_m from regua_modelos where codigo = p_modelo;
  if v_o is null or v_m is null then return 'registro inexistente'; end if;

  if v_o.whatsapp_grupo_id is null then return 'sem grupo de WhatsApp'; end if;
  if v_o.optout_em is not null then return 'cliente pediu para sair'; end if;

  -- A IA leu "quer sair das mensagens" e a equipe ainda não decidiu: a régua
  -- espera. Confirmada a saída, vale o optout_em acima; desfeita, ou passado o
  -- prazo sem decisão, a régua segue.
  if exists (select 1 from mensagens_recebidas m
             where m.obra_id = p_obra and m.contexto = 'sair' and m.da_equipe = false
               and m.recebida_em > now() - make_interval(days =>
                     coalesce((select valor::int from config where chave = 'optout_ia_segura_dias'), 3))
               and m.recebida_em > coalesce((select max(c.registrado_em) from consentimentos c
                                             where c.obra_id = p_obra), '-infinity'::timestamptz)) then
    return 'pediu para sair? a equipe ainda não confirmou';
  end if;

  if v_m.condicao = 'com_optin' and (v_o.optin_em is null) then
    return 'sem autorização para marketing';
  end if;

  if v_m.condicao = 'sem_indicacao' then
    if v_o.optin_em is null then return 'sem autorização para marketing'; end if;
    -- indicação de verdade (mesmo registrada sem mensagem) ou recado classificado
    -- como indicação; "não era indicação" (descartada) não conta
    if exists (select 1 from mensagens_recebidas m
               where m.obra_id = p_obra and m.contexto = 'indicacao')
       or exists (select 1 from indicacoes i
               where i.indicador_obra_id = p_obra and coalesce(i.status, '') <> 'descartada') then
      return 'cliente já indicou';
    end if;
  end if;

  if v_m.condicao = 'requer_geracao' or v_m.codigo = 'd365_aniversario' then
    select t.meses into v_meses from public.obra_geracao_total(p_obra) t;
    if coalesce(v_meses,0) = 0 then return 'geração não registrada'; end if;
  end if;

  return null;
end; $function$;

create or replace function public.registrar_optin_manual(p_obra uuid, p_origem text default 'manual'::text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_txt text; v_o record; v_reativadas int := 0; v_nota text;
begin
  if not public.is_autorizado() then return json_build_object('erro','Não autorizado'); end if;
  select id, optin_em, optin_origem, optout_em, optout_origem into v_o from obras where id = p_obra;
  if v_o.id is null then return json_build_object('erro','Obra não encontrada'); end if;
  select valor into v_txt from config where chave = 'optin_texto';

  -- Quem já tinha autorizado mantém a data e a origem da autorização; o que sai
  -- é só o opt-out.
  update obras set optin_em     = coalesce(optin_em, now()),
                   optin_texto  = case when optin_em is null then v_txt else optin_texto end,
                   optin_origem = case when optin_em is null then p_origem else optin_origem end,
                   optout_em = null, optout_origem = null
  where id = p_obra;

  if v_o.optout_em is not null then
    -- a régua cancelada por causa do opt-out, e ainda no prazo, volta
    update regua_contatos set status = 'pendente', bloqueio_motivo = null
     where obra_id = p_obra and status = 'cancelado'
       and bloqueio_motivo like 'cliente pediu para sair%'
       and data_limite >= current_date;
    get diagnostics v_reativadas = row_count;
    v_nota := 'Saída desfeita pela equipe: o opt-out de '
      || to_char(v_o.optout_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      || ' (' || coalesce(v_o.optout_origem, 'sem origem') || ') não valia.'
      || case when v_o.optin_em is not null
              then ' Continua valendo a autorização de '
                   || to_char(v_o.optin_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
                   || ' (' || coalesce(v_o.optin_origem, 'sem origem') || ').'
              else '' end;
  end if;

  insert into consentimentos (obra_id, acao, texto, origem)
  values (p_obra, 'optin', coalesce(v_nota, v_txt), p_origem);

  return json_build_object('ok', true, 'desfez_saida', v_o.optout_em is not null,
                           'regua_reativada', v_reativadas);
end; $function$;
