-- 29/10: mensagem que a Z-API aceitou e não chegou ao grupo do cliente
--
-- JOSÉ VICENTE DOS SANTOS PINTO (4875), 28 e 29/10: o painel mandou duas
-- mensagens ao grupo dele (a da etapa "Execução da Obra" e o agendamento de
-- 17/11), o notificar-grupo respondeu 200 nas duas e nenhuma chegou: a Isabela
-- não estava no grupo. A Z-API aceita o envio para um grupo em que o número não
-- está e não diz nada. Quem soube foi o Vitor, porque o cliente não respondeu.
--
-- Desde 15/10 tudo o que sai pelo número da Isabela volta para o webhook
-- (fromMe) e é gravado em mensagens_recebidas como 'Sistema/Polaris'. Medido de
-- 15/10 a 29/10, 59 envios com hora gravada (régua, relatório do instalador,
-- pesquisa de satisfação, vistoria): todos voltaram, de 4 a 75 s depois. O do
-- José Vicente é o único caso conhecido de mensagem que não voltou.
--
-- entrega_conferir(simular) olha o que saiu nas últimas 24 h para grupo de
-- cliente e procura a cópia que voltou (2 min antes a 30 min depois do envio):
--   painel    -> envios_grupo (o notificar-grupo, desde a v17: etapa, agendamento,
--                vistoria, equipe, NPS e IPTU pedidos na tela)
--   regua     -> regua_contatos (régua das 17h e resumo do mês)
--   relatorio -> obras.relatorio_enviado_em (o foto-obra)
--   nps       -> obras.nps_enviado_em (a pesquisa de satisfação)
-- Só confere envio com mais de `entrega_espera_min` (10) minutos e grupo que o
-- webhook grava (obra_do_grupo): o grupo da equipe não tem obra, e de lá nunca
-- volta cópia. O que não voltou vira aviso à pós-venda (resp_posvenda), num
-- texto só por rodada; cada envio é avisado uma vez, e um grupo não recebe
-- novo aviso antes de `entrega_intervalo_h` (6) horas. Falha de mais de 24 h
-- não vira aviso.
-- Fica de fora o que não grava a hora do envio: o lembrete da véspera
-- (instalacao_lembrete_em guarda a data da obra), a autoleitura e o aviso de
-- fim de semana da Isabela.
--
-- Quem manda o aviso é a edge function entrega-conferir (cron a cada 10 min,
-- 8h às 20h50), e ela só marca avisado (entrega_avisada) depois que a Z-API
-- aceita. Desliga pela config: entrega_conferir_ativo = '0'.

create table if not exists public.entrega_conferida (
  id           bigserial primary key,
  origem       text not null,
  ref          text not null,
  grupo_id     text not null,
  obra_id      uuid,
  enviado_em   timestamptz not null,
  previa       text,
  conferido_em timestamptz not null default now(),
  voltou_em    timestamptz,
  avisado_em   timestamptz,
  unique (origem, ref)
);
create index if not exists entrega_conferida_grupo on public.entrega_conferida (grupo_id, avisado_em desc);
create index if not exists entrega_conferida_aberta on public.entrega_conferida (enviado_em) where voltou_em is null and avisado_em is null;
alter table public.entrega_conferida enable row level security;
revoke all on public.entrega_conferida from anon, authenticated;
-- a busca da cópia: o que o número da Isabela gravou, por grupo e hora
create index if not exists mr_copia_idx on public.mensagens_recebidas (grupo_id, recebida_em)
  where da_equipe and remetente_nome = 'Sistema/Polaris';
comment on table public.entrega_conferida is
  'Mensagem para grupo de cliente conferida contra a cópia que volta pelo webhook (JOSÉ VICENTE 4875, 29/10). origem: painel | regua | relatorio | nps. voltou_em nulo = a mensagem não voltou do grupo. avisado_em = quando a pós-venda foi avisada. Sem policy: só o service_role lê e grava.';

