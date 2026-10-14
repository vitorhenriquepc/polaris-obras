-- Isabela: escada de atendimento nos grupos de cliente (Vitor, 14/10).
--
-- Cliente escreve no grupo da obra e ninguém da equipe responde:
--   2 h úteis  → a Isabela (18 99690-6474) avisa no privado o VENDEDOR da obra
--   4 h úteis  → avisa o pós-venda (equipe.resp_posvenda, hoje a Lívia)
--   sábado, domingo e feriado: passadas 2 h, a Isabela diz NO GRUPO que o
--   atendimento é de segunda a sexta e que alguém retoma o contato.
-- "Hora útil" = segunda a sexta, atendimento_hora_ini..atendimento_hora_fim,
-- fora dos feriados ativos (tabela feriados).
--
-- Antes de qualquer aviso, a IA lê a conversa e responde duas coisas: a
-- mensagem precisa MESMO de resposta? e alguma mensagem nossa — inclusive
-- automática — já respondeu? É isso que separa "ok, combinado" de pergunta.
-- (A medição de 14/10 contou recado e "ok" como pergunta e inflou o atraso:
-- as duas "demoradas" que eu citei foram respondidas em 1 e 5 minutos.)
--
-- Quem executa é a edge function isabela-atendimento. Tudo nasce DESLIGADO:
--   atendimento_ativo     = 0  → a escada (avisos à equipe)
--   atendimento_fds_ativo = 0  → o aviso no grupo (fala com o cliente: regra
--                               3.5, exceção decidida pelo Vitor em 14/10; o
--                               texto sai de atendimento_fds_texto)
-- O autoaprimoramento mora em atendimento_exemplo: cada caso que a equipe
-- corrige ("esse aviso não precisava", "essa precisava") vira exemplo que a IA
-- lê na próxima decisão — o mesmo desenho do classificacoes_exemplo, que o
-- webhook já usa para classificar mensagens.

-- 1. Parâmetros -------------------------------------------------------------
insert into config (chave, valor) values
  ('atendimento_ativo', '0'),
  ('atendimento_vendedor_min', '120'),
  ('atendimento_posvenda_min', '240'),
  ('atendimento_hora_ini', '8'),
  ('atendimento_hora_fim', '18'),
  ('atendimento_fds_ativo', '0'),
  ('atendimento_fds_min', '120'),
  ('atendimento_fds_hora_ini', '8'),
  ('atendimento_fds_hora_fim', '20'),
  ('atendimento_fds_texto',
   'Olá! 👋 Aqui é a Isabela, da Polaris Energia Solar.' || chr(10) || chr(10)
   || 'Recebemos sua mensagem! Nosso atendimento é de segunda a sexta, das 8h às 18h — '
   || '{quando} alguém da nossa equipe retoma o contato com você por aqui. 🙏'),
  ('atendimento_desde', '')
on conflict (chave) do nothing;

