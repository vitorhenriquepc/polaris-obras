-- =====================================================================
-- 2026-09-12 — Travas de cadastro, conciliação extrato↔parcela,
--              linha do tempo, anotações e funil de indicação
--
-- Tudo aqui JÁ ESTÁ APLICADO no projeto dakubhcgohiwzyqiegqf.
-- Este arquivo versiona o que foi feito e permite recriar em outro ambiente.
-- As funções da seção 6 foram exportadas do banco e conferidas por md5.
-- O que ainda falta para recriar do zero está na seção 11.
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
 ('distancia_km',   'financeiro','distância (km) — fica na ficha financeira', 9,'f_km')
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
 ('ger_vizinhanca_ativa',      '1'),   -- sem isto usina_dias ignora a cidade
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

-- ---------------------------------------------------------------------
-- 6. FUNÇÕES
--
-- Exportadas do banco com pg_get_functiondef em 12/09/2026 e conferidas
-- uma a uma por md5 contra o projeto dakubhcgohiwzyqiegqf — o texto abaixo
-- é o que está rodando, não uma reescrita.
--
-- Precisam vir antes da seção 7: os triggers apontam para elas.
-- Estas dependem de coisas que vieram antes de 12/09 e ainda não estão
-- versionadas: conferir_saude_base(), queda_geracao(), regua_texto(),
-- regua_bloqueio(), v_indice_dia e as tabelas do pós-venda.
-- ---------------------------------------------------------------------

-- trava_campos_obra — campos obrigatórios do card.
-- Confere new.cliente (TEXTO). A chave na tabela se chama cliente_id por
-- herança; exigir cliente_id de verdade travaria card recém-criado.
CREATE OR REPLACE FUNCTION public.trava_campos_obra()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare faltam text[] := array[]::text[];
begin
  if coalesce(new.trilha,'padrao') <> 'padrao' then return new; end if;
  if exists (select 1 from campos_obrigatorios where campo='cliente_id' and ativo)
     and coalesce(btrim(new.cliente),'') = '' then faltam := faltam || array['cliente']; end if;
  if exists (select 1 from campos_obrigatorios where campo='contrato' and ativo)
     and coalesce(btrim(new.contrato::text),'') = '' then faltam := faltam || array['número do contrato']; end if;
  if exists (select 1 from campos_obrigatorios where campo='potencia_kwp' and ativo)
     and coalesce(new.potencia_kwp,0) <= 0 then faltam := faltam || array['potência (kWp)']; end if;
  if exists (select 1 from campos_obrigatorios where campo='vendedor_id' and ativo)
     and new.vendedor_id is null then faltam := faltam || array['vendedor']; end if;
  if exists (select 1 from campos_obrigatorios where campo='origem_lead' and ativo)
     and coalesce(btrim(new.origem_lead),'') = '' then faltam := faltam || array['origem do lead']; end if;
  if exists (select 1 from campos_obrigatorios where campo='tipo_telhado' and ativo)
     and coalesce(btrim(new.tipo_telhado),'') = '' then faltam := faltam || array['tipo de telhado']; end if;
  if exists (select 1 from campos_obrigatorios where campo='endereco' and ativo)
     and coalesce(btrim(new.endereco),'') = '' then faltam := faltam || array['endereço']; end if;
  if array_length(faltam,1) > 0 then
    raise exception 'Para salvar, preencha: %', array_to_string(faltam, ', ') using errcode='P0001';
  end if;
  return new;
end $function$;

-- trava_campos_financeiro — campos obrigatórios da ficha.
-- Sai fora quando app.espelhando=1: reflexo do valor da obra não é edição.

CREATE OR REPLACE FUNCTION public.trava_campos_financeiro()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare faltam text[] := array[]::text[]; v_km numeric; v_valor numeric;
begin
  -- reflexo do valor digitado na obra nao e edicao da ficha: nao exige nada
  if coalesce(current_setting('app.espelhando', true),'') = '1' then return new; end if;
  if coalesce(new.dispensado,false) then return new; end if;

  select distancia_km, valor_projeto into v_km, v_valor from obras where id = new.obra_id;
  if exists (select 1 from campos_obrigatorios where campo='preco_negociado' and ativo)
     and coalesce(new.preco_negociado,0) <= 0 and coalesce(v_valor,0) <= 0
     then faltam := faltam || array['valor do projeto']; end if;
  if exists (select 1 from campos_obrigatorios where campo='distancia_km' and ativo)
     and coalesce(v_km,0) <= 0 then faltam := faltam || array['distância em km']; end if;

  if array_length(faltam,1) > 0 then
    raise exception 'Para salvar, preencha: %', array_to_string(faltam, ', ') using errcode='P0001';
  end if;
  return new;
end $function$;

-- sincroniza_valor — JÁ EXISTIA antes de 12/09; ganhou o flag app.espelhando.
-- Espelha valor_projeto em preco_negociado. NÃO criar outro espelhamento.