insert into public.config (chave, valor) values
  ('entrega_conferir_ativo', '1'),
  ('entrega_espera_min', '10'),
  ('entrega_intervalo_h', '6'),
  ('entrega_desde', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
on conflict (chave) do nothing;

-- a cópia de um envio: o que o número da Isabela gravou no mesmo grupo,
-- de 2 min antes a 30 min depois
create or replace function public.entrega_voltou(p_grupo text, p_enviado timestamptz)
 returns timestamptz
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select min(m.recebida_em)
    from mensagens_recebidas m
   where m.grupo_id = p_grupo and m.da_equipe and m.remetente_nome = 'Sistema/Polaris'
     and m.recebida_em between p_enviado - interval '2 minutes' and p_enviado + interval '30 minutes';
$function$;

-- o que saiu para grupo de cliente entre p_desde e p_ate e ainda não foi conferido
create or replace function public.entrega_candidatos(p_desde timestamptz, p_ate timestamptz)
 returns table (origem text, ref text, grupo_id text, obra_id uuid, enviado_em timestamptz, previa text, voltou_em timestamptz)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with c as (
    select 'painel'::text as origem, e.id::text as ref, e.grupo_id, e.concluido_em as enviado_em, e.previa
      from envios_grupo e
     where e.ok and e.concluido_em > p_desde and e.concluido_em <= p_ate
    union all
    select 'regua', rc.id::text, o.whatsapp_grupo_id, rc.enviado_em, left(coalesce(rc.texto_enviado, rc.texto_custom, rc.modelo), 60)
      from regua_contatos rc join obras o on o.id = rc.obra_id
     where rc.status = 'enviado' and rc.enviado_em > p_desde and rc.enviado_em <= p_ate
    union all
    select 'relatorio', o.id::text || '@' || o.relatorio_enviado_em::text, o.whatsapp_grupo_id, o.relatorio_enviado_em, 'relatório do instalador'
      from obras o
     where o.relatorio_enviado_em > p_desde and o.relatorio_enviado_em <= p_ate
    union all
    select 'nps', o.id::text || '@' || o.nps_enviado_em::text, o.whatsapp_grupo_id, o.nps_enviado_em, 'pesquisa de satisfação'
      from obras o
     where o.nps_enviado_em > p_desde and o.nps_enviado_em <= p_ate
  ), d as (
    select c.*, obra_do_grupo(c.grupo_id) as obra_id
      from c
     where c.grupo_id like '%-group'
       and not exists (select 1 from entrega_conferida x where x.origem = c.origem and x.ref = c.ref)
  )
  select d.origem, d.ref, d.grupo_id, d.obra_id, d.enviado_em, d.previa, entrega_voltou(d.grupo_id, d.enviado_em)
    from d
   where d.obra_id is not null;
$function$;

create or replace function public.entrega_conferir(p_simular boolean default true)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_espera int := coalesce((select nullif(valor, '')::int from config where chave = 'entrega_espera_min'), 10);
  v_interv int := coalesce((select nullif(valor, '')::int from config where chave = 'entrega_intervalo_h'), 6);
  v_desde timestamptz := greatest(now() - interval '24 hours',
    coalesce((select nullif(valor, '')::timestamptz from config where chave = 'entrega_desde'), '-infinity'::timestamptz));
  v_ate timestamptz := now() - make_interval(mins => v_espera);
  v_novos int := 0;
  v_tardias int := 0;
  v_falta json;
  v_ids bigint[];
  v_grupos int := 0;
  v_falhando int := 0;
  v_primeiro timestamptz;
  v_sistema boolean := false;
  v_texto text;
  v_destino text;
begin
  if not p_simular then
    insert into entrega_conferida (origem, ref, grupo_id, obra_id, enviado_em, previa, voltou_em)
    select c.origem, c.ref, c.grupo_id, c.obra_id, c.enviado_em, c.previa, c.voltou_em
      from entrega_candidatos(v_desde, v_ate) c
    on conflict (origem, ref) do nothing;
    get diagnostics v_novos = row_count;
    -- a cópia que chegou depois da última conferência
    update entrega_conferida x set voltou_em = entrega_voltou(x.grupo_id, x.enviado_em)
     where x.voltou_em is null and x.avisado_em is null and x.enviado_em > now() - interval '24 hours'
       and entrega_voltou(x.grupo_id, x.enviado_em) is not null;
    get diagnostics v_tardias = row_count;
  end if;

  -- o estado como ficaria: o que já está na tabela e, na simulação, o que entraria agora
  with estado as (
    select x.id, x.origem, x.grupo_id, x.obra_id, x.enviado_em, x.previa,
           coalesce(x.voltou_em, entrega_voltou(x.grupo_id, x.enviado_em)) as voltou_em, x.avisado_em
      from entrega_conferida x
     where x.enviado_em > now() - interval '24 hours'
    union all
    select null::bigint, c.origem, c.grupo_id, c.obra_id, c.enviado_em, c.previa, c.voltou_em, null::timestamptz
      from entrega_candidatos(v_desde, v_ate) c
  ), falta as (
    select e.*, o.cliente, o.contrato
      from estado e left join obras o on o.id = e.obra_id
     where e.voltou_em is null and e.avisado_em is null
       and not exists (select 1 from entrega_conferida y
                        where y.grupo_id = e.grupo_id and y.avisado_em > now() - make_interval(hours => v_interv))
  )
  select coalesce(json_agg(json_build_object(
           'id', f.id, 'origem', f.origem, 'grupo_id', f.grupo_id, 'obra_id', f.obra_id,
           'cliente', f.cliente, 'contrato', f.contrato, 'enviado_em', f.enviado_em, 'previa', f.previa)
           order by f.cliente, f.enviado_em), '[]'::json),
         array_agg(f.id) filter (where f.id is not null),
         count(distinct f.grupo_id),
         min(f.enviado_em),
         -- grupos sem cópia nas últimas 24 h, avisados ou não: é o que mostra falha geral
         (select count(distinct e.grupo_id) from estado e where e.voltou_em is null)
    into v_falta, v_ids, v_grupos, v_primeiro, v_falhando
    from falta f;

  if v_grupos = 0 then
    return json_build_object('ok', true, 'simular', p_simular, 'novos', v_novos, 'tardias', v_tardias,
                             'falta', v_falta, 'texto', null, 'ids', '[]'::json);
  end if;

  -- 3 ou mais grupos sem cópia e nada voltou de grupo nenhum desde o primeiro
  -- envio que faltou: o problema é do número (desconectado) ou da Z-API (deixou
  -- de devolver o que sai), não de um grupo
  v_sistema := v_falhando >= 3 and not exists (
    select 1 from mensagens_recebidas m
     where m.da_equipe and m.remetente_nome = 'Sistema/Polaris' and m.recebida_em >= v_primeiro - interval '2 minutes');

  with f as (
    select (e->>'cliente') as cliente, (e->>'contrato') as contrato, (e->>'grupo_id') as grupo_id,
           (e->>'origem') as origem, (e->>'enviado_em')::timestamptz as enviado_em, (e->>'previa') as previa
      from json_array_elements(v_falta) e
  ), por_grupo as (
    select f.grupo_id, min(f.cliente) as cliente, min(f.contrato) as contrato,
           string_agg('   ' || to_char(f.enviado_em at time zone 'America/Sao_Paulo',
                        case when (f.enviado_em at time zone 'America/Sao_Paulo')::date = (now() at time zone 'America/Sao_Paulo')::date
                             then 'HH24:MI' else 'DD/MM HH24:MI' end)
                      || ' · ' || case f.origem when 'painel' then 'pelo painel' when 'regua' then 'régua'
                                                when 'relatorio' then 'relatório do instalador' when 'nps' then 'pesquisa de satisfação'
                                                else f.origem end
                      || case when f.origem in ('painel', 'regua') and coalesce(f.previa, '') <> ''
                              then ': "' || btrim(regexp_replace(translate(f.previa, '*_~', ''), '\s+', ' ', 'g')) || '…"'
                              else '' end,
                      E'\n' order by f.enviado_em) as linhas,
           min(f.enviado_em) as primeiro
      from f group by f.grupo_id
  )
  select case when v_sistema
           then E'⚠️ *Nenhuma mensagem da Isabela voltou dos grupos desde as '
             || to_char(v_primeiro at time zone 'America/Sao_Paulo', 'HH24:MI') || E'*\n\n'
             || v_falhando || E' grupos sem a cópia. Pode ser o WhatsApp da Isabela desconectado, ou a Z-API '
             || E'deixou de devolver o que ela manda ("Notificar as enviadas por mim também"). '
             || E'Os clientes podem não ter recebido:\n\n'
           else E'⚠️ *Mensagem que não chegou ao grupo do cliente*\n\n'
         end
         || string_agg('• *' || coalesce(pg.cliente, 'grupo sem obra') || '*' || coalesce(' #' || pg.contrato, '') || E'\n' || pg.linhas,
                       E'\n' order by pg.primeiro)
         || case when v_sistema then ''
                 else E'\n\nA Z-API aceitou, mas a mensagem não voltou do grupo. O mais comum é a Isabela não estar '
                   || E'no grupo. Confira o grupo, coloque a Isabela se faltar e mande de novo (o 📣 do card manda '
                   || E'a mensagem da etapa e o aviso de agendamento).' end
    into v_texto
    from por_grupo pg;

  select e.telefone into v_destino
    from equipe e where e.resp_posvenda and e.ativo and coalesce(e.telefone, '') <> ''
   order by e.nome limit 1;

  return json_build_object('ok', true, 'simular', p_simular, 'novos', v_novos, 'tardias', v_tardias,
                           'sistema', v_sistema, 'grupos', v_grupos, 'falhando', v_falhando, 'falta', v_falta,
                           'texto', v_texto, 'destino', v_destino, 'ids', coalesce(to_json(v_ids), '[]'::json));
end $function$;

-- só depois que a Z-API aceitou o aviso à pós-venda
create or replace function public.entrega_avisada(p_ids bigint[])
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_n int;
begin
  update entrega_conferida set avisado_em = now() where id = any(p_ids) and avisado_em is null;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- armadilha 10: os dois revokes; só o service_role (a edge function) chama
revoke execute on function public.entrega_voltou(text, timestamptz) from public;
revoke execute on function public.entrega_voltou(text, timestamptz) from anon;
revoke execute on function public.entrega_voltou(text, timestamptz) from authenticated;
grant  execute on function public.entrega_voltou(text, timestamptz) to service_role;
revoke execute on function public.entrega_candidatos(timestamptz, timestamptz) from public;
revoke execute on function public.entrega_candidatos(timestamptz, timestamptz) from anon;
revoke execute on function public.entrega_candidatos(timestamptz, timestamptz) from authenticated;
grant  execute on function public.entrega_candidatos(timestamptz, timestamptz) to service_role;
revoke execute on function public.entrega_conferir(boolean) from public;
revoke execute on function public.entrega_conferir(boolean) from anon;
revoke execute on function public.entrega_conferir(boolean) from authenticated;
grant  execute on function public.entrega_conferir(boolean) to service_role;
revoke execute on function public.entrega_avisada(bigint[]) from public;
revoke execute on function public.entrega_avisada(bigint[]) from anon;
revoke execute on function public.entrega_avisada(bigint[]) from authenticated;
grant  execute on function public.entrega_avisada(bigint[]) to service_role;

-- a cada 10 minutos, das 8h às 20h50 de Brasília
select cron.schedule('entrega-conferir', '*/10 11-23 * * *', $cron$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/entrega-conferir',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token', (select valor from public.config where chave = 'cron_token')),
    timeout_milliseconds := 60000);
$cron$);
