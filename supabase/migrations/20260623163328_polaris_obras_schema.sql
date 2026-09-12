-- POLARIS OBRAS — Schema

-- 1) ETAPAS (catálogo das fases — fonte única da verdade)
create table if not exists etapas (
  numero      smallint primary key,
  nome        text not null,
  icone       text,
  descricao   text,
  prazo_texto text,
  mensagem_wa text,
  ordem       smallint
);

insert into etapas (numero, nome, icone, descricao, prazo_texto, mensagem_wa, ordem) values
 (0,'Boas-vindas','👋','Cadastro inicial / pré-início do projeto.','',
    'Seja muito bem-vindo(a) à Polaris Energia Solar! Em breve damos início ao seu projeto. ☀️',0),
 (1,'Contrato Fechado','🎉','Contrato assinado e pagamento confirmado.','Prazo: 1 a 2 dias úteis',
    'Seu contrato foi confirmado e já estamos dando início ao seu projeto!',1),
 (2,'Documentação do Projeto','📄','Elaboração do projeto técnico e documentos.','Prazo: 1 a 3 dias úteis',
    'Estamos elaborando o projeto técnico e toda a documentação necessária.',2),
 (3,'Aprovação na Concessionária','⚡','Projeto enviado para aprovação na concessionária de energia.','Prazo: 1 a 15 dias úteis',
    'Seu projeto foi enviado para aprovação na *concessionária de energia*.',3),
 (4,'Compra do Material','🛒','Aquisição dos equipamentos para o projeto.','Prazo: 1 a 2 dias úteis',
    'Estamos realizando a *compra dos equipamentos* do seu projeto!',4),
 (5,'Entrega do Material','📦','Equipamentos a caminho para instalação.','Prazo: 1 a 15 dias úteis',
    'Os equipamentos estão sendo *entregues* para iniciar a instalação!',5),
 (6,'Execução da Obra','🔨','Instalação de painéis, inversor e conexões.','Prazo: 1 a 7 dias úteis',
    'A instalação dos painéis e inversor está em andamento no seu imóvel!',6),
 (7,'Vistoria e Conexão','🔎','Troca do medidor e vistoria da concessionária.','Prazo: 1 a 5 dias úteis',
    'Instalação concluída! Aguardando *vistoria e troca do medidor*.',7),
 (8,'Sistema Ativo!','☀️','Gerando energia limpa e monitorado!','Gerando energia agora!',
    '',8)
on conflict (numero) do update set
  nome=excluded.nome, icone=excluded.icone, descricao=excluded.descricao,
  prazo_texto=excluded.prazo_texto, mensagem_wa=excluded.mensagem_wa, ordem=excluded.ordem;

-- 2) OBRAS
create table if not exists obras (
  id              uuid primary key default gen_random_uuid(),
  cliente         text not null,
  slug            text not null unique,
  telefone        text,
  potencia_kwp    numeric(7,2),
  contrato        text,
  etapa_numero    smallint not null default 1 references etapas(numero),
  status          text not null default 'Em andamento'
                  check (status in ('Boas-vindas','Em andamento','Finalizado','A configurar')),
  data_fechamento date,
  data_conclusao  date,
  observacoes     text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index if not exists idx_obras_etapa on obras (etapa_numero);
create index if not exists idx_obras_slug  on obras (slug);

-- 3) ETAPAS_HISTORICO
create table if not exists etapas_historico (
  id           bigint generated always as identity primary key,
  obra_id      uuid not null references obras(id) on delete cascade,
  etapa_numero smallint not null references etapas(numero),
  entrou_em    timestamptz not null default now(),
  por_usuario  text
);
create index if not exists idx_hist_obra on etapas_historico (obra_id);

-- 4) FOTOS
create table if not exists fotos (
  id           bigint generated always as identity primary key,
  obra_id      uuid not null references obras(id) on delete cascade,
  etapa_numero smallint references etapas(numero),
  url          text not null,
  legenda      text,
  criado_em    timestamptz not null default now()
);
create index if not exists idx_fotos_obra on fotos (obra_id);

