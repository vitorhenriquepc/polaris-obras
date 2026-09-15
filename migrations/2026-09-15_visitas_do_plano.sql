-- Visitas contratadas x realizadas.
--
-- O Completo vende "uma visita tecnica anual em cada endereco". E a unica
-- parte do plano que custa mao de obra, e ate aqui nao havia onde registrar
-- que ela aconteceu. No contrato da Tays sao duas por ano, em cidades
-- diferentes; em marco ninguem saberia se a do rancho saiu.
--
-- DUAS DECISOES, para ficarem explicitas em vez de escondidas no codigo:
--
-- 1. QUANDO a visita e marcada: no MEIO do contrato (inicio + meses/2). Doze
--    meses viram uma visita no sexto mes. E um palpite meu de operacao, nao
--    uma regra do negocio -- da folga dos dois lados e deixa a visita pronta
--    antes da conversa de renovacao. A data e editavel; se o Vitor preferir
--    outro ponto, muda em plano_visitas_gerar().
--
-- 2. UMA POR ENDERECO, nao por usina. O Gilberto tem 4 usinas num endereco
--    so: seria uma visita, nao quatro. O endereco e
--    coalesce(endereco, cidade), a mesma conta que define o preco.
--    De cada endereco sai a usina de maior potencia como representante.
--
-- O endereco fica GRAVADO na visita, nao so referenciado: se alguem corrigir
-- o endereco da usina depois, o historico continua dizendo para onde o
-- tecnico foi de verdade.

create table if not exists plano_visita (
  id           uuid primary key default gen_random_uuid(),
  contrato_id  uuid not null references plano_contratos(id) on delete cascade,
  usina_id     uuid references usinas(id) on delete set null,
  endereco     text,
  prevista_para date not null,
  realizada_em date,
  equipe_id    uuid references equipe(id),
  laudo_url    text,
  observacao   text,
  status       text not null default 'prevista',
  criado_em    timestamptz not null default now(),
  constraint visita_status_ok check (status in ('prevista','realizada','cancelada')),
  constraint visita_realizada_tem_data check (status <> 'realizada' or realizada_em is not null)
);

create index if not exists idx_visita_contrato on plano_visita(contrato_id);
create index if not exists idx_visita_prevista on plano_visita(prevista_para)
  where status = 'prevista';

alter table plano_visita enable row level security;

-- mesmo formato de clientes/usinas: apagar e so do admin, o resto e de quem
-- esta autorizado. Nao repetir a ALL da plano_contratos (armadilha 8).
drop policy if exists pv_sel on plano_visita;
drop policy if exists pv_ins on plano_visita;
drop policy if exists pv_upd on plano_visita;
drop policy if exists pv_del on plano_visita;
create policy pv_sel on plano_visita for select using (is_autorizado());
create policy pv_ins on plano_visita for insert with check (is_autorizado());
create policy pv_upd on plano_visita for update using (is_autorizado()) with check (is_autorizado());
create policy pv_del on plano_visita for delete using (is_admin());


-- Cria as visitas previstas de um contrato. Idempotente: rodar de novo nao
-- duplica, porque so cria para endereco que ainda nao tem visita prevista.
create or replace function public.plano_visitas_gerar(p_contrato uuid)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare v_c record; v_quando date; v_criadas int := 0;
begin
  if not is_autorizado() then
    return json_build_object('erro','Sem permissao.');
  end if;

  select c.id, c.obra_id, c.inicio, c.meses, c.status, p.inclui_visita
    into v_c
    from plano_contratos c join planos p on p.codigo = c.plano_codigo
   where c.id = p_contrato;

  if not found then return json_build_object('erro','Contrato nao encontrado.'); end if;
  if not coalesce(v_c.inclui_visita,false) then
    return json_build_object('ok',true,'criadas',0,'motivo','Este plano nao inclui visita.');
  end if;
  if v_c.inicio is null then
    return json_build_object('ok',true,'criadas',0,
      'motivo','O contrato ainda nao comecou: sem data de inicio nao da para marcar visita.');
  end if;

  v_quando := (v_c.inicio + ((coalesce(v_c.meses,12) / 2.0) || ' months')::interval)::date;

  with locais as (
    select distinct on (coalesce(nullif(btrim(coalesce(u.endereco,'')),''), u.cidade))
           u.id as usina_id,
           coalesce(nullif(btrim(coalesce(u.endereco,'')),''), u.cidade) as onde
      from obra_usina ou
      join usinas u on u.id = ou.usina_id
     where ou.obra_id = v_c.obra_id and u.ativa
     order by coalesce(nullif(btrim(coalesce(u.endereco,'')),''), u.cidade),
              u.potencia_kwp desc nulls last
  ), novas as (
    insert into plano_visita (contrato_id, usina_id, endereco, prevista_para)
    select p_contrato, l.usina_id, l.onde, v_quando
      from locais l
     where not exists (
       select 1 from plano_visita v
        where v.contrato_id = p_contrato
          and coalesce(v.endereco,'') = coalesce(l.onde,'')
          and v.status = 'prevista')
    returning 1)
  select count(*) into v_criadas from novas;

  return json_build_object('ok',true,'criadas',v_criadas,'prevista_para',v_quando);