-- 2. Mensagem que não pede resposta ----------------------------------------
-- Partiu da lista de cortesia da clientes_esperando(), em função própria e
-- aceitando expressões em sequência. Pergunta ("?") nunca é trivial, por
-- menor que seja. O que passar daqui a IA ainda julga.
create or replace function public.msg_trivial(p text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  -- trivial = a mensagem inteira é uma sequência de expressões de cortesia
  -- ("ok", "beleza, fico no aguardo", "obrigado viu, bom dia")
  select case when coalesce(p, '') like '%?%' then false
    else length(trim(t.x)) < 3
      or trim(t.x) ~ ('^(' || t.f || ')([[:space:]]+(' || t.f || '))*$')
    end
  from (select lower(regexp_replace(
          translate(coalesce(p, ''),
                    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
                    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
          '[^[:alnum:][:space:]]', '', 'g')) as x,
        'ok|okay|blz|beleza|valeu|vlw|obrigad[oa]|obg|obgd|muito|bom dia|boa tarde|boa noite|oi|ola|'
        || 'otima semana|boa semana|otimo final de semana|bom final de semana|amem|certo|isso|sim|nao|'
        || 'ta bom|ta|tudo bem|tudo certo|tudo joia|joia|combinado|perfeito|show|top|vou ver|ja vi|'
        || 'entendi|de nada|eu que agradeco|nos que agradecemos|igualmente|pra voces tambem|'
        || 'para voces tambem|fico no aguardo|no aguardo|aguardo|aguardando|deu certo|gratidao|grato|'
        || 'grata|maravilha|otimo|otima|legal|deus abencoe|kk+|ha(ha)+|rs+|mesmo|viu|entao|gente|'
        || 'pessoal|amigo|amiga|tchau|abraco|abracos|voces|vcs|tambem|todos|demais' as f) t;
$function$;

-- 3. Minutos do horário de atendimento entre dois instantes -----------------
create or replace function public.minutos_uteis(p_ini timestamptz, p_fim timestamptz)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  with cfg as (
    select coalesce(nullif((select valor from config where chave = 'atendimento_hora_ini'), '')::int, 8) as hi,
           coalesce(nullif((select valor from config where chave = 'atendimento_hora_fim'), '')::int, 18) as hf
  ), dias as (
    select d::date as dia
    from generate_series((p_ini at time zone 'America/Sao_Paulo')::date,
                         (p_fim at time zone 'America/Sao_Paulo')::date, interval '1 day') d
  )
  select coalesce(sum(greatest(0, floor(extract(epoch from (
           least(p_fim, (dias.dia + make_time(cfg.hf, 0, 0)) at time zone 'America/Sao_Paulo')
         - greatest(p_ini, (dias.dia + make_time(cfg.hi, 0, 0)) at time zone 'America/Sao_Paulo')
         )) / 60))), 0)::int
  from dias, cfg
  where p_fim > p_ini
    and extract(isodow from dias.dia) between 1 and 5
    and not exists (select 1 from feriados f where f.ativo and f.data = dias.dia);
$function$;

-- 4. Cada espera de cliente vira uma linha (para avisar uma vez por degrau,
--    medir e aprender) ----------------------------------------------------------
create table if not exists atendimento_espera (
  id bigserial primary key,
  obra_id uuid not null references obras(id) on delete cascade,
  grupo_id text not null,
  desde timestamptz not null,
  ultima_msg_em timestamptz not null,
  avaliado_ate timestamptz,
  precisa_resposta boolean,
  ja_respondida boolean,
  resumo text,
  urgente boolean,
  parecer jsonb,
  vendedor_id uuid,
  vendedor_avisado_em timestamptz,
  posvenda_avisado_em timestamptz,
  fds_avisado_em timestamptz,
  fechado_em timestamptz,
  fechado_como text check (fechado_como in
    ('respondida', 'nao_precisava', 'respondida_isabela', 'resolvida_fora', 'expirada')),
  fechado_por text,
  respondido_em timestamptz,
  feedback text check (feedback in ('util', 'desnecessario', 'faltou_avisar')),
  feedback_por text,
  feedback_em timestamptz,
  criado_em timestamptz not null default now()
);
create unique index if not exists atendimento_espera_um_aberto
  on atendimento_espera (obra_id) where fechado_em is null;
create index if not exists atendimento_espera_desde on atendimento_espera (desde desc);
alter table atendimento_espera enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.atendimento_espera'::regclass
                 and polname = 'atendimento_espera_leitura') then
    create policy atendimento_espera_leitura on atendimento_espera for select using (is_autorizado());
  end if;
end $p$;

-- 5. O que a equipe corrigiu vira exemplo para a próxima decisão ------------
create table if not exists atendimento_exemplo (
  id bigserial primary key,
  trecho text not null,
  precisa_resposta boolean not null,
  observacao text,
  origem text not null default 'equipe' check (origem in ('equipe', 'revisao', 'feedback')),
  espera_id bigint references atendimento_espera(id) on delete set null,
  criado_por text,
  criado_em timestamptz not null default now(),
  ativo boolean not null default true
);
alter table atendimento_exemplo enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.atendimento_exemplo'::regclass
                 and polname = 'atendimento_exemplo_leitura') then
    create policy atendimento_exemplo_leitura on atendimento_exemplo for select using (is_autorizado());
  end if;
end $p$;