CREATE OR REPLACE FUNCTION public.sincroniza_valor()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(new.valor_projeto,0) > 0
     and coalesce(new.valor_projeto,0) is distinct from coalesce(old.valor_projeto,0) then
    perform set_config('app.espelhando','1',true);
    update obra_financeiro set preco_negociado = new.valor_projeto where obra_id = new.id;
    perform set_config('app.espelhando','',true);
  end if;
  return new;
end $function$;

-- casar_na_hora — ao apontar um valor do extrato para uma obra, procura a
-- parcela de mesmo valor, marca recebida e lança a receita no DRE.

CREATE OR REPLACE FUNCTION public.casar_na_hora()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_parcela uuid; v_lanc uuid; v_data date; v_entrada boolean;
        v_tol numeric; v_conta text; v_dias int;
begin
  if coalesce((select valor from config where chave='conciliacao_automatica'),'1') <> '1'
     then return new; end if;
  if new.obra_id is null or new.conta_codigo is not null or new.parcela_id is not null then
    return new;
  end if;

  v_tol   := coalesce((select valor::numeric from config where chave='conciliacao_tolerancia'),1.00);
  v_conta := coalesce((select valor from config where chave='conciliacao_conta_receita'),'01.1.06');
  v_dias  := coalesce((select valor::int from config where chave='conciliacao_dias_max'),90);

  select m.data_mov, m.valor > 0 into v_data, v_entrada
  from extrato_movimentos m where m.id = new.movimento_id;
  if not coalesce(v_entrada,false) then return new; end if;

  select pa.id into v_parcela from obra_parcelas pa
  where pa.obra_id = new.obra_id
    and abs(pa.valor - new.valor) <= v_tol
    and abs(pa.vencimento - v_data) <= v_dias
    and not exists (select 1 from extrato_rateio x where x.parcela_id = pa.id)
  order by abs(pa.vencimento - v_data) limit 1;

  if v_parcela is null then return new; end if;

  insert into dre_lancamentos(data_competencia, data_caixa, conta_codigo, obra_id,
                              valor, descricao, origem, criado_por)
  values (v_data, v_data, v_conta, new.obra_id, new.valor,
          'Recebimento conciliado do extrato', 'extrato', 'conciliacao automatica')
  returning id into v_lanc;

  new.conta_codigo := v_conta;
  new.lancamento_id := v_lanc;
  new.parcela_id := v_parcela;
  update obra_parcelas set recebida=true, recebida_em=v_data where id=v_parcela;
  return new;
end $function$;

-- desfazer_vinculo — desfaz o casamento quando o rateio é apagado.
-- Roda em constraint trigger deferrable (ver seção 7).

CREATE OR REPLACE FUNCTION public.desfazer_vinculo()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.parcela_id is not null then
    update obra_parcelas set recebida=false, recebida_em=null where id=old.parcela_id;
    delete from dre_lancamentos where id = old.lancamento_id and criado_por='conciliacao automatica';
  end if;
  return old;
end $function$;

-- casar_recebimentos(simular) — casamento em lote. p_simular=true por padrão:
-- mostra o que faria sem gravar nada.