end;
$function$;


-- Da baixa numa visita.
create or replace function public.plano_visita_registrar(
  p_visita uuid, p_data date default current_date,
  p_equipe uuid default null, p_laudo text default null, p_obs text default null)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare v record;
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  select * into v from plano_visita where id = p_visita;
  if not found then return json_build_object('erro','Visita nao encontrada.'); end if;
  if v.status = 'realizada' then
    return json_build_object('erro','Esta visita ja foi dada como feita em '
      || to_char(v.realizada_em,'DD/MM/YYYY')||'.');
  end if;
  if p_data > current_date then
    return json_build_object('erro','A data da visita nao pode ser no futuro.');
  end if;

  update plano_visita
     set status='realizada', realizada_em=p_data, equipe_id=p_equipe,
         laudo_url=nullif(btrim(coalesce(p_laudo,'')),''),
         observacao=nullif(btrim(coalesce(p_obs,'')),'')
   where id = p_visita;

  return json_build_object('ok',true,'realizada_em',p_data);
end;
$function$;


-- O que a tela mostra.
create or replace function public.get_plano_visitas()
returns json
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  with base as (
    select v.id, v.prevista_para, v.realizada_em, v.status, v.endereco,
           v.laudo_url, v.observacao,
           o.id as obra_id, o.cliente, e.nome as tecnico,
           u.apelido as usina,
           (v.prevista_para - current_date) as dias
      from plano_visita v
      join plano_contratos c on c.id = v.contrato_id
      join obras o on o.id = c.obra_id
      left join usinas u on u.id = v.usina_id
      left join equipe e on e.id = v.equipe_id
     where v.status <> 'cancelada'
  )
  select json_build_object(
    'resumo', (select json_build_object(
        'previstas', count(*) filter (where status='prevista'),
        'atrasadas', count(*) filter (where status='prevista' and dias < 0),
        'proximos_60', count(*) filter (where status='prevista' and dias between 0 and 60),
        'realizadas', count(*) filter (where status='realizada'),
        'sem_laudo',  count(*) filter (where status='realizada'
                                         and coalesce(btrim(laudo_url),'') = '')
      ) from base),
    'lista', (select coalesce(json_agg(json_build_object(
        'id',id,'obra_id',obra_id,'cliente',cliente,'usina',usina,
        'endereco',endereco,'prevista_para',prevista_para,'dias',dias,
        'status',status,'realizada_em',realizada_em,'tecnico',tecnico,
        'laudo_url',laudo_url,'observacao',observacao
      ) order by (status='prevista') desc, prevista_para), '[]'::json) from base),
    'equipe', (select coalesce(json_agg(json_build_object('id',id,'nome',nome)
                       order by nome),'[]'::json) from equipe where ativo)
  ) into v;
  return v;
end;
$function$;

revoke execute on function public.plano_visitas_gerar(uuid) from public;
revoke execute on function public.plano_visitas_gerar(uuid) from anon;
grant  execute on function public.plano_visitas_gerar(uuid) to authenticated;
revoke execute on function public.plano_visita_registrar(uuid, date, uuid, text, text) from public;
revoke execute on function public.plano_visita_registrar(uuid, date, uuid, text, text) from anon;
grant  execute on function public.plano_visita_registrar(uuid, date, uuid, text, text) to authenticated;
revoke execute on function public.get_plano_visitas() from public;
revoke execute on function public.get_plano_visitas() from anon;
grant  execute on function public.get_plano_visitas() to authenticated;
