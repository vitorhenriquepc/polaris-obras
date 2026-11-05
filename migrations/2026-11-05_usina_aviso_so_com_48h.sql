-- 05/11: aviso de "usina sem internet" ao cliente só depois de 48 h seguidas sem
-- comunicar (Vitor, 04/11: "não compensa mandar um alerta" para a usina que cai e
-- volta; 05/11: "pode fazer a regra das 48h").
--
-- Medido de 06/09 a 04/11 no usina_leitura (as leituras de 09h15, 13h15, 16h15):
--   - 180 quedas de comunicação em 53 usinas; 92% voltaram sozinhas em até 48 h,
--     105 já na leitura seguinte (~4 h); 46% começam na leitura das 9h15 -- e a
--     rodada de problemas do mensagens-usina-auto escreve às 10h20;
--   - dos 49 avisos de internet que a IA escreveu, 31 eram de usina que voltou
--     sozinha em até 2 dias (19 em 3 h); 29 foram recusados na mão e 3 saíram para
--     o cliente com a usina já de volta (João Vitor, Ines, Valdecir);
--   - quando a queda passa de um dia, em 82% o inversor guardou a geração e mandou
--     depois: nada se perdeu;
--   - 12 usinas fazem 55% das quedas; a LUCINEI teve 7 avisos escritos.
--
-- O que muda:
--   1) usina_aviso_cliente(usina, obra) decide o aviso de usina para o cliente
--      (o mensagens-usina-auto passa a perguntar a ela):
--        - obra que ainda não foi ligada (obra_ativa) não recebe aviso de usina
--          (a Igreja 4810, na vistoria, ganhou um em 04/11);
--        - "internet" só se o SolarView NÃO fala com o inversor (datalogger
--          offline) há usina_aviso_horas_sem_comunicar (48) horas seguidas;
--          "operando" e sem gerar não é internet;
--        - um aviso por queda (e por parada): queda longa não ganha um por semana;
--   2) regua_usina_resolvidos() tira da fila (status 'pulado', com o motivo) o
--      aviso de internet ou de parada cuja usina voltou -- aguardando ou já
--      aprovado. Roda depois de cada leitura do usina-status (cron
--      regua-usina-voltou) e no começo do disparo das 17h (regua_expirar);
--   3) usina_queda_atual(usina): a queda em curso e quantas quedas em 14 dias;
--      pendencias_posvenda() ganha conexao_instavel (usina_instavel_quedas_14d,
--      3+ quedas em 14 dias), que o aviso das 8h mostra às segundas, para a
--      equipe -- o cliente não é avisado a cada queda.

insert into public.config (chave, valor) values
  ('usina_aviso_horas_sem_comunicar', '48'),
  ('usina_instavel_quedas_14d', '3')
on conflict (chave) do nothing;

