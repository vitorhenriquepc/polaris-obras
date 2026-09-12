-- =====================================================================
-- 2026-09-12 — Travas de cadastro, conciliação extrato↔parcela,
--              linha do tempo, anotações e funil de indicação
--
-- Tudo aqui JÁ ESTÁ APLICADO no projeto dakubhcgohiwzyqiegqf.
-- Este arquivo versiona o que foi feito e permite recriar em outro ambiente.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. CAMPOS OBRIGATÓRIOS (lista editável, não código)
-- ---------------------------------------------------------------------

create table if not exists campos_obrigatorios (
  campo         text primary key,
  onde          text not null check (onde in ('obra','financeiro')),
  rotulo        text not null,
  ativo         boolean not null default true,
  ordem         int default 0,
  campo_na_tela text
);

alter table campos_obrigatorios enable row level security;
drop policy if exists co_leitura on campos_obrigatorios;
create policy co_leitura on campos_obrigatorios for select to authenticated using (true);
grant select on campos_obrigatorios to authenticated;

insert into campos_obrigatorios(campo,onde,rotulo,ordem,campo_na_tela) values
 ('cliente_id',     'obra',      'cliente (nome)',     1,'f_cli'),
 ('contrato',       'obra',      'número do contrato', 2,'f_con'),
 ('potencia_kwp',   'obra',      'potência (kWp)',     3,'f_pot'),
 ('vendedor_id',    'obra',      'vendedor',           4,'f_vend'),
 ('origem_lead',    'obra',      'origem do lead',     5,'f_org'),
 ('tipo_telhado',   'obra',      'tipo de telhado',    6,'f_tel2'),
 ('endereco',       'obra',      'endereço',           7,'f_end'),
 ('preco_negociado','financeiro','preço negociado',    8,'f_valor'),
 ('distancia_km',   'financeiro','distância (km)',     9,'f_km')
on conflict (campo) do nothing;

-- ---------------------------------------------------------------------
-- 2. PARÂMETROS
-- ---------------------------------------------------------------------

insert into config(chave,valor) values
 ('conciliacao_automatica',    '1'),
 ('conciliacao_tolerancia',    '1.00'),
 ('conciliacao_dias_max',      '90'),
 ('conciliacao_conta_receita', '01.1.06'),
 ('usina_carencia_dias',       '15'),
 ('vizinhanca_min_usinas',     '5'),
 ('regua_resumo_ativa',        '1')
on conflict (chave) do nothing;

-- o PIX do cliente vem junto (kit + instalação); o plano só tinha separado
insert into dre_plano_contas(codigo, pai, nivel, nome, tipo, natureza,
                             rateavel, no_dre, ordem, ativo)
values ('01.1.06','01.1',3,'Receita de Venda de Sistema Fotovoltaico',
        'receita','variavel',false,true,106,true)
on conflict (codigo) do nothing;

-- ---------------------------------------------------------------------
-- 3. ANOTAÇÕES DA EQUIPE (alimentam a linha do tempo; não se apagam)
-- ---------------------------------------------------------------------

create table if not exists obra_nota (
  id             bigserial primary key,
  obra_id        uuid not null references obras(id) on delete cascade,
  tipo           text not null check (tipo in ('visita','ligacao','combinado','troca','observacao')),
  texto          text not null check (length(btrim(texto)) >= 3),
  aconteceu_em   date not null default current_date,
  criado_em      timestamptz not null default now(),
  criado_por     text,
  corrigida_em   timestamptz,
  corrigida_por  text,
  texto_anterior text
);
create index if not exists ix_obra_nota_obra on obra_nota(obra_id, aconteceu_em desc);

