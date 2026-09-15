-- Autoleitura: lembrar o cliente rural de informar a leitura do relogio.
--
-- POR QUE NAO ENTROU NA REGUA
-- `regua_contatos` tem UNIQUE (obra_id, modelo): uma mensagem por modelo por
-- obra, para sempre. E o que impede a regua de repetir boas-vindas. A
-- autoleitura e MENSAL, entao ou eu criaria um modelo por mes (feio e sem
-- fim) ou afrouxaria esse indice -- e ele protege a regua inteira. Autoleitura
-- ganha casa propria.
--
-- ⚠️ NADA E ENVIADO POR ESTA MIGRACAO. Ela monta o calendario, decide quem
-- avisar e prepara o texto. O disparo automatico depende de tres decisoes do
-- Vitor que estao anotadas no fim deste arquivo. Enquanto isso a tela tem
-- botao de copiar, e a Livia manda na mao -- que ja e melhor do que nada.

create table if not exists unidade_consumidora (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obras(id) on delete cascade,
  usina_id      uuid references usinas(id) on delete set null,
  numero        text not null,
  apelido       text,
  distribuidora text,
  autoleitura   boolean not null default true,
  ativa         boolean not null default true,
  criado_em     timestamptz not null default now(),
  constraint uc_numero_por_obra unique (obra_id, numero)
);

comment on table unidade_consumidora is
  'Unidade consumidora (o relogio). Um cliente rural pode ter varias. '
  '`autoleitura` = quem informa a leitura e o cliente, nao a distribuidora.';

create table if not exists uc_leitura_prevista (
  id            uuid primary key default gen_random_uuid(),
  uc_id         uuid not null references unidade_consumidora(id) on delete cascade,
  data_prevista date not null,
  responsavel   text not null default 'cliente',
  origem        text not null default 'informada',
  avisado_vespera_em date,
  avisado_dia_em     date,
  criado_em     timestamptz not null default now(),
  constraint leitura_responsavel_ok check (responsavel in ('cliente','distribuidora')),
  constraint leitura_origem_ok check (origem in ('informada','projetada')),
  constraint leitura_unica unique (uc_id, data_prevista)
);

comment on column uc_leitura_prevista.origem is
  '`informada` = digitada do que a CPFL mostra, confiavel. '
  '`projetada` = calculada pelo dia-base, some quando a data real chegar.';

create index if not exists idx_leitura_data on uc_leitura_prevista(data_prevista);

alter table unidade_consumidora enable row level security;
alter table uc_leitura_prevista enable row level security;

do $$
declare t text;
begin
  foreach t in array array['unidade_consumidora','uc_leitura_prevista'] loop
    execute format('drop policy if exists %I on %I', t||'_sel', t);
    execute format('drop policy if exists %I on %I', t||'_ins', t);
    execute format('drop policy if exists %I on %I', t||'_upd', t);
    execute format('drop policy if exists %I on %I', t||'_del', t);
    execute format('create policy %I on %I for select using (is_autorizado())', t||'_sel', t);
    execute format('create policy %I on %I for insert with check (is_autorizado())', t||'_ins', t);
    execute format('create policy %I on %I for update using (is_autorizado()) with check (is_autorizado())', t||'_upd', t);
    execute format('create policy %I on %I for delete using (is_admin())', t||'_del', t);
  end loop;
end $$;


-- O ultimo dia util em d ou antes dele.
-- A regra do Vitor e clara: fim de semana a vigilancia roda, mensagem para
-- cliente nao. Mas a CPFL nao liga para dia util -- leitura marcada para
-- sabado existe. Em vez de pular o aviso, ele e ANTECIPADO para a sexta.
-- Avisar cedo e pior que avisar no dia; nao avisar e muito pior que os dois.
create or replace function public.dia_util_ate(d date)
returns date language sql immutable as $function$
  select case extract(dow from d)
           when 0 then d - 2   -- domingo -> sexta
           when 6 then d - 1   -- sabado  -> sexta
           else d end;