-- A queda de comunicação em curso, pelas leituras do usina-status.
create or replace function public.usina_queda_atual(p_usina uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with l as (
    select lida_em, status from usina_leitura where usina_id = p_usina
  ), ult as (
    select lida_em, status from l order by lida_em desc limit 1
  ), ult_ok as (   -- a última leitura em que o SolarView falava com o inversor
    select max(lida_em) as em from l where status is distinct from 'datalogger offline'
  ), ini as (      -- a primeira leitura da queda em curso
    select min(l.lida_em) as em from l, ult_ok
     where l.status = 'datalogger offline' and (ult_ok.em is null or l.lida_em > ult_ok.em)
  ), q14 as (      -- quedas (começos de sequência offline) nos últimos 14 dias
    select count(*) as n from (
      select status = 'datalogger offline' as off,
             lag(status = 'datalogger offline') over (order by lida_em) as off_ant
        from l where lida_em > now() - interval '14 days') z
     where off and coalesce(off_ant, false) = false
  )
  select jsonb_build_object(
    'ultima_leitura', (select lida_em from ult),
    'status', (select status from ult),
    'sem_comunicar', coalesce((select status from ult) = 'datalogger offline', false),
    'desde', case when (select status from ult) = 'datalogger offline' then (select em from ini) end,
    'horas', case when (select status from ult) = 'datalogger offline'
                  then round(extract(epoch from now() - (select em from ini)) / 3600)::int end,
    'quedas_14d', (select n from q14));
$function$;

comment on function public.usina_queda_atual(uuid) is
  'A queda de comunicação em curso (datalogger offline nas leituras do usina-status): desde quando, há quantas horas, e quantas quedas a usina teve em 14 dias. Só leitura (05/11).';

-- O aviso de usina para o cliente: pode sair? de que tipo? Se não, por quê.
-- `segue` = a usina está bem e a obra ligada: o mensagens-usina-auto pode olhar
-- queda de geração e recorde.
create or replace function public.usina_aviso_cliente(p_usina uuid, p_obra uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_horas_min int := coalesce((select nullif(valor, '')::int from config where chave = 'usina_aviso_horas_sem_comunicar'), 48);
  v_dias_parada int := coalesce((select nullif(valor, '')::int from config where chave = 'msg_ia_min_dias_parada'), 3);
  e record;
  q jsonb;
  v_ja record;
begin
  if not coalesce(public.obra_ativa(p_obra), false) then
    return jsonb_build_object('tipo', null, 'segue', false,
      'pula', 'a obra ainda não foi ligada (etapa ' || coalesce((select etapa_numero::text from obras where id = p_obra), '?') || ')');
  end if;

  select * into e from public.usina_estado(p_usina);
  if e.estado = 'recém-ligada' then
    return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado, 'pula', 'recém-ligada, em carência');
  end if;

  if e.estado = 'parada' then
    if coalesce(e.dias_sem_gerar, 0) < v_dias_parada then
      return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado,
        'pula', 'parada há ' || coalesce(e.dias_sem_gerar, 0) || ' dia(s); o aviso sai com ' || v_dias_parada);
    end if;
    -- um aviso por parada
    select c.id, c.status, c.status_aprovacao into v_ja from regua_contatos c
     where c.usina_id = p_usina and c.modelo in ('usina_wifi', 'usina_parada')
       and c.criado_em >= (current_date - e.dias_sem_gerar)::timestamptz
     order by c.criado_em desc limit 1;
    if found then
      return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado,
        'pula', 'esta parada já tem aviso (contato ' || v_ja.id || ', ' || v_ja.status || '/' || coalesce(v_ja.status_aprovacao, '-') || ')');
    end if;
    return jsonb_build_object('tipo', 'parada', 'segue', false, 'estado', e.estado, 'motivo', e.motivo);
  end if;

  if e.estado in ('sem comunicação', 'alerta', 'nunca gerou', 'sem dado') then
    q := public.usina_queda_atual(p_usina);
    if not coalesce((q->>'sem_comunicar')::boolean, false) then
      return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado, 'queda', q,
        'pula', 'o SolarView fala com o inversor (' || coalesce(q->>'status', 'sem leitura') || '): não é internet');
    end if;
    if coalesce((q->>'horas')::int, 0) < v_horas_min then
      return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado, 'queda', q,
        'pula', 'sem comunicar há ' || coalesce(q->>'horas', '?') || ' h; o aviso só sai com ' || v_horas_min || ' h seguidas');
    end if;
    -- um aviso por queda: a queda longa não ganha um por semana
    select c.id, c.status, c.status_aprovacao into v_ja from regua_contatos c
     where c.usina_id = p_usina and c.modelo in ('usina_wifi', 'usina_parada')
       and c.criado_em >= (q->>'desde')::timestamptz
     order by c.criado_em desc limit 1;
    if found then
      return jsonb_build_object('tipo', null, 'segue', false, 'estado', e.estado, 'queda', q,
        'pula', 'esta queda já tem aviso (contato ' || v_ja.id || ', ' || v_ja.status || '/' || coalesce(v_ja.status_aprovacao, '-') || ')');
    end if;
    return jsonb_build_object('tipo', 'wifi', 'segue', false, 'estado', e.estado, 'queda', q,
      'motivo', 'sem comunicar desde ' || to_char(((q->>'desde')::timestamptz) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
                || ' (' || (q->>'horas') || ' h)');
  end if;

  return jsonb_build_object('tipo', null, 'segue', true, 'estado', e.estado);
end $function$;

comment on function public.usina_aviso_cliente(uuid, uuid) is
  'O aviso de usina para o cliente (05/11): obra não ligada não recebe; internet só com o SolarView sem falar com o inversor há usina_aviso_horas_sem_comunicar (48) h seguidas; parada com msg_ia_min_dias_parada; um aviso por queda/parada. Devolve tipo (wifi/parada), motivo, ou pula; segue = pode olhar queda de geração e recorde. Só leitura.';

-- Tira da fila o aviso de usina que já não vale: a usina voltou a comunicar
-- (internet) ou a gerar (parada), ou a obra não está ligada. Não apaga: vira
-- 'pulado' com o motivo (regra 3.6). Vale para aguardando e para aprovado.
create or replace function public.regua_usina_resolvidos(p_simular boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r record;
  v_motivo text;
  v_quando timestamptz;
  v_dia date;
  v_status_antes text;
  v_ini timestamptz;
  v_ant record;
  v_itens jsonb := '[]'::jsonb;
begin
  for r in
    select c.id, c.obra_id, c.usina_id, c.modelo, c.criado_em, c.status_aprovacao, o.cliente
      from regua_contatos c join obras o on o.id = c.obra_id
     where c.status = 'pendente' and c.modelo in ('usina_wifi', 'usina_parada')
     order by c.id
  loop
    v_motivo := null;
    if not coalesce(public.obra_ativa(r.obra_id), false) then
      v_motivo := 'a obra ainda não foi ligada: aviso de usina não vale';
    elsif r.usina_id is not null and r.modelo = 'usina_wifi' then
      select l.status into v_status_antes from usina_leitura l
       where l.usina_id = r.usina_id and l.lida_em <= r.criado_em order by l.lida_em desc limit 1;
      select min(l.lida_em) into v_quando from usina_leitura l
       where l.usina_id = r.usina_id and l.lida_em > r.criado_em and l.status is distinct from 'datalogger offline';
      if v_status_antes is distinct from 'datalogger offline' and v_status_antes is not null then
        v_motivo := 'quando o aviso foi escrito o SolarView falava com o inversor (' || v_status_antes || '): não era internet';
      elsif v_quando is not null then
        v_motivo := 'a usina voltou a comunicar em ' || to_char(v_quando at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI') || ': o aviso não vale mais';
      else
        -- ainda sem comunicar: um aviso por queda. Se esta mesma queda já teve
        -- aviso (enviado ou recusado), este é repetição -- a LUCINEI teve 7.
        select min(l.lida_em) into v_ini from usina_leitura l
         where l.usina_id = r.usina_id and l.status = 'datalogger offline' and l.lida_em <= r.criado_em
           and l.lida_em > coalesce((select max(l2.lida_em) from usina_leitura l2
                                      where l2.usina_id = r.usina_id and l2.lida_em <= r.criado_em
                                        and l2.status is distinct from 'datalogger offline'), '-infinity'::timestamptz);
        select c2.id, c2.criado_em, c2.status into v_ant from regua_contatos c2
         where c2.usina_id = r.usina_id and c2.modelo in ('usina_wifi', 'usina_parada')
           and c2.id <> r.id and c2.criado_em < r.criado_em and c2.criado_em >= v_ini
         order by (c2.status = 'enviado') desc, c2.criado_em limit 1;
        if found then
          v_motivo := 'esta queda (desde ' || to_char(v_ini at time zone 'America/Sao_Paulo', 'DD/MM') || ') já teve aviso: contato '
                      || v_ant.id || ' de ' || to_char(v_ant.criado_em at time zone 'America/Sao_Paulo', 'DD/MM')
                      || case when v_ant.status = 'enviado' then ', enviado' else ', não enviado' end;
        end if;
      end if;
    elsif r.usina_id is not null and r.modelo = 'usina_parada' then
      select min(d.dia) into v_dia from usina_dia d
       where d.usina_id = r.usina_id and d.dia > (r.criado_em at time zone 'America/Sao_Paulo')::date and d.kwh > 0.5;
      if v_dia is not null then
        v_motivo := 'a usina voltou a gerar em ' || to_char(v_dia, 'DD/MM') || ': o aviso não vale mais';
      end if;
    end if;
    continue when v_motivo is null;
    if not p_simular then
      update regua_contatos set status = 'pulado', bloqueio_motivo = v_motivo
       where id = r.id and status = 'pendente';
    end if;
    v_itens := v_itens || jsonb_build_object('id', r.id, 'cliente', r.cliente, 'modelo', r.modelo,
                                             'aprovacao', r.status_aprovacao, 'motivo', v_motivo);
  end loop;
  return jsonb_build_object('ok', true, 'simular', p_simular, 'n', jsonb_array_length(v_itens), 'itens', v_itens);
end $function$;

comment on function public.regua_usina_resolvidos(boolean) is
  'Tira da régua (status pulado, com o motivo) o aviso de internet ou de parada que já não vale: a usina voltou a comunicar ou a gerar, ou a obra não está ligada. Simula por padrão. Roda pelo cron regua-usina-voltou e no regua_expirar (17h). 05/11.';

-- o disparo das 17h começa pelo regua_expirar: tira antes o aviso que não vale
create or replace function public.regua_expirar()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare n int;
begin
  -- aviso de usina que voltou não sai (05/11)
  perform public.regua_usina_resolvidos(false);
  update regua_contatos set status='pulado', bloqueio_motivo='passou da janela'
  where status='pendente' and data_limite < current_date;
  get diagnostics n = row_count;
  return n;
end; $function$;

-- usina que cai e volta, para a equipe (o aviso das 8h mostra às segundas)
do $do$
declare
  d text := pg_get_functiondef('public.pendencias_posvenda()'::regprocedure);
  m constant text := $m$      where m.lida_em is null and m.da_equipe = false and m.contexto = 'indicacao')
  );$m$;
begin
  if position('conexao_instavel' in d) > 0 then
    raise notice 'pendencias_posvenda já tem conexao_instavel; nada a fazer';
    return;
  end if;
  if (length(d) - length(replace(d, m, ''))) / length(m) <> 1 then
    raise exception 'marcador (fim de indicacoes_pendentes) não está uma vez só';
  end if;
  d := replace(d, m, $q$      where m.lida_em is null and m.da_equipe = false and m.contexto = 'indicacao'),

    -- Usina que cai e volta sozinha (05/11): o cliente não é avisado a cada queda
    -- (usina_aviso_cliente); a equipe vê aqui quem caiu usina_instavel_quedas_14d
    -- (3) vezes ou mais em 14 dias, para cuidar da internet de lá.
    'conexao_instavel', (select coalesce(json_agg(t order by t.quedas desc), '[]'::json) from (
      select o.cliente, o.contrato, u.apelido as usina, (x.q->>'quedas_14d')::int as quedas,
             coalesce((x.q->>'sem_comunicar')::boolean, false) as sem_comunicar_agora
      from usinas u
      join obra_usina ou on ou.usina_id = u.id and ou.saiu_em is null
      join obras o on o.id = ou.obra_id
      cross join lateral (select public.usina_queda_atual(u.id) as q) x
      where u.ativa and o.cancelada_em is null
        and (x.q->>'quedas_14d')::int >= coalesce((select nullif(valor, '')::int from config where chave = 'usina_instavel_quedas_14d'), 3)
      limit 10) t)
  );$q$);
  execute d;
end $do$;

-- armadilha 10: os dois revokes
revoke execute on function public.usina_queda_atual(uuid) from public;
revoke execute on function public.usina_queda_atual(uuid) from anon;
grant  execute on function public.usina_queda_atual(uuid) to authenticated;
grant  execute on function public.usina_queda_atual(uuid) to service_role;
revoke execute on function public.usina_aviso_cliente(uuid, uuid) from public;
revoke execute on function public.usina_aviso_cliente(uuid, uuid) from anon;
grant  execute on function public.usina_aviso_cliente(uuid, uuid) to authenticated;
grant  execute on function public.usina_aviso_cliente(uuid, uuid) to service_role;
revoke execute on function public.regua_usina_resolvidos(boolean) from public;
revoke execute on function public.regua_usina_resolvidos(boolean) from anon;
revoke execute on function public.regua_usina_resolvidos(boolean) from authenticated;
grant  execute on function public.regua_usina_resolvidos(boolean) to service_role;

-- depois de cada leitura do usina-status (09h15, 13h15, 16h15): 09h20, 13h20, 16h20
select cron.schedule('regua-usina-voltou', '20 12,16,19 * * *',
                     $c$ select public.regua_usina_resolvidos(false); $c$);