alter table obra_nota enable row level security;
drop policy if exists nota_ler on obra_nota;
drop policy if exists nota_escrever on obra_nota;
drop policy if exists nota_corrigir on obra_nota;
create policy nota_ler      on obra_nota for select to authenticated using (true);
create policy nota_escrever on obra_nota for insert to authenticated with check (true);
create policy nota_corrigir on obra_nota for update to authenticated using (true);
grant select, insert, update on obra_nota to authenticated;
revoke delete on obra_nota from authenticated, anon, public;
grant usage on sequence obra_nota_id_seq to authenticated;

-- ---------------------------------------------------------------------
-- 4. VÍNCULO EXTRATO ↔ PARCELA
-- ---------------------------------------------------------------------

alter table extrato_rateio add column if not exists parcela_id uuid references obra_parcelas(id);
create unique index if not exists ux_rateio_parcela
  on extrato_rateio(parcela_id) where parcela_id is not null;

-- ---------------------------------------------------------------------
-- 5. AGRUPAMENTO POR CIDADE
-- ---------------------------------------------------------------------

create or replace view public.v_usina_cidade as
select u.id as usina_id,
       nullif(btrim(coalesce(nullif(btrim(u.cidade),''), o.cidade, '')), '-') as cidade
from usinas u
left join lateral (
  select o.cidade from obra_usina ou join obras o on o.id=ou.obra_id
   where ou.usina_id=u.id order by ou.principal desc nulls last limit 1
) o on true;
alter view public.v_usina_cidade set (security_invoker = true);
grant select on public.v_usina_cidade to authenticated;

-- cidade com massa suficiente ganha grupo próprio sozinha; o resto cai em regiao
create or replace view public.v_indice_regiao as
with lim as (
  select coalesce((select valor::int from config where chave='vizinhanca_min_usinas'),5) as minimo
),
base as (
  select d.dia, coalesce(vc.cidade,'sem cidade') as cidade, d.kwh_kwp
  from usina_dia d
  join usinas u on u.id=d.usina_id and u.ativa
  join v_usina_cidade vc on vc.usina_id=u.id
  where d.kwh_kwp is not null
),
cont as (select dia, cidade, count(*) as n from base group by 1,2),
mapa as (
  select b.dia,
         case when c.n >= l.minimo then b.cidade else 'regiao' end as regiao,
         b.kwh_kwp
  from base b
  join cont c on c.dia = b.dia and c.cidade = b.cidade
  cross join lim l
)
select dia, regiao, count(*) as usinas,
       round(percentile_cont(0.5) within group (order by kwh_kwp)::numeric,3) as mediana
from mapa group by 1,2;
alter view public.v_indice_regiao set (security_invoker = true);
grant select on public.v_indice_regiao to authenticated;

commit;

-- =====================================================================
-- FUNÇÕES — definições completas estão no banco. Para exportar:
--
--   select string_agg(pg_get_functiondef(p.oid), E';\n\n' order by p.proname)
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.proname in ('trava_campos_obra', ...);
--
-- Criadas ou alteradas nesta sessão:
--   trava_campos_obra()        campos obrigatórios do card
--   trava_campos_financeiro()  campos obrigatórios da ficha
--   sincroniza_valor()         JÁ EXISTIA; ganhou o flag app.espelhando
--   casar_na_hora()            casa recebimento com parcela ao lançar rateio
--   desfazer_vinculo()         desfaz o casamento ao apagar o rateio
--   casar_recebimentos(bool)   casamento em lote, com modo simular
--   conferir_travas()          acusa cadastro incompleto
--   conferir_financeiro()      acusa recebimento/parcela fora do lugar
--   conferir_saude()           junta base + travas + financeiro
--   linha_do_tempo(uuid)       história da obra, todas as fontes
--   nota_guarda_anterior()     guarda texto anterior ao corrigir
--   trava_indicacao()          telefone obrigatório, paga só se fechar
--   indicacoes_resumo(uuid)    funil honesto
--   usina_estado(uuid)         ganhou o estado recém-ligada
--   usina_dias(uuid,int)       passou a usar o índice da cidade
--   rotulo_usina(text,text)    recém-ligada vira começando
--   get_queda_svc(uuid)        barra usina em carência
--   regua_fila(int)            passou a respeitar optout_em
--   regua_resumo_dia()         resumo das 11h
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6. TRIGGERS
-- ---------------------------------------------------------------------

