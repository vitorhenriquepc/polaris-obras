-- Confere o espelho esquema/ contra o banco. Só leitura: roda no SQL editor do
-- Supabase (ou pelo MCP) sem mexer em nada.
--
-- Cada linha sai no formato do MANIFESTO.md5 da pasta ("md5  arquivo"). Para
-- conferir, compare com o manifesto (ex.: cole o resultado de uma pasta num
-- arquivo e rode `diff` contra esquema/<pasta>/MANIFESTO.md5). Linha diferente
-- = o objeto mudou no banco e o arquivo ficou para trás; linha que só existe
-- no manifesto = o objeto foi apagado no banco.
--
-- Para trazer o arquivo novo BYTE A BYTE, troque o select final por
--   select encode(convert_to(ddl, 'UTF8'), 'base64') from espelho
--    where pasta = '...' and arquivo = '...';
-- e decodifique com `base64 -d`. Copiar o texto do resultado na mão erra fácil
-- (as quebras de linha e as aspas vêm escapadas).
--
-- funcoes/: o texto é o próprio pg_get_functiondef.
-- tabelas/ e views/: o gerador abaixo monta o DDL no formato dos arquivos de
-- 12/09/2026. Ele foi reconstruído em 26/10/2026 (o original não tinha sido
-- guardado) e reproduziu byte a byte as 12 tabelas que não tinham mudado desde
-- 12/09 — sequência, índice, RLS e policy incluídos. O que ele não carrega
-- está no README.md.
--
-- Objeto novo no espelho: acrescente o nome na lista da pasta, aqui embaixo.

with
fn as (
  select 'funcoes'::text pasta, p.proname || '.sql' arquivo, pg_get_functiondef(p.oid) ddl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f','p')
    and p.proname in ('auto_lida','buscar_duplicata','calibrar_fatores','calibrar_tarifa','chave_nome',
      'classificar_lote','classificar_movimento','clientes_esperando','conferir_saude_base','decidir_mensagem',
      'descartar_movimento','desfazer_lancamento','dias_anormais','espelha_preco_na_ficha','fracao_polaris',
      'get_aprovacoes','get_automacoes','get_cliente_ficha','get_clientes_acervo','get_contas_extrato',
      'get_extrato_pendentes','get_marco_svc','get_posvenda_mensagens','get_posvenda_usinas',
      'get_regua_aprovacoes','get_relatorios_painel','get_usina_causa','get_usina_detalhe',
      'get_usina_detalhe_svc','importar_extrato','lancar_avulso','lancar_movimentos','ligar_automacao',
      'manutencao_usinas','marcar_todas_lidas','marcos_novos','mascara_credencial','mensagem_sem_acao',
      'obras_aguardando_ligacao','painel_avulsos','parcelas_abertas','pista_de_causa','pontua_nome',
      'previsao_estimada','queda_geracao','receber_do_extrato','recorde_do_dia','registrar_google_enviado',
      'regua_decidir','regua_texto_item','rls_auto_enable','salvar_causa','salvar_fator','salvar_previsao',
      'salvar_relatorio_arquivo','salvar_relatorio_link','tarifa_status','tokens_iguais',
      'trg_marcar_aceite_pedido','trg_valida_lancamento','usina_meses','usina_retorno','valida_obra_usina')
),
t as (
  select c.oid, c.relname::text nome, c.relrowsecurity rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('automacoes','backup_valores_20260910','clientes','clima_dia','conferencia_log','mensagem_aprovacao',
      'mensagem_mascarada','nps_backup_20260902','obra_relatorios','obra_usina','tarifa_historico','usina_dia',
      'usina_geracao','usina_leitura','usina_marco','usina_monitoramento','usina_previsao','usinas')
),
seqs as (  -- sequências da tabela (owned by)
  select t.oid tab, s.relname::text seq, a.attname::text col
  from t join pg_depend d on d.refobjid = t.oid and d.deptype = 'a' and d.classid = 'pg_class'::regclass
  join pg_class s on s.oid = d.objid and s.relkind = 'S'
  join pg_attribute a on a.attrelid = t.oid and a.attnum = d.refobjsubid
),
tab as (
  select 'tabelas'::text pasta, t.nome || '.sql' arquivo,
    coalesce((select string_agg('create sequence if not exists public.' || seq || E';\n\n', '' order by seq)
              from seqs where tab = t.oid), '')
    || 'create table if not exists public.' || t.nome || E' (\n'
    -- colunas na ordem da tabela; depois as constraints: pk, unique, check, fk (cada grupo por nome)
    || (select string_agg(linha, E',\n' order by ordem, k1, k2) from (
          select 1 ordem, a.attnum::int k1, ''::text k2,
                 '  ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
                 || coalesce(' default ' || pg_get_expr(ad.adbin, ad.adrelid), '')
                 || case when a.attnotnull then ' not null' else '' end linha
          from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
          where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
          union all
          select 2, array_position(array['p','u','c','f','x'], co.contype::text), co.conname::text,
                 '  constraint ' || quote_ident(co.conname) || ' ' || pg_get_constraintdef(co.oid)
          from pg_constraint co where co.conrelid = t.oid and co.contype in ('p','u','c','f','x')) l)
    || E'\n);\n'
    || coalesce((select string_agg(E'\nalter sequence public.' || seq || ' owned by public.' || t.nome || '.' || col || E';\n', '' order by seq)
                 from seqs where tab = t.oid), '')
    -- índices que não são de constraint; o UNIQUE fica como o Postgres escreve (sem "if not exists")
    || coalesce(E'\n' || (select string_agg(replace(pg_get_indexdef(ix.indexrelid), 'CREATE INDEX ', 'create index if not exists ') || E';\n', '' order by ic.relname)
          from pg_index ix join pg_class ic on ic.oid = ix.indexrelid
          where ix.indrelid = t.oid and not exists (select 1 from pg_constraint co where co.conindid = ix.indexrelid)), '')
    || case when t.rls then E'\nalter table public.' || t.nome || E' enable row level security;\n' else '' end
    || coalesce(E'\n' || (select string_agg('create policy ' || quote_ident(p.policyname) || ' on public.' || t.nome
          || case when p.permissive = 'RESTRICTIVE' then ' as restrictive' else '' end
          || ' for ' || lower(p.cmd) || ' to ' || array_to_string(p.roles, ', ')
          || coalesce(E'\n  using (' || p.qual || ')', '') || coalesce(E'\n  with check (' || p.with_check || ')', '')
          || E';\n', '' order by p.policyname)
          from pg_policies p where p.schemaname = 'public' and p.tablename = t.nome), '') ddl
  from t
),
vw as (
  select 'views'::text pasta, c.relname || '.sql' arquivo,
    'create or replace view public.' || c.relname || E' as\n' || pg_get_viewdef(c.oid, true)
    || coalesce(E'\n\nalter view public.' || c.relname || ' set (' || replace(array_to_string(c.reloptions, ', '), '=', ' = ') || ');', '')
    || E'\n\ngrant select on public.' || c.relname || E' to authenticated;\n' ddl
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
    and c.relname in ('v_indice_dia','v_obras_painel','v_usinas_monitoradas')
),
espelho as (
  select * from fn union all select * from tab union all select * from vw
)
select pasta, md5(ddl) || '  ' || arquivo as linha
from espelho
order by pasta, arquivo;