$function$;


-- Projeta as proximas leituras a partir de um dia-base do mes.
-- So cria o que ainda nao existe, e nunca por cima de uma data `informada`.
create or replace function public.uc_leituras_projetar(
  p_uc uuid, p_dia int, p_meses int default 6, p_responsavel text default 'cliente')
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare v_i int; v_d date; v_criadas int := 0;
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  if p_dia < 1 or p_dia > 31 then
    return json_build_object('erro','O dia-base precisa estar entre 1 e 31.');
  end if;

  for v_i in 1 .. greatest(p_meses,1) loop
    -- dia 31 em mes de 30 cai no ultimo dia do mes, nao no 1o do seguinte
    v_d := least(
      (date_trunc('month', current_date) + (v_i || ' months')::interval)::date
        + (p_dia - 1),
      (date_trunc('month', current_date) + ((v_i + 1) || ' months')::interval - interval '1 day')::date
    );
    insert into uc_leitura_prevista (uc_id, data_prevista, responsavel, origem)
    values (p_uc, v_d, p_responsavel, 'projetada')
    on conflict (uc_id, data_prevista) do nothing;
    if found then v_criadas := v_criadas + 1; end if;
  end loop;

  return json_build_object('ok', true, 'criadas', v_criadas);
end;
$function$;


-- Quem precisa ser avisado hoje, com o texto pronto.
--
-- vespera: dia util anterior a data da leitura
-- no dia:  so quando a leitura cai em dia util. Se cair em fim de semana, a
--          vespera antecipada ja cobriu, e mandar de novo na sexta seria
--          duas mensagens iguais no mesmo dia.
create or replace function public.autoleitura_fila()
returns json
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  with base as (
    select l.id, l.data_prevista, l.avisado_vespera_em, l.avisado_dia_em,
           u.id as uc_id, u.numero, u.apelido, coalesce(u.distribuidora,'distribuidora') dist,
           o.id as obra_id, o.cliente, o.whatsapp_grupo_id, o.telefone,
           public.dia_util_ate(l.data_prevista - 1) as avisar_vespera,
           case when extract(dow from l.data_prevista) between 1 and 5
                then l.data_prevista end as avisar_dia
      from uc_leitura_prevista l
      join unidade_consumidora u on u.id = l.uc_id
      join obras o on o.id = u.obra_id
     where l.responsavel = 'cliente'
       and u.autoleitura and u.ativa
       and l.data_prevista >= current_date - 1
  ), alvo as (
    select b.*,
           case when b.avisar_vespera = current_date and b.avisado_vespera_em is null
                then 'vespera'
                when b.avisar_dia = current_date and b.avisado_dia_em is null
                then 'dia' end as tipo
      from base b
  )
  select json_build_object(
    'hoje', (select coalesce(json_agg(json_build_object(
        'leitura_id', id, 'obra_id', obra_id, 'cliente', cliente,
        'uc', coalesce(apelido, numero), 'numero', numero,
        'data', data_prevista, 'tipo', tipo,
        'tem_grupo', whatsapp_grupo_id is not null and whatsapp_grupo_id not like 'http%',
        'texto', public.autoleitura_texto(id, tipo)
      ) order by cliente), '[]'::json) from alvo where tipo is not null),
    'proximas', (select coalesce(json_agg(json_build_object(
        'leitura_id', id, 'cliente', cliente, 'uc', coalesce(apelido, numero),
        'data', data_prevista, 'dias', data_prevista - current_date,
        'avisar_vespera', avisar_vespera,
        'antecipado', avisar_vespera <> data_prevista - 1,
        'ja_avisado', avisado_vespera_em is not null
      ) order by data_prevista, cliente), '[]'::json)
      from base where data_prevista >= current_date)
  ) into v;
  return v;
end;
$function$;