drop trigger if exists tg_trava_campos_obra on obras;
create trigger tg_trava_campos_obra
  before insert or update on obras
  for each row execute function trava_campos_obra();

-- o prefixo zz garante que roda DEPOIS do espelhamento (ordem alfabética)
drop trigger if exists tg_zz_trava_campos_financeiro on obra_financeiro;
create trigger tg_zz_trava_campos_financeiro
  before insert or update on obra_financeiro
  for each row execute function trava_campos_financeiro();

drop trigger if exists tg_nota_anterior on obra_nota;
create trigger tg_nota_anterior
  before update on obra_nota
  for each row execute function nota_guarda_anterior();

drop trigger if exists tg_trava_indicacao on indicacoes;
create trigger tg_trava_indicacao
  before insert or update on indicacoes
  for each row execute function trava_indicacao();

drop trigger if exists tg_casar_na_hora on extrato_rateio;
create trigger tg_casar_na_hora
  before insert on extrato_rateio
  for each row execute function casar_na_hora();

-- PRECISA ser constraint trigger deferrable: a FK lancamento_id é
-- ON DELETE SET NULL e tentaria atualizar a própria linha sendo apagada.
drop trigger if exists tg_desfazer_vinculo on extrato_rateio;
create constraint trigger tg_desfazer_vinculo
  after delete on extrato_rateio
  deferrable initially deferred
  for each row execute function desfazer_vinculo();

-- ---------------------------------------------------------------------
-- 7. AUTOMAÇÕES (aparecem na tela de configuração)
-- ---------------------------------------------------------------------

insert into automacoes(chave,nome,descricao,grupo,ordem,visivel) values
('conciliacao_automatica','Casar recebimento com parcela',
 'Quando um valor do extrato é apontado para uma obra, o sistema procura a parcela de mesmo valor, marca como recebida e lança a receita no DRE. Tolerância e prazo são ajustáveis.',
 'Financeiro',40,true),
('regua_resumo_ativa','Resumo da régua para a equipe',
 'Todo dia útil às 11h, avisa a responsável pelo pós-venda o que está esperando autorização e o que sai às 17h. Se não houver nada, não manda nada.',
 'Pós-venda',35,true)
on conflict (chave) do update
  set nome = excluded.nome, descricao = excluded.descricao;

-- ---------------------------------------------------------------------
-- 8. CRON (horários em UTC; Brasília = UTC-3)
-- ---------------------------------------------------------------------
--   select cron.schedule('regua-resumo','0 14 * * 1-5', $cron$
--     select net.http_post(
--       url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/regua-resumo',
--       headers := jsonb_build_object('Content-Type','application/json'),
--       body := jsonb_build_object('token',(select valor from config where chave='cron_token')),
--       timeout_milliseconds := 60000);
--   $cron$);

-- ---------------------------------------------------------------------
-- 9. CARGA ÚNICA (executada em 12/09/2026 — não repetir)
-- ---------------------------------------------------------------------
-- 16 recebimentos estavam apontados para obras sem conta e sem lançamento no
-- DRE, somando R$ 107.265. Todos casaram com parcela de mesmo valor e mesma
-- data. Agosto foi de R$ 115.463 para R$ 208.728 de receita.
--
--   select * from casar_recebimentos(true);   -- simular
--   select * from casar_recebimentos(false);  -- gravar
--
-- Também foram canceladas 7 mensagens de um cliente com optout que seguia na fila:
--
--   update regua_contatos c set status='cancelado',
--          bloqueio_motivo = coalesce(bloqueio_motivo||' · ','')
--                            || 'cliente pediu para sair da regua'
--   from obras o
--   where o.id=c.obra_id and o.optout_em is not null and c.status='pendente';
