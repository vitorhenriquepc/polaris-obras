# esquema/ — retrato do que só existe dentro do banco

Isto **não é migração**. É o estado atual dos objetos que não estão em
histórico nenhum — nem em `supabase_migrations.schema_migrations`, nem na
pasta `migrations/` deste repositório. O levantamento que explica o porquê
está em `migrations/COBERTURA.md`.

Não dá para rodar esta pasta de cima a baixo e levantar o banco: falta a
ordem em que as coisas foram criadas (o Postgres não guarda) e faltam as 18
tabelas e 3 views das quais estas funções dependem.

Para que serve, então: a regra de negócio deixa de existir em um lugar só.
Se o projeto do Supabase sumir, o que está aqui se lê e se recria.

## funcoes/

Uma função por arquivo, exportada com `pg_get_functiondef`. Cada arquivo é
**byte a byte igual** ao que está no banco — sem reformatação.

`MANIFESTO.md5` tem o md5 de cada arquivo. Como o arquivo é idêntico à saída
de `pg_get_functiondef`, o mesmo md5 sai do banco. Para conferir se o
repositório ainda bate com produção:

```sql
select p.proname || '.sql' as arquivo, md5(pg_get_functiondef(p.oid)) as md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind in ('f','p')
order by 1;
```

e do lado do repositório:

```
cd esquema/funcoes && md5sum -c MANIFESTO.md5
```

Divergência quer dizer que alguém mexeu na função direto no banco e o
repositório ficou para trás.

`_permissoes.sql` guarda quem pode executar cada função — o
`pg_get_functiondef` não traz isso. Leia o aviso no fim dele.

## O que ainda não está aqui

As 18 tabelas e 3 views órfãs. Precisam de `supabase db dump` numa máquina
com a CLI: reconstruir DDL de tabela pelo catálogo, na mão, perde default,
constraint, índice, RLS e grant, e não há como conferir por checksum.

## tabelas/ e views/

Geradas a partir do catálogo do Postgres em 12/09/2026, não do `pg_dump`
(não há CLI nem conexão direta nesta máquina). Cada arquivo foi conferido
por md5 contra a mesma geração feita dentro do banco.

O que cada arquivo carrega: colunas com tipo, default e `not null`;
constraints via `pg_get_constraintdef`; índices via `pg_indexes.indexdef`;
sequences com `owned by`; `enable row level security`; e as policies.

**O que não carrega, e é bom saber:**

- **Grants.** As 18 tabelas estão todas no padrão do Supabase — os sete
  privilégios para `anon`, `authenticated` e `service_role` — que o próprio
  Supabase aplica por default privilege. Quem segura a escrita é a RLS.
  Se alguma tabela sair desse padrão, o arquivo dela não vai refletir isso.
- **Ordem de criação.** O Postgres não guarda. Rodar a pasta de cima a baixo
  não funciona: há FK entre as tabelas e para `obras` e `clientes`.
- **Triggers.** Ficam com as funções, não com as tabelas.
- **Um índice sem `if not exists`:** `uq_ou_principal`, em `obra_usina`, é
  `CREATE UNIQUE INDEX` e ficou verbatim. Rodar duas vezes dá erro nele.
