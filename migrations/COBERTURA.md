# O que está versionado e o que não está

Levantado em 12/09/2026 contra o projeto `dakubhcgohiwzyqiegqf`.

Existem **dois** históricos, e nenhum dos dois está completo:

1. `supabase_migrations.schema_migrations` no banco — 149 migrações,
   de 23/06 a 01/09/2026, todas com os comandos guardados (441 KB).
2. A pasta `migrations/` deste repositório — só a sessão de 12/09.

## Cobertura dos objetos de `public`

| | funções | tabelas | views |
|---|---:|---:|---:|
| Total no banco | 231 | 77 | 7 |
| No histórico do Supabase | 147 | 57 | 2 |
| Só no repositório (12/09) | 18 | 2 | 2 |
| **Em lugar nenhum** | **66** | **18** | **3** |

**87 objetos não existem em nenhum histórico.** Foram aplicados direto no
banco, pelo editor de SQL ou pelo painel.

Como foi medido: o nome de cada objeto foi procurado dentro do texto de
todos os comandos guardados em `schema_migrations`. É uma aproximação por
nome — pode dar falso positivo (nome citado sem ser criado ali), nunca
falso negativo. Ou seja: 87 é o piso, não o teto.

## Os 87 órfãos

**Tabelas (18)** — `usinas`, `usina_dia`, `usina_geracao`, `usina_leitura`, `usina_marco`, `usina_monitoramento`, `usina_previsao`,
`usina_status`, `obra_usina`, `clima_dia`, `obra_relatorios`, `automacoes`,
`conferencia_log`, `mensagem_aprovacao`, `mensagem_mascarada`,
`tarifa_historico`, e duas de backup: `backup_valores_20260910` e
`nps_backup_20260902`.

**Views (3)** — `v_indice_dia`, `v_obras_painel`, `v_usinas_monitoradas`.

**Funções (66)** — entre elas `queda_geracao`, `usina_retorno`, `usina_meses`,
`conferir_saude_base`, `manutencao_usinas`, `importar_extrato`,
`classificar_movimento`, `receber_do_extrato`, `lancar_movimentos`,
`regua_decidir`, `regua_texto_item`, `espelha_preco_na_ficha`,
`valida_obra_usina`, `calibrar_tarifa`, `calibrar_fatores`.

Para listar de novo:

```sql
with hist as (
  select string_agg(s, E'\n') as txt
  from supabase_migrations.schema_migrations m, unnest(m.statements) s)
select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace, hist h
where n.nspname='public' and p.prokind in ('f','p') and position(p.proname in h.txt)=0
order by 1;
```

O monitoramento inteiro — as 56 usinas, a geração diária, o clima, os marcos
de retorno — está fora dos dois históricos. É a parte do sistema que só existe
dentro do banco.

## Por que a sessão de 12/09 NÃO foi registrada em `schema_migrations`

Foi uma decisão, não esquecimento.

Inserir a linha faria o histórico do Supabase apontar 12/09 como última
migração aplicada. Ele passaria de *visivelmente atrasado* para
*silenciosamente errado*: pareceria em dia enquanto 87 objetos continuam sem
registro nenhum. Quem confiasse nele para um `supabase db reset`, para criar
um branch ou para ler um `db diff` receberia um banco quebrado — e confiaria
mais nele do que confia hoje.

Enquanto o histórico está claramente parado em 01/09, ninguém se engana.

A ordem que faz sentido:

1. Exportar as 66 funções órfãs. É mecânico e confere por md5, igual ao que
   foi feito com as 19 da sessão de 12/09. É onde mora a regra de negócio e
   é o que seria mais caro perder.
2. Exportar as 18 tabelas e 3 views. Precisa de `supabase db dump` numa
   máquina com a CLI — reconstruir DDL de tabela pelo catálogo, na mão,
   perde default, constraint, índice, RLS e grant.
3. Só quando o repositório conseguir levantar o esquema, realinhar o
   histórico do Supabase — e aí pela CLI (`supabase migration repair`),
   não com INSERT na mão.

## Detalhe que confirma a leitura

Das 19 funções da sessão de 12/09, exatamente uma aparece no histórico do
Supabase: `regua_fila`, criada em `20260807025018 regua_fila_e_regras` e
alterada em 12/09 para respeitar `optout_em`. Bate com o que o arquivo da
migração diz — ela foi alterada, não criada.

Já `sincroniza_valor`, que o arquivo também marca como "JÁ EXISTIA", não está
em histórico nenhum. Existia mesmo, mas nunca passou por migração.

## Uma divergência no CLAUDE.md

A seção 4 do `CLAUDE.md` lista `usina_mes` entre as tabelas do pós-venda.
Essa tabela não existe no banco — não há `usina_mes`, nem tabela nem view.
A tabela de geração mensal se chama `usina_geracao` (5 colunas).

Não mexi no `CLAUDE.md`: corrigir o mapa do projeto é decisão do Vitor, e
pode ser que o nome certo seja o da tabela, não o do documento.
