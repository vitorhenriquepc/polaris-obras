-- 17/09/2026 — O aviso das 8h passa a falar de avaliação no Google, e com nome.
--
-- A Lívia pediu duas coisas: ver na lista quem não avaliou no Google (isso é
-- tela, foi no posvenda.html) e SER AVISADA de quem não avaliou. O aviso já
-- existia: `alerta-pendencias`, 8h de seg a sex, endereçado por papel ao
-- `resp_posvenda`. Ele já dizia "N brindes para entregar" e "N clientes sem
-- pesquisa respondida" — só número, sem nome — e não dizia nada sobre Google.
--
-- Aqui a `pendencias_posvenda()` ganha:
--   · google_pendente / google_lista  — promotor que não avaliou (o que faltava)
--   · sem_nps_lista                   — quem, não só quantos
--   · brindes_lista                   — quem, com o código do voucher
--
-- Os campos escalares (sem_nps, brindes_pendentes, sem_aniversario) continuam
-- existindo com o mesmo nome e o mesmo significado, de propósito: quem já lia
-- não quebra.
--
-- Duas correções de critério, no caminho:
--
-- 1. Trocado `etapa_numero >= 8` por `obra_ativa(o.id)`. É a regra do §6 do
--    CLAUDE.md: a trilha `manutencao` termina na etapa 4, e um corte em ">= 8"
--    deixa essas obras fora para sempre. O Jose Antonio Bassetto (manutenção,
--    etapa 4) é o caso real: ele respondeu NPS 10 em 10/09 e nunca ia aparecer
--    em nenhuma dessas contas.
--
-- 2. Acrescentado `not coalesce(cliente_externo, false)`. Cliente de plano não
--    recebe NPS (obras_para_nps corta por isso desde 15/09), então cobrá-lo de
--    "sem pesquisa respondida" é mandar a Lívia atrás de algo que o sistema
--    nunca vai deixar acontecer.
--
-- E `data_conclusao` virou `obra_ativa_em(o.id)`: a obra de manutenção do
-- Bassetto tem `data_conclusao` NULA, e `current_date - null` é null — a
-- comparação sumia em silêncio.
--
-- O corte de dias do Google reusa `config.lembrete_google_dias` (3), que até
-- agora só era lido pela `nps_para_lembrete_google()` — função sem nenhum
-- chamador. A chave volta a ter um leitor vivo.

create or replace function public.pendencias_posvenda()
returns json
language sql
security definer
set search_path to 'public'
as $function$
  select json_build_object(
    'respostas', (select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contexto', m.contexto,
        'horas', round(extract(epoch from (now()-m.recebida_em))/3600)
      ) order by m.recebida_em), '[]'::json)
      from mensagens_recebidas m join obras o on o.id = m.obra_id
      where m.lida_em is null and m.da_equipe = false),

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

    -- O QUE FALTAVA: promotor que ainda não avaliou no Google.
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

-- Armadilha 10: os DOIS revokes. Só a edge function (service_role) lê isto.
revoke execute on function public.pendencias_posvenda() from public;
revoke execute on function public.pendencias_posvenda() from anon;
revoke execute on function public.pendencias_posvenda() from authenticated;
grant  execute on function public.pendencias_posvenda() to service_role;