-- 6. Quem está esperando resposta num dado instante -------------------------
-- "Resposta" aqui é mensagem de GENTE da equipe (equipe_por_fone, inclusive os
-- números extras). Mensagem automática da Isabela não fecha sozinha: quem
-- decide se ela respondeu é a IA, lendo a conversa. p_agora existe para dar
-- para reprocessar o passado (modo replay da edge function).
create or replace function public.atendimento_candidatos(p_agora timestamptz default now(),
                                                         p_desde_min timestamptz default null)
 returns json
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  with m as (
    select mr.id, mr.obra_id, mr.recebida_em, coalesce(mr.da_equipe, false) as eq, mr.contexto,
           mr.tipo, mr.metodo, coalesce(mr.transcricao, mr.texto) as conteudo, mr.remetente_nome
    from mensagens_recebidas mr
    where mr.recebida_em <= p_agora and mr.recebida_em > p_agora - interval '7 days'
  ), ult_eq as (
    select obra_id, max(recebida_em) as em,
           (array_agg(remetente_nome order by recebida_em desc))[1] as quem
    from m where eq and coalesce(contexto, '') <> 'automatica'
    group by obra_id
  ), pend as (
    select m.obra_id, min(m.recebida_em) as desde, max(m.recebida_em) as ultima, count(*) as n,
           (array_agg(left(m.conteudo, 160) order by m.recebida_em desc))[1] as trecho
    from m left join ult_eq u on u.obra_id = m.obra_id
    where not m.eq
      and m.recebida_em > coalesce(u.em, '-infinity'::timestamptz)
      and m.tipo not in ('reacao', 'figurinha', 'outro')
      and coalesce(m.contexto, '') not in ('nps', 'autorizacao', 'sair', 'aceite_relatorio', 'automatica')
      and coalesce(m.metodo, '') not in ('aceite', 'optin', 'nps')
      and (m.tipo in ('imagem', 'documento', 'video', 'audio') or not public.msg_trivial(m.conteudo))
    group by m.obra_id
  )
  select coalesce(json_agg(json_build_object(
      'obra_id', o.id, 'cliente', o.cliente, 'contrato', o.contrato, 'grupo', o.whatsapp_grupo_id,
      'vendedor_id', o.vendedor_id, 'trilha', coalesce(o.trilha, 'padrao'), 'etapa', o.etapa_numero,
      'desde', p.desde, 'ultima', p.ultima, 'msgs', p.n, 'trecho', p.trecho,
      'ult_equipe_em', u.em, 'ult_equipe_quem', u.quem,
      'min_uteis', public.minutos_uteis(p.desde, p_agora),
      'min_corridos', floor(extract(epoch from (p_agora - p.desde)) / 60)::int
    ) order by p.desde), '[]'::json)
  from pend p
  join obras o on o.id = p.obra_id
  left join ult_eq u on u.obra_id = p.obra_id
  where o.whatsapp_grupo_id is not null
    and o.optout_em is null
    and (p_desde_min is null or p.desde >= p_desde_min);
$function$;

-- 7. Ações da tela (fechar na mão e ensinar) — com trava de quem é da equipe -
create or replace function public.atendimento_fechar(p_id bigint, p_como text default 'resolvida_fora',
                                                     p_obs text default null)
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
  update atendimento_espera
     set fechado_em = now(), fechado_como = p_como, fechado_por = v_quem || coalesce(' · ' || p_obs, '')
   where id = p_id and fechado_em is null;
  if not found then return json_build_object('erro', 'já estava fechada ou não existe'); end if;
  return json_build_object('ok', true);
end $function$;

create or replace function public.atendimento_ensinar(p_id bigint, p_feedback text, p_obs text default null)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_quem text := coalesce(auth.jwt() ->> 'email', 'equipe');
  e record;
begin
  if not is_autorizado() then return json_build_object('erro', 'sem permissão'); end if;
  if p_feedback not in ('util', 'desnecessario', 'faltou_avisar') then
    return json_build_object('erro', 'feedback inválido');
  end if;
  update atendimento_espera set feedback = p_feedback, feedback_por = v_quem, feedback_em = now()
   where id = p_id returning * into e;
  if e.id is null then return json_build_object('erro', 'não existe'); end if;
  -- "desnecessário" e "faltou avisar" viram exemplo; "útil" confirma o que já foi feito
  if p_feedback in ('desnecessario', 'faltou_avisar') then
    insert into atendimento_exemplo (trecho, precisa_resposta, observacao, origem, espera_id, criado_por)
    values (coalesce(e.parecer ->> 'trecho', e.resumo, ''), p_feedback = 'faltou_avisar', p_obs, 'feedback', e.id, v_quem);
  end if;
  return json_build_object('ok', true);
end $function$;

-- 8. Permissões (armadilha 10: os dois revokes) -----------------------------
revoke execute on function public.msg_trivial(text) from public;
revoke execute on function public.msg_trivial(text) from anon;
grant  execute on function public.msg_trivial(text) to authenticated, service_role;
revoke execute on function public.minutos_uteis(timestamptz, timestamptz) from public;
revoke execute on function public.minutos_uteis(timestamptz, timestamptz) from anon;
grant  execute on function public.minutos_uteis(timestamptz, timestamptz) to authenticated, service_role;
revoke execute on function public.atendimento_candidatos(timestamptz, timestamptz) from public;
revoke execute on function public.atendimento_candidatos(timestamptz, timestamptz) from anon;
grant  execute on function public.atendimento_candidatos(timestamptz, timestamptz) to authenticated, service_role;
revoke execute on function public.atendimento_fechar(bigint, text, text) from public;
revoke execute on function public.atendimento_fechar(bigint, text, text) from anon;
grant  execute on function public.atendimento_fechar(bigint, text, text) to authenticated, service_role;
revoke execute on function public.atendimento_ensinar(bigint, text, text) from public;
revoke execute on function public.atendimento_ensinar(bigint, text, text) from anon;
grant  execute on function public.atendimento_ensinar(bigint, text, text) to authenticated, service_role;
