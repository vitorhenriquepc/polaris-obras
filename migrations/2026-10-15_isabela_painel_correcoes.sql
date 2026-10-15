-- Isabela: o que a tela de correções precisa (15/10, "Sim pode fazer" do Vitor).
--
-- O aprendizado existia desde 14/10 (atendimento_ensinar → atendimento_exemplo →
-- prompt da decisão seguinte), mas sem tela ninguém corrigia e a tabela de
-- exemplos tinha 0 linhas. A aba "Isabela" do posvenda.html passa a mostrar as
-- esperas e oferecer "Falei por fora", "Não precisava", "Foi útil" e, nas que
-- ela descartou, "Precisava responder".
--
-- 1) atendimento_painel(dias): as esperas abertas + as fechadas nos últimos
--    `dias`, com cliente, contrato e vendedor, e o estado da escada. Só leitura.
--
-- 2) atendimento_ensinar ganha duas travas que só importam agora que há botão:
--    - clique repetido com o mesmo parecer não vira exemplo em dobro;
--    - quem muda de ideia (marcou "não precisava" e depois "foi útil") desliga o
--      exemplo antigo (ativo = false) — ele para de ensinar, mas fica guardado
--      (regra 3.6). Exemplo sem texto não é gravado: entraria no prompt como "".
--
-- 3) atendimento_fechar carimba avaliado_ate = agora. A escada só reavalia uma
--    espera fechada quando chega mensagem do cliente MAIS NOVA que avaliado_ate;
--    sem o carimbo, uma mensagem mandada antes do "Falei por fora" (fora do
--    horário, por exemplo) faria a rodada seguinte avisar de novo sobre o que já
--    foi resolvido por telefone.
--
-- APLICADA em 15/10 (as três partes). Testado com rollback, como usuário
-- autorizado e sem login: 14 passos + o carimbo — nada ficou gravado.

create or replace function public.atendimento_painel(p_dias integer default 14)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_dias int := greatest(coalesce(p_dias, 14), 1);
  v_ini timestamptz := now() - make_interval(days => greatest(coalesce(p_dias, 14), 1));
begin
  if not is_autorizado() then return json_build_object('erro', 'sem permissão'); end if;
  return json_build_object(
    'ativo', coalesce((select valor from config where chave = 'atendimento_ativo'), '0') = '1',
    'fds_ativo', coalesce((select valor from config where chave = 'atendimento_fds_ativo'), '0') = '1',
    'desde', (select valor from config where chave = 'atendimento_desde'),
    'vendedor_min', (select valor from config where chave = 'atendimento_vendedor_min'),
    'posvenda_min', (select valor from config where chave = 'atendimento_posvenda_min'),
    'posvenda', (select nome from equipe where resp_posvenda and ativo order by nome limit 1),
    'exemplos', (select count(*) from atendimento_exemplo where ativo),
    'dias', v_dias,
    'esperas', coalesce((
      select json_agg(x order by x.aberta desc, x.ordem desc)
      from (
        select e.id, e.obra_id, o.cliente, o.contrato, v.nome as vendedor,
               (e.fechado_em is null) as aberta,
               coalesce(e.fechado_em, e.criado_em) as ordem,
               case when coalesce(e.parecer ->> 'pendente_desde', '') ~ '^\d{4}-\d{2}-\d{2}'
                    then (e.parecer ->> 'pendente_desde')::timestamptz else e.desde end as escreveu_em,
               e.ultima_msg_em,
               coalesce(e.parecer ->> 'trecho', '') as trecho,
               e.resumo, e.parecer ->> 'motivo' as motivo, coalesce(e.urgente, false) as urgente,
               e.precisa_resposta, e.ja_respondida,
               e.vendedor_avisado_em, e.posvenda_avisado_em, e.fds_avisado_em,
               e.fechado_em, e.fechado_como, e.fechado_por, e.respondido_em,
               e.feedback, e.feedback_por, e.feedback_em
        from atendimento_espera e
        join obras o on o.id = e.obra_id
        left join equipe v on v.id = e.vendedor_id
        where e.fechado_em is null or coalesce(e.fechado_em, e.criado_em) >= v_ini
        order by (e.fechado_em is null) desc, coalesce(e.fechado_em, e.criado_em) desc
        limit 150
      ) x), '[]'::json)
  );
end $function$;

comment on function public.atendimento_painel(integer) is
  'A aba Isabela do posvenda.html: esperas abertas + fechadas nos últimos N dias, com cliente, vendedor e o estado da escada. Só leitura (15/10).';

revoke execute on function public.atendimento_painel(integer) from public;
revoke execute on function public.atendimento_painel(integer) from anon;
grant  execute on function public.atendimento_painel(integer) to authenticated;
grant  execute on function public.atendimento_painel(integer) to service_role;

create or replace function public.atendimento_ensinar(p_id bigint, p_feedback text, p_obs text default null)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_quem text := coalesce(auth.jwt() ->> 'email', 'equipe');
  v_trecho text;
  e record;
begin
  if not is_autorizado() then return json_build_object('erro', 'sem permissão'); end if;
  if p_feedback not in ('util', 'desnecessario', 'faltou_avisar') then
    return json_build_object('erro', 'feedback inválido');
  end if;
  select * into e from atendimento_espera where id = p_id for update;
  if not found then return json_build_object('erro', 'não existe'); end if;
  -- clique repetido não vira exemplo em dobro
  if e.feedback is not distinct from p_feedback then
    return json_build_object('ok', true, 'ja_estava', true);
  end if;
  update atendimento_espera set feedback = p_feedback, feedback_por = v_quem, feedback_em = now()
   where id = p_id;
  -- mudou de ideia: o exemplo de antes para de ensinar, mas fica guardado (regra 3.6)
  update atendimento_exemplo set ativo = false where espera_id = p_id and ativo;
  if p_feedback in ('desnecessario', 'faltou_avisar') then
    v_trecho := coalesce(nullif(btrim(e.parecer ->> 'trecho'), ''), nullif(btrim(e.resumo), ''));
    if v_trecho is not null then
      insert into atendimento_exemplo (trecho, precisa_resposta, observacao, origem, espera_id, criado_por)
      values (v_trecho, p_feedback = 'faltou_avisar', nullif(btrim(coalesce(p_obs, '')), ''), 'feedback', e.id, v_quem);
    end if;
  end if;
  return json_build_object('ok', true, 'exemplo', v_trecho is not null);
end $function$;

create or replace function public.atendimento_fechar(p_id bigint, p_como text default 'resolvida_fora', p_obs text default null)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_quem text := coalesce(auth.jwt() ->> 'email', 'equipe');
begin
  if not is_autorizado() then return json_build_object('erro', 'sem permissão'); end if;
  if p_como not in ('resolvida_fora', 'nao_precisava', 'respondida') then
    return json_build_object('erro', 'como inválido');
  end if;
  -- avaliado_ate = agora: tudo o que o cliente escreveu até o clique está tratado. Sem
  -- isso, uma mensagem mandada antes do clique (fora do horário, por exemplo) faria a
  -- próxima rodada reavaliar e avisar de novo sobre o que já foi resolvido por fora.
  update atendimento_espera
     set fechado_em = now(), fechado_como = p_como, fechado_por = v_quem || coalesce(' · ' || p_obs, ''),
         avaliado_ate = now()
   where id = p_id and fechado_em is null;
  if not found then return json_build_object('erro', 'já estava fechada ou não existe'); end if;
  return json_build_object('ok', true);
end $function$;