-- O texto que vai para o cliente. Data e nome vem do banco, nunca de chute.
create or replace function public.autoleitura_texto(p_leitura uuid, p_tipo text)
returns text
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v record; v_nome text; v_quando text; v_dia text;
begin
  select l.data_prevista, coalesce(u.apelido, u.numero) as uc,
         coalesce(nullif(btrim(coalesce(u.distribuidora,'')),''), 'distribuidora') as dist,
         o.cliente, o.categoria
    into v
    from uc_leitura_prevista l
    join unidade_consumidora u on u.id = l.uc_id
    join obras o on o.id = u.obra_id
   where l.id = p_leitura;
  if not found then return null; end if;

  v_nome := public.nome_tratamento(v.cliente, v.categoria);
  v_dia  := to_char(v.data_prevista, 'DD/MM');
  v_quando := case when p_tipo = 'dia' then 'hoje' else 'no dia ' || v_dia end;

  return
    case when p_tipo = 'dia'
      then '📷 *' || v_nome || ', hoje é o dia da leitura do seu relógio*' || E'\n\n'
      else '🔔 *' || v_nome || ', a leitura do seu relógio é ' || v_quando || '*' || E'\n\n'
    end
    || 'A ' || v.dist || ' marcou a leitura da unidade *' || v.uc
    || '* para *' || v_dia || '*, e nessa unidade *quem informa a leitura é você*.' || E'\n\n'
    || '📷 Tire a foto do visor do relógio e envie pelo aplicativo ou pelo canal da '
    || v.dist || '.' || E'\n\n'
    || 'Se a leitura não for enviada, a conta vem por média — e a compensação do '
    || 'seu sistema pode não entrar certa no mês.' || E'\n\n'
    || 'Qualquer dúvida é só chamar aqui. 💚' || E'\n\n'
    || '*Equipe Polaris Energia Solar* ☀️';
end;
$function$;


-- Marca que o aviso saiu. Quem manda e a tela (ou, no futuro, o cron).
create or replace function public.autoleitura_marcar(p_leitura uuid, p_tipo text)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  if p_tipo not in ('vespera','dia') then
    return json_build_object('erro','Tipo deve ser vespera ou dia.');
  end if;
  update uc_leitura_prevista
     set avisado_vespera_em = case when p_tipo='vespera' then current_date else avisado_vespera_em end,
         avisado_dia_em     = case when p_tipo='dia'     then current_date else avisado_dia_em end
   where id = p_leitura;
  if not found then return json_build_object('erro','Leitura nao encontrada.'); end if;
  return json_build_object('ok', true);
end;
$function$;


-- Cadastro pela tela.
create or replace function public.uc_salvar(p jsonb)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid; v_num text := btrim(coalesce(p->>'numero',''));
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  if v_num = '' then return json_build_object('erro','Informe o numero da unidade consumidora.'); end if;
  if nullif(p->>'obra_id','') is null then return json_build_object('erro','Sem obra.'); end if;

  insert into unidade_consumidora (obra_id, usina_id, numero, apelido, distribuidora, autoleitura)
  values ((p->>'obra_id')::uuid, nullif(p->>'usina_id','')::uuid, v_num,
          nullif(btrim(coalesce(p->>'apelido','')),''),
          nullif(btrim(coalesce(p->>'distribuidora','')),''),
          coalesce((p->>'autoleitura')::boolean, true))
  on conflict (obra_id, numero) do update
    set apelido = excluded.apelido,
        distribuidora = excluded.distribuidora,
        usina_id = excluded.usina_id,
        autoleitura = excluded.autoleitura
  returning id into v_id;

  return json_build_object('ok', true, 'uc_id', v_id);
end;
$function$;

create or replace function public.uc_leitura_salvar(
  p_uc uuid, p_data date, p_responsavel text default 'cliente')