CREATE OR REPLACE FUNCTION public.casar_recebimentos(p_simular boolean DEFAULT true)
 RETURNS TABLE(contrato text, cliente text, valor numeric, data_banco date, parcela integer, acao text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_parcela uuid; v_lanc uuid;
begin
  for r in
    select ra.id as rateio_id, ra.obra_id, ra.valor, m.data_mov,
           o.contrato, split_part(o.cliente,' ',1) as cli
    from extrato_rateio ra
    join extrato_movimentos m on m.id = ra.movimento_id
    join obras o on o.id = ra.obra_id
    where ra.conta_codigo is null and ra.parcela_id is null and m.valor > 0
    order by ra.valor desc
  loop
    select pa.id into v_parcela
    from obra_parcelas pa
    where pa.obra_id = r.obra_id
      and abs(pa.valor - r.valor) < 1
      and not exists (select 1 from extrato_rateio x where x.parcela_id = pa.id)
    order by abs(pa.vencimento - r.data_mov)
    limit 1;

    if v_parcela is null then
      contrato:=r.contrato; cliente:=r.cli; valor:=r.valor; data_banco:=r.data_mov;
      parcela:=null; acao:='sem parcela prevista'; return next;
      continue;
    end if;

    if not p_simular then
      insert into dre_lancamentos(data_competencia, data_caixa, conta_codigo, obra_id,
                                  valor, descricao, origem, criado_por)
      values (r.data_mov, r.data_mov, '01.1.06', r.obra_id, r.valor,
              'Recebimento conciliado do extrato', 'extrato', 'conciliacao automatica')
      returning id into v_lanc;
      update extrato_rateio set conta_codigo='01.1.06', lancamento_id=v_lanc, parcela_id=v_parcela
       where id = r.rateio_id;
      update obra_parcelas set recebida=true, recebida_em=r.data_mov where id = v_parcela;
    end if;

    contrato:=r.contrato; cliente:=r.cli; valor:=r.valor; data_banco:=r.data_mov;
    parcela:=(select numero from obra_parcelas where id=v_parcela);
    acao:= case when p_simular then 'casaria' else 'casado' end; return next;
  end loop;
end $function$;

-- conferir_travas — acusa cadastro incompleto e exigência sem campo na tela.

CREATE OR REPLACE FUNCTION public.conferir_travas()
 RETURNS TABLE(gravidade integer, achado text, detalhe text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int; lista text;
begin
  -- 1) exigencia sem campo correspondente na tela (foi o erro do card do Tognon)
  for r in select campo, rotulo from campos_obrigatorios
            where ativo and coalesce(campo_na_tela,'') = '' loop
    gravidade := 1;
    achado := 'campo exigido que a tela nao preenche';
    detalhe := r.rotulo || ' (' || r.campo || ') — travaria sem ter onde digitar';
    return next;
  end loop;

  -- 2) cards de obra que seriam recusados (so leitura)
  select count(*), coalesce(string_agg(contrato, ' ' order by contrato) filter (where contrato is not null),'')
    into n, lista
  from obras o where coalesce(o.trilha,'padrao')='padrao' and (
       (exists (select 1 from campos_obrigatorios where campo='cliente_id' and ativo)
        and coalesce(btrim(o.cliente),'')='' and o.cliente_id is null)
    or (exists (select 1 from campos_obrigatorios where campo='contrato' and ativo)
        and coalesce(btrim(o.contrato::text),'')='')
    or (exists (select 1 from campos_obrigatorios where campo='potencia_kwp' and ativo)
        and coalesce(o.potencia_kwp,0)<=0)
    or (exists (select 1 from campos_obrigatorios where campo='vendedor_id' and ativo)
        and o.vendedor_id is null)
    or (exists (select 1 from campos_obrigatorios where campo='origem_lead' and ativo)
        and coalesce(btrim(o.origem_lead),'')='')
    or (exists (select 1 from campos_obrigatorios where campo='tipo_telhado' and ativo)
        and coalesce(btrim(o.tipo_telhado),'')='')
    or (exists (select 1 from campos_obrigatorios where campo='endereco' and ativo)
        and coalesce(btrim(o.endereco),'')=''));
  if n > 0 then
    gravidade := 3; achado := n || ' card(s) de obra incompletos';
    detalhe := 'contratos: ' || left(lista, 200); return next;
  end if;

  -- 3) fichas financeiras que seriam recusadas
  select count(*) into n
  from obra_financeiro f join obras o on o.id=f.obra_id
  where not coalesce(f.dispensado,false) and (
      (exists (select 1 from campos_obrigatorios where campo='preco_negociado' and ativo)
       and coalesce(f.preco_negociado,0)<=0 and coalesce(o.valor_projeto,0)<=0)
   or (exists (select 1 from campos_obrigatorios where campo='distancia_km' and ativo)
       and coalesce(o.distancia_km,0)<=0));
  if n > 0 then
    gravidade := 3; achado := n || ' ficha(s) financeira(s) incompletas';
    detalhe := 'falta valor do projeto ou distancia em km'; return next;
  end if;
end $function$;

-- conferir_financeiro — acusa recebimento e parcela fora do lugar.