-- 5) TRIGGERS
create or replace function fn_touch_updated() returns trigger as $$
begin new.atualizado_em := now(); return new; end;
$$ language plpgsql;

drop trigger if exists trg_obra_touch on obras;
create trigger trg_obra_touch before update on obras
  for each row execute function fn_touch_updated();

create or replace function fn_log_etapa() returns trigger
language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT') or (new.etapa_numero is distinct from old.etapa_numero) then
    insert into etapas_historico (obra_id, etapa_numero, por_usuario)
    values (new.id, new.etapa_numero, coalesce(auth.jwt() ->> 'email','sistema'));
  end if;
  return null;
end;
$$;

drop trigger if exists trg_obra_log on obras;
create trigger trg_obra_log after insert or update on obras
  for each row execute function fn_log_etapa();

-- 6) VIEWS
create or replace view vw_duracao_etapa as
with seq as (
  select obra_id, etapa_numero, entrou_em,
         lead(entrou_em) over (partition by obra_id order by entrou_em) as proximo
  from etapas_historico
)
select etapa_numero,
       count(*) filter (where proximo is not null) as amostras,
       round(avg(extract(epoch from (proximo - entrou_em))/86400.0)
             filter (where proximo is not null), 1) as dias_medio
from seq
group by etapa_numero
order by etapa_numero;

create or replace view vw_obras_paradas as
select o.id, o.cliente, o.slug, o.etapa_numero, e.nome as etapa, o.status,
       h.entrou_em,
       round(extract(epoch from (now() - h.entrou_em))/86400.0, 1) as dias_na_etapa
from obras o
join etapas e on e.numero = o.etapa_numero
join lateral (
  select entrou_em from etapas_historico
  where obra_id = o.id and etapa_numero = o.etapa_numero
  order by entrou_em desc limit 1
) h on true
where o.status <> 'Finalizado' and o.etapa_numero < 8
order by dias_na_etapa desc;

-- 7) RPC pública para a página do cliente (anon)
create or replace function get_obra_publica(p_slug text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'cliente',         o.cliente,
    'slug',            o.slug,
    'potencia_kwp',    o.potencia_kwp,
    'etapa_numero',    o.etapa_numero,
    'status',          o.status,
    'data_fechamento', o.data_fechamento,
    'data_conclusao',  o.data_conclusao,
    'etapa', jsonb_build_object(
        'numero', e.numero, 'nome', e.nome, 'icone', e.icone,
        'descricao', e.descricao, 'prazo_texto', e.prazo_texto),
    'historico', coalesce((
        select jsonb_agg(jsonb_build_object('etapa_numero', h.etapa_numero, 'entrou_em', h.entrou_em)
               order by h.entrou_em)
        from etapas_historico h where h.obra_id = o.id), '[]'::jsonb),
    'fotos', coalesce((
        select jsonb_agg(jsonb_build_object('url', f.url, 'legenda', f.legenda, 'etapa_numero', f.etapa_numero)
               order by f.criado_em)
        from fotos f where f.obra_id = o.id), '[]'::jsonb)
  )
  from obras o
  left join etapas e on e.numero = o.etapa_numero
  where o.slug = p_slug;
$$;

-- 8) SEGURANÇA (RLS)
alter table etapas            enable row level security;
alter table obras             enable row level security;
alter table etapas_historico  enable row level security;
alter table fotos             enable row level security;

drop policy if exists etapas_read  on etapas;
drop policy if exists etapas_write on etapas;
create policy etapas_read  on etapas for select to anon, authenticated using (true);
create policy etapas_write on etapas for all    to authenticated using (true) with check (true);

drop policy if exists obras_auth on obras;
create policy obras_auth on obras for all to authenticated using (true) with check (true);

drop policy if exists hist_auth on etapas_historico;
create policy hist_auth on etapas_historico for all to authenticated using (true) with check (true);

drop policy if exists fotos_auth on fotos;
create policy fotos_auth on fotos for all to authenticated using (true) with check (true);

grant execute on function get_obra_publica(text) to anon, authenticated;

-- 9) REALTIME
do $$ begin
  alter publication supabase_realtime add table obras;
exception when duplicate_object then null; end $$;