returns json
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  if p_responsavel not in ('cliente','distribuidora') then
    return json_build_object('erro','Responsavel deve ser cliente ou distribuidora.');
  end if;
  insert into uc_leitura_prevista (uc_id, data_prevista, responsavel, origem)
  values (p_uc, p_data, p_responsavel, 'informada')
  on conflict (uc_id, data_prevista) do update
    set responsavel = excluded.responsavel, origem = 'informada';
  return json_build_object('ok', true);
end;
$function$;


-- O que a tela lista.
create or replace function public.get_autoleitura()
returns json
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'fila', public.autoleitura_fila(),
    'ucs', (select coalesce(json_agg(json_build_object(
        'id', u.id, 'obra_id', u.obra_id, 'cliente', o.cliente,
        'numero', u.numero, 'apelido', u.apelido,
        'distribuidora', u.distribuidora, 'autoleitura', u.autoleitura,
        'ativa', u.ativa,
        'proxima', (select min(l.data_prevista) from uc_leitura_prevista l
                     where l.uc_id = u.id and l.data_prevista >= current_date),
        'datas', (select coalesce(json_agg(json_build_object(
                     'id', l.id, 'data', l.data_prevista,
                     'responsavel', l.responsavel, 'origem', l.origem,
                     'avisado', l.avisado_vespera_em is not null)
                   order by l.data_prevista), '[]'::json)
                   from uc_leitura_prevista l
                  where l.uc_id = u.id and l.data_prevista >= current_date - 30)
      ) order by o.cliente, u.numero), '[]'::json)
      from unidade_consumidora u join obras o on o.id = u.obra_id
     where u.ativa),
    'obras', (select coalesce(json_agg(json_build_object('id', o.id, 'cliente', o.cliente)
               order by o.cliente), '[]'::json)
               from obras o
              where (coalesce(o.trilha,'padrao') <> 'manutencao' and public.obra_ativa(o.id))
                 or coalesce(o.cliente_externo,false)),
    'ligada', coalesce((select valor from config where chave='autoleitura_ativo'),'0')
  ) into v;
  return v;
end;
$function$;

-- Desligada. So o Vitor liga, e so depois de decidir os tres pontos abaixo.
insert into config (chave, valor) values ('autoleitura_ativo','0')
on conflict (chave) do nothing;

do $$
declare f text;
begin
  foreach f in array array[
    'uc_leituras_projetar(uuid,int,int,text)',
    'autoleitura_fila()',
    'autoleitura_texto(uuid,text)',
    'autoleitura_marcar(uuid,text)',
    'uc_salvar(jsonb)',
    'uc_leitura_salvar(uuid,date,text)',
    'get_autoleitura()',
    'dia_util_ate(date)'] loop
    execute 'revoke execute on function public.'||f||' from public';
    execute 'revoke execute on function public.'||f||' from anon';
    execute 'grant execute on function public.'||f||' to authenticated';
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- O QUE FALTA, E DEPENDE DO VITOR
--
-- 1. HORA DO AVISO "NO DIA". A regua dispara as 17h, e quem le o relogio faz
--    de manha. O aviso da vespera as 17h funciona; o do dia, nao. Precisa de
--    cron proprio de manha, e a hora e escolha dele.
--
-- 2. FIM DE SEMANA. Ja resolvi antecipando para a sexta (dia_util_ate), que
--    respeita a regra de nao mandar mensagem no sabado e no domingo. Se ele
--    preferir que a autoleitura seja excecao a essa regra, muda a funcao.
--
-- 3. CANAL PESSOAL. O Vitor pediu "no pessoal e no grupo". A regua manda so
--    para `whatsapp_grupo_id` -- canal pessoal nao existe nela. Mandar para o
--    numero do cliente exige mexer na regua-disparo, que e a trava dos 17h.
--    Nao mexi.
--
-- Ate la a tela mostra a fila do dia com o texto pronto e um botao de copiar.
-- ---------------------------------------------------------------------------
