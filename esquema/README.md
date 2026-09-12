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