CREATE OR REPLACE FUNCTION public.conferir_financeiro()
 RETURNS TABLE(gravidade integer, achado text, detalhe text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; lista text; v numeric;
begin
  -- entrada apontada para obra que nao encontrou parcela
  select count(*), coalesce(string_agg(distinct o.contrato,' '),'') into n, lista
  from extrato_rateio r join extrato_movimentos m on m.id=r.movimento_id
  join obras o on o.id=r.obra_id
  where r.conta_codigo is null and m.valor > 0;
  if n > 0 then gravidade:=2; achado:=n||' recebimento(s) sem parcela para casar';
    detalhe:='contratos: '||left(lista,150); return next; end if;

  -- parcela marcada recebida sem dinheiro no banco
  select count(*), coalesce(string_agg(distinct o.contrato,' '),'') into n, lista
  from obra_parcelas pa join obras o on o.id=pa.obra_id
  where pa.recebida and not exists (select 1 from extrato_rateio r where r.parcela_id=pa.id);
  if n > 0 then gravidade:=3; achado:=n||' parcela(s) marcada(s) como recebida sem extrato';
    detalhe:='contratos: '||left(lista,150); return next; end if;

  -- ficha cuja soma das parcelas nao fecha com o preco
  select count(*) into n from (
    select f.obra_id, f.preco_negociado, sum(pa.valor) as total
    from obra_financeiro f join obra_parcelas pa on pa.obra_id=f.obra_id
    where coalesce(f.preco_negociado,0)>0 and not coalesce(f.dispensado,false)
    group by 1,2 having abs(sum(pa.valor) - f.preco_negociado) > 1) x;
  if n > 0 then gravidade:=3; achado:=n||' ficha(s) com parcelas que nao fecham com o preço';
    detalhe:='abrir o financeiro e completar o parcelamento'; return next; end if;

  -- movimento ainda sem classificar
  select count(*) into n from extrato_movimentos where situacao='pendente';
  if n > 0 then gravidade:=4; achado:=n||' movimento(s) de extrato sem classificar';
    detalhe:='conciliar no financeiro'; return next; end if;
end $function$;

-- conferir_saude — a conferência das 7h30. Junta a base com travas e financeiro.
-- Depende de conferir_saude_base(), que é anterior a 12/09 e não está aqui.

CREATE OR REPLACE FUNCTION public.conferir_saude()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_base json; v_travas json; v_fin json;
begin
  v_base := conferir_saude_base();
  select coalesce(json_agg(json_build_object('achado',achado,'qtd',1,'detalhe',detalhe)),'[]'::json)
    into v_travas from conferir_travas();
  select coalesce(json_agg(json_build_object('achado',achado,'qtd',1,'detalhe',detalhe)),'[]'::json)
    into v_fin from conferir_financeiro();
  return (select json_agg(x) from (
    select * from json_array_elements(v_base)
    union all select * from json_array_elements(v_travas)
    union all select * from json_array_elements(v_fin)) t(x));
end $function$;

-- linha_do_tempo(obra) — história completa: etapas, travas, relatórios,
-- pagamentos, NPS, mensagens da régua e marcos de retorno.

CREATE OR REPLACE FUNCTION public.linha_do_tempo(p_obra uuid)
 RETURNS TABLE(quando timestamp with time zone, tipo text, titulo text, detalhe text, icone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with o as (select id, coalesce(trilha,'padrao') as trilha from obras where id = p_obra)
  select h.entrou_em, 'etapa',
         'Entrou em ' || coalesce(e.nome, 'etapa '||h.etapa_numero),
         nullif(h.por_usuario,''), coalesce(e.icone,'📍')
  from etapas_historico h cross join o
  left join etapas e on e.numero = h.etapa_numero and e.trilha = o.trilha
  where h.obra_id = p_obra
  union all
  select t.inicio, 'trava', 'Travou: ' || t.trava,
         case when t.fim is not null
              then 'resolvido em ' || to_char(t.fim,'DD/MM') || ' (' || (t.fim::date - t.inicio::date) || ' dias parado)'
              else 'ainda aberto' end, '🚧'
  from travas_historico t where t.obra_id = p_obra
  union all
  select r.criado_em, 'relatorio', 'Relatório anexado',
         coalesce(r.titulo,'') , '📎'
  from obra_relatorios r where r.obra_id = p_obra
  union all
  select (p.recebida_em)::timestamptz, 'pagamento', 'Parcela ' || p.numero || ' recebida',
         'R$ ' || to_char(p.valor,'FM999G999D00'), '💰'
  from obra_parcelas p where p.obra_id = p_obra and p.recebida and p.recebida_em is not null
  union all
  select n.criado_em, 'nps', 'Avaliou com nota ' || n.nota,
         nullif(left(coalesce(n.comentario,''),120),''), '⭐'
  from nps n where n.obra_id = p_obra and n.nota is not null
  union all
  select c.enviado_em, 'contato', coalesce(m.nome, c.modelo),
         left(coalesce(c.texto_custom,''),120), '💬'
  from regua_contatos c left join regua_modelos m on m.codigo=c.modelo
  where c.obra_id = p_obra and c.status='enviado' and c.enviado_em is not null
  union all
  select (k.atingido_em)::timestamptz, 'marco', 'Atingiu ' || k.marco || '% do retorno',
         'R$ ' || to_char(k.economizado,'FM999G999D00') || ' economizados', '🎯'
  from usina_marco k join obra_usina ou on ou.usina_id = k.usina_id
  where ou.obra_id = p_obra
  order by 1;
$function$;

-- nota_guarda_anterior — ao corrigir uma anotação, guarda o texto antigo.
-- Anotação se corrige, não se apaga.

CREATE OR REPLACE FUNCTION public.nota_guarda_anterior()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.texto is distinct from old.texto then
    new.texto_anterior := old.texto;
    new.corrigida_em := now();
  end if;
  new.obra_id := old.obra_id;      -- nao deixa mudar de obra
  new.criado_em := old.criado_em;
  new.criado_por := old.criado_por;
  return new;
end $function$;

-- trava_indicacao — sem telefone a indicação não passa de nova; prêmio só
-- depois que o indicado fecha.

CREATE OR REPLACE FUNCTION public.trava_indicacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare tem_fone boolean;
begin
  tem_fone := coalesce(length(regexp_replace(coalesce(new.telefone_indicado,''),'\D','','g')), 0) >= 10;

  -- sem telefone, a indicacao nao sai de "nova": nome solto e intencao, nao indicacao
  if not tem_fone and (new.contatada_em is not null or new.visita_em is not null
                       or new.fechada_em is not null) then
    raise exception 'Indicação sem telefone não avança: registre o número de % antes',
      coalesce(nullif(btrim(new.nome_indicado),''),'quem foi indicado') using errcode='P0001';
  end if;
  if not tem_fone and coalesce(new.status,'nova') not in ('nova','perdida') then
    raise exception 'Indicação sem telefone só pode ficar como nova ou perdida' using errcode='P0001';
  end if;

  -- brinde/premio so quando fecha
  if (new.pago_etapa1_em is not null or new.pago_etapa2_em is not null)
     and new.fechada_em is null then
    raise exception 'Só dá para pagar indicação depois que o indicado fecha' using errcode='P0001';
  end if;

  -- fechou sem estar contatada? registra o contato junto, para o funil nao mentir
  if new.fechada_em is not null and new.contatada_em is null then
    new.contatada_em := new.fechada_em;
  end if;

  return new;
end $function$;

-- indicacoes_resumo(obra) — funil. Só conta como fechada o que fechou.

CREATE OR REPLACE FUNCTION public.indicacoes_resumo(p_obra uuid DEFAULT NULL::uuid)
 RETURNS TABLE(registradas integer, com_telefone integer, contatadas integer, fechadas integer, a_pagar integer, valor_a_pagar numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int,
         count(*) filter (where length(regexp_replace(coalesce(telefone_indicado,''),'\D','','g')) >= 10)::int,
         count(*) filter (where contatada_em is not null)::int,
         count(*) filter (where fechada_em is not null)::int,
         count(*) filter (where fechada_em is not null and pago_etapa1_em is null)::int,
         coalesce(sum(coalesce(valor_etapa1,0) + coalesce(valor_etapa2,0))
                  filter (where fechada_em is not null and pago_etapa1_em is null), 0)
  from indicacoes
  where p_obra is null or indicador_obra_id = p_obra;
$function$;

-- usina_estado(usina) — normal, sem comunicação, parada, recém-ligada...
-- Datalogger offline reporta zero: isso é "não medi", não "não gerou".

CREATE OR REPLACE FUNCTION public.usina_estado(p_usina uuid)
 RETURNS TABLE(estado text, motivo text, dias_sem_gerar integer, dias_sol_perdidos integer, gravidade integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (select * from usinas where id = p_usina),
  ini as (
    -- quando a usina entrou em operacao de verdade
    select coalesce(u.data_instalacao,
                    (select o.data_conclusao from obra_usina ou join obras o on o.id=ou.obra_id
                      where ou.usina_id=p_usina order by ou.principal desc limit 1)) as desde
    from u
  ),
  carencia as (
    select coalesce((select valor::int from config where chave='usina_carencia_dias'),15) as dias
  ),
  nova as (
    select (i.desde is not null and (current_date - i.desde) <= c.dias) as e_nova,
           greatest(0, (current_date - i.desde)) as idade
    from ini i, carencia c
  ),
  hist as (
    select count(*)::int as lidos,
           count(*) filter (where kwh > 0.5)::int as gerou,
           max(dia) filter (where kwh > 0.5) as ultimo_ok
    from usina_dia d cross join u
    where d.usina_id = p_usina and d.dia < current_date
      and (u.data_instalacao is null or d.dia >= u.data_instalacao)
  ),
  mudo as (
    select (u.status_atual in ('datalogger offline','datalogger sem coletar')
            or u.causa = 'wifi') as sem_medir,
           coalesce((current_date - hh.ultimo_ok),
             case when u.status_desde is null then null
                  else (current_date - u.status_desde::date) end) as dias_mudo
    from u, hist hh
  ),
  ult as (
    select d.dia, d.kwh, i.mediana_kwh_kwp, row_number() over (order by d.dia desc) as pos
    from usina_dia d left join v_indice_dia i on i.dia = d.dia cross join u
    where d.usina_id = p_usina and d.dia < current_date
      and (u.data_instalacao is null or d.dia >= u.data_instalacao)
    order by d.dia desc limit 20
  ),
  zerados as (
    select coalesce(count(*),0)::int as n from (
      select pos, kwh, sum(case when kwh > 0.5 then 1 else 0 end)
             over (order by pos rows unbounded preceding) as marca from ult
    ) z where z.marca = 0
  ),
  sol_perdido as (
    select coalesce(count(*),0)::int as n from (
      select pos, kwh, mediana_kwh_kwp,
             sum(case when kwh > 0.5 or coalesce(mediana_kwh_kwp,0) <= 1.5 then 1 else 0 end)
               over (order by pos rows unbounded preceding) as marca from ult
    ) z where z.marca = 0 and coalesce(z.mediana_kwh_kwp,0) > 1.5
  )
  select
    case
      when u.status_atual in ('nao injetando','nao injetando com evento',
                              'inversores inativos','medidores inativos') then 'crítico'
      -- usina recem ligada que ainda nao reportou: nao e problema, e comeco
      when nv.e_nova and hh.gerou = 0 then 'recém-ligada'
      when m.sem_medir then 'sem comunicação'
      when hh.lidos = 0 then 'sem dado'
      when hh.gerou = 0 then 'nunca gerou'
      when z.n >= 5 then 'parada'
      when u.status_atual = 'operando' and sp.n >= 2 then 'silencioso'
      when u.status_atual = 'operando' then 'normal'
      when u.status_atual is null then 'sem dado'
      else 'alerta'
    end,
    case
      when u.status_atual in ('nao injetando','nao injetando com evento') then 'o inversor parou de injetar na rede'
      when u.status_atual = 'inversores inativos' then 'inversores inativos'
      when u.status_atual = 'medidores inativos' then 'medidores inativos'
      when nv.e_nova and hh.gerou = 0 then
        'ligada há ' || nv.idade || ' dia' || case when nv.idade=1 then '' else 's' end
        || ' — ainda pode não ter começado a reportar'
      when m.sem_medir and hh.ultimo_ok is not null then
        'sem medição há ' || m.dias_mudo || ' dias (última em ' || to_char(hh.ultimo_ok,'DD/MM')
        || ') — pode estar gerando, mas não conseguimos acompanhar'
      when m.sem_medir then
        'sem comunicar desde a instalação — pode estar gerando, mas não conseguimos acompanhar'
      when hh.lidos = 0 then 'a plataforma não devolve nenhum dado — conferir o cadastro'
      when hh.gerou = 0 then 'nunca gerou desde a instalação — equipamento provavelmente não ligado'
      when z.n >= 5 then 'comunicando e sem gerar há ' || z.n || ' dias (gerava até ' || to_char(hh.ultimo_ok,'DD/MM') || ')'
      when u.status_atual = 'operando' and sp.n >= 2
        then 'a plataforma diz operando, mas não gerou em ' || sp.n || ' dias seguidos de sol'
      when u.status_atual = 'operando' then 'gerando normalmente'
      else coalesce(u.status_atual,'sem status')
    end,
    z.n, sp.n,
    case
      when u.status_atual in ('nao injetando','nao injetando com evento',
                              'inversores inativos','medidores inativos') then 1
      when nv.e_nova and hh.gerou = 0 then 5      -- so acompanhar, nao e problema
      when m.sem_medir and coalesce(m.dias_mudo,999) >= 15 then 2
      when m.sem_medir then 3
      when hh.lidos = 0 then 3
      when hh.gerou = 0 then 2
      when z.n >= 5 then 1
      when u.status_atual = 'operando' and sp.n >= 2 then 2
      else 4
    end
  from u, nova nv, hist hh, mudo m, zerados z, sol_perdido sp;
$function$;

-- usina_dias(usina, dias) — geração diária com esperado, clima e base usada.
-- A base cai para carteira se ger_vizinhanca_ativa não for 1 (ver seção 2).

CREATE OR REPLACE FUNCTION public.usina_dias(p_usina uuid, p_dias integer DEFAULT 30)
 RETURNS TABLE(dia date, kwh numeric, kwh_kwp numeric, indice numeric, esperado numeric, razao numeric, anormal boolean, fim_de_semana boolean, chuva_mm numeric, sol_horas numeric, tempo text, sem_medicao boolean, base_usada text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (select * from usinas where id = p_usina),
  minha_cidade as (select coalesce(cidade,'sem cidade') as c from v_usina_cidade where usina_id = p_usina),
  liga as (select coalesce((select valor from config where chave='ger_vizinhanca_ativa'),'0')='1' as usar),
  ok as (select max(d.dia) as ultimo from usina_dia d where d.usina_id=p_usina and d.kwh > 0.5),
  mudo as (select (u.status_atual in ('datalogger offline','datalogger sem coletar')
                   or u.causa='wifi') as sem_medir from u),
  meu as (
    select d.dia as d_dia, d.kwh as d_kwh, d.kwh_kwp as d_kwp
    from usina_dia d where d.usina_id = p_usina and d.dia >= current_date - p_dias
  ),
  -- escolhe sozinho: cidade dela se tiver grupo no dia, senao o balde regional,
  -- e se nem isso existir volta para a carteira inteira
  idx as (
    select g.dia,
           coalesce(cid.mediana, reg.mediana, g.mediana_kwh_kwp) as mediana,
           case when cid.mediana is not null then 'cidade'
                when reg.mediana is not null then 'regiao'
                else 'carteira' end as base
    from v_indice_dia g
    cross join liga l cross join minha_cidade mc
    left join v_indice_regiao cid on l.usar and cid.dia=g.dia and cid.regiao = mc.c
    left join v_indice_regiao reg on l.usar and reg.dia=g.dia and reg.regiao = 'regiao'
  ),
  base as (
    select percentile_cont(0.5) within group (order by d.kwh_kwp / nullif(i.mediana,0)) as fator_dia
    from usina_dia d join idx i on i.dia = d.dia
    where d.usina_id = p_usina and d.dia >= current_date - 60
      and d.kwh_kwp is not null and i.mediana > 0.5
  )
  select
    m.d_dia, m.d_kwh, m.d_kwp, i.mediana,
    round((i.mediana * coalesce(b.fator_dia,1))::numeric, 3),
    case when i.mediana * coalesce(b.fator_dia,1) > 0.3
         then round((m.d_kwp / (i.mediana * coalesce(b.fator_dia,1)))::numeric, 2) end,
    (not (md.sem_medir and coalesce(m.d_kwh,0) <= 0.5
          and (o.ultimo is null or m.d_dia > o.ultimo))
     and i.mediana > 1.5
     and m.d_kwp < (i.mediana * coalesce(b.fator_dia,1) * 0.5)),
    extract(dow from m.d_dia) in (0,6),
    c.chuva_mm, c.sol_horas,
    case when c.dia is null then null
         when coalesce(c.chuva_mm,0) >= 5 then 'chuva'
         when coalesce(c.sol_horas,0) >= 9 and coalesce(c.nuvens_pct,0) <= 30 then 'sol'
         when coalesce(c.sol_horas,0) >= 6 then 'sol entre nuvens'
         else 'nublado' end,
    (md.sem_medir and coalesce(m.d_kwh,0) <= 0.5 and (o.ultimo is null or m.d_dia > o.ultimo)),
    i.base
  from meu m
  cross join base b cross join mudo md cross join ok o
  left join idx i on i.dia = m.d_dia
  left join clima_dia c on c.dia = m.d_dia
  order by m.d_dia;
$function$;

-- rotulo_usina(estado, causa) — como o estado aparece para gente.

CREATE OR REPLACE FUNCTION public.rotulo_usina(p_estado text, p_causa text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_causa = 'wifi' then 'sem wi-fi'
    when p_causa = 'sem_energia' then 'sem energia no local'
    when p_causa = 'desligado_pelo_cliente' then 'desligada pelo cliente'
    when p_causa = 'obra_no_local' then 'obra no local'
    when p_causa = 'aguardando_concessionaria' then 'aguardando concessionária'
    when p_causa = 'defeito_inversor' then 'defeito no inversor'
    when p_causa = 'cadastro_errado' then 'cadastro a corrigir'
    when p_causa = 'outro' then 'motivo registrado'
    when p_estado = 'sem comunicação' then 'sem medição'
    when p_estado = 'recém-ligada' then 'começando'
    else p_estado
  end;
$function$;

-- get_queda_svc(usina) — material para a mensagem de queda. Barra usina em
-- carência e usina que não está em estado normal.

CREATE OR REPLACE FUNCTION public.get_queda_svc(p_usina uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_caiu boolean; v_estado text;
begin
  select q.caiu into v_caiu from queda_geracao(p_usina) q;
  select e.estado into v_estado from usina_estado(p_usina) e;
  if v_estado = 'recém-ligada' then
    return json_build_object('erro','usina recem-ligada — ainda em periodo de carencia');
  end if;
  if not coalesce(v_caiu,false) then return json_build_object('erro','esta usina nao esta em queda'); end if;
  if v_estado <> 'normal' then
    return json_build_object('erro','usina em '||v_estado||' — nao e caso de queda');
  end if;
  select json_build_object(
    'cliente', split_part(c.nome,' ',1), 'apelido', u.apelido, 'obra_id', o.id,
    'queda_pct', round((1 - q.razao_recente)*100), 'dias_observados', q.dias_bons,
    'exemplos', (select coalesce(string_agg(left(coalesce(m.transcricao,m.texto),200), E'\n---\n'),'')
                 from (select transcricao, texto from mensagens_recebidas mr
                       where mr.obra_id=o.id and mr.da_equipe
                         and length(coalesce(mr.transcricao,mr.texto))>25
                       order by mr.recebida_em desc limit 4) m)
  ) into v
  from usinas u join clientes c on c.id=u.cliente_id
  join obra_usina ou on ou.usina_id=u.id and ou.saiu_em is null
  join obras o on o.id=ou.obra_id, lateral queda_geracao(u.id) q
  where u.id=p_usina order by ou.principal desc limit 1;
  return v;
end $function$;

-- regua_fila(limite) — o que sai hoje às 17h. Respeita optout_em e só solta
-- modelo que precisa de aprovação depois de aprovado.

CREATE OR REPLACE FUNCTION public.regua_fila(p_limite integer DEFAULT 50)
 RETURNS TABLE(id bigint, obra_id uuid, cliente text, grupo text, modelo text, nome_modelo text, texto text, bloqueio text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.obra_id, o.cliente, o.whatsapp_grupo_id,
         c.modelo, m.nome,
         coalesce(nullif(c.texto_custom,''), public.regua_texto(c.obra_id, c.modelo)),
         public.regua_bloqueio(c.obra_id, c.modelo)
  from regua_contatos c
  join obras o on o.id = c.obra_id
  join regua_modelos m on m.codigo = c.modelo
  where c.status = 'pendente' and o.whatsapp_grupo_id not like 'http%'
    and o.optout_em is null
    and coalesce(c.adiado_para, c.data_programada) <= current_date
    and c.data_limite >= current_date
    and (coalesce(m.precisa_aprovacao,false) = false
         or coalesce(c.status_aprovacao,'') = 'aprovada')
    and not (m.texto = '{texto_custom}' and coalesce(c.texto_custom,'') = '')
    and coalesce(nullif(c.texto_custom,''), public.regua_texto(c.obra_id, c.modelo))
        not like '%{texto_custom}%'
  order by c.data_programada
  limit p_limite;
$function$;

-- regua_resumo_dia — o que a Lívia recebe às 11h: esperando, sai hoje,
-- vence amanhã.

CREATE OR REPLACE FUNCTION public.regua_resumo_dia()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'esperando', (
      select coalesce(json_agg(json_build_object(
               'cliente', split_part(o.cliente,' ',1),
               'contrato', o.contrato,
               'assunto', coalesce(m.nome, rc.modelo),
               'dias_parada', (current_date - rc.data_programada)
             ) order by rc.data_programada), '[]'::json)
      from regua_contatos rc
      join obras o on o.id=rc.obra_id
      left join regua_modelos m on m.codigo=rc.modelo
      where rc.status='pendente' and rc.status_aprovacao='aguardando'
        and o.optout_em is null and rc.data_limite >= current_date
    ),
    'sai_hoje', (
      select coalesce(json_agg(json_build_object(
               'cliente', split_part(f.cliente,' ',1),
               'assunto', f.nome_modelo) ), '[]'::json)
      from regua_fila(50) f
    ),
    'vence_amanha', (
      select count(*) from regua_contatos rc join obras o on o.id=rc.obra_id
      where rc.status='pendente' and rc.status_aprovacao='aguardando'
        and rc.data_limite = current_date + 1 and o.optout_em is null
    )
  );
$function$;


-- ---------------------------------------------------------------------
-- 6.1 QUEM PODE EXECUTAR
--
-- O padrão do Postgres é liberar execute para PUBLIC, o que no Supabase
-- inclui o anon. As funções de gatilho ficam no padrão (quem dispara é o
-- trigger). As demais são fechadas na mão, como estão em produção.
-- ---------------------------------------------------------------------

-- rotina de manutenção e conferência: ninguém pela API, só o cron/backend
revoke all on function public.casar_recebimentos(boolean)  from public, anon, authenticated;
revoke all on function public.conferir_travas()            from public, anon, authenticated;
revoke all on function public.conferir_financeiro()        from public, anon, authenticated;
revoke all on function public.conferir_saude()             from public, anon, authenticated;
revoke all on function public.get_queda_svc(uuid)          from public, anon, authenticated;

-- leitura das telas: equipe logada sim, anon não
revoke all on function public.linha_do_tempo(uuid)         from public, anon;
revoke all on function public.indicacoes_resumo(uuid)      from public, anon;
revoke all on function public.usina_estado(uuid)           from public, anon;
revoke all on function public.usina_dias(uuid, integer)    from public, anon;
revoke all on function public.rotulo_usina(text, text)     from public, anon;
revoke all on function public.regua_fila(integer)          from public, anon;
revoke all on function public.regua_resumo_dia()           from public, anon;

grant execute on function public.linha_do_tempo(uuid)      to authenticated;
grant execute on function public.indicacoes_resumo(uuid)   to authenticated;
grant execute on function public.usina_estado(uuid)        to authenticated;
grant execute on function public.usina_dias(uuid, integer) to authenticated;
grant execute on function public.rotulo_usina(text, text)  to authenticated;
grant execute on function public.regua_fila(integer)       to authenticated;
grant execute on function public.regua_resumo_dia()        to authenticated;

-- ---------------------------------------------------------------------
-- 7. TRIGGERS
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
-- 8. AUTOMAÇÕES (aparecem na tela de configuração)
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
-- 9. CRON (horários em UTC; Brasília = UTC-3)
--
-- Estava só como comentário e o resumo das 11h não subia em ambiente novo.
-- Precisa da extensão pg_cron, da pg_net e da edge function regua-resumo
-- publicada. cron.schedule substitui pelo nome, então repetir não duplica.
-- ---------------------------------------------------------------------

select cron.schedule('regua-resumo','0 14 * * 1-5', $cron$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/regua-resumo',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('token',(select valor from config where chave='cron_token')),
    timeout_milliseconds := 60000);
$cron$);

-- ---------------------------------------------------------------------
-- 10. CARGA ÚNICA (executada em 12/09/2026 — não repetir)
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

-- ---------------------------------------------------------------------
-- 11. O QUE AINDA NÃO ESTÁ AQUI
-- ---------------------------------------------------------------------
-- Para este arquivo levantar o ambiente do zero ainda falta:
--
-- 1. A publicação da edge function regua-resumo. O fonte agora está em
--    supabase/functions/regua-resumo/, mas a seção 9 agenda uma chamada
--    para uma função que só existe depois de:
--      supabase functions deploy regua-resumo --no-verify-jwt
--    Ela também precisa das variáveis de ambiente da Z-API e da chave
--    cron_token em config — ver o README da pasta.
-- 2. Tudo que é anterior a 12/09/2026. As funções da seção 6 dependem de
--    conferir_saude_base(), queda_geracao(), regua_texto(), regua_bloqueio(),
--    v_indice_dia e das tabelas de obra, financeiro e pós-venda.
-- 3. O registro em supabase_migrations.schema_migrations. A sessão de 12/09
--    foi aplicada direto no banco; a última migração registrada é
--    20260901142357 servicos_avulsos. Quem olhar só o histórico do Supabase
--    não vê nada do que está neste arquivo.
