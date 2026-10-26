# esquema/ — retrato do que só existe dentro do banco

Isto **não é migração**. É o estado atual dos objetos que não estão em
histórico nenhum — nem em `supabase_migrations.schema_migrations`, nem na
pasta `migrations/` deste repositório. O levantamento que explica o porquê
está em `migrations/COBERTURA.md`.

Não dá para rodar esta pasta de cima a baixo e levantar o banco: falta a
ordem em que as coisas foram criadas (o Postgres não guarda), e o resto do
esquema está em `migrations/` e `supabase/migrations/`.

Para que serve, então: a regra de negócio deixa de existir em um lugar só.
Se o projeto do Supabase sumir, o que está aqui se lê e se recria.

## Conferir se ainda bate com o banco

`conferir.sql` (só leitura) devolve, para as três pastas, uma linha por
arquivo no formato do `MANIFESTO.md5`: o md5 do texto que o banco gera
**hoje**. Do lado do repositório:

```
cd esquema/funcoes && md5sum -c MANIFESTO.md5      # e o mesmo em tabelas/ e views/
```

Linha diferente quer dizer que o objeto mudou no banco e o arquivo ficou para
trás; linha que só existe no manifesto, que o objeto foi apagado. O próprio
`conferir.sql` diz como trazer o texto novo byte a byte (em base64), sem
copiar à mão.

⚠️ **Migração que mexe num objeto daqui tem de atualizar o arquivo junto.**
Quem deixou o espelho para trás não foi alguém mexendo direto no banco: foram
migrações do próprio repositório. Em 26/10 havia 8 funções e 5 tabelas
diferentes do banco — entre elas `calibrar_fatores` e `manutencao_usinas`
(saúde da usina, 26/09), `pista_de_causa` e `get_marco_svc` (Isabela, 15/10),
as colunas novas de `usinas` e `usina_geracao`, e o "delete só admin" de
`usinas`, `obra_usina`, `obra_relatorios` e `usina_monitoramento`, aplicado
em 12/09 depois da primeira foto.

## funcoes/

Uma função por arquivo, exportada com `pg_get_functiondef`. Cada arquivo é
**byte a byte igual** ao que está no banco — sem reformatação; por isso o
mesmo md5 sai do banco.

`_permissoes.sql` guarda quem pode executar cada função — o
`pg_get_functiondef` não traz isso. Leia o aviso no fim dele.

`rls_auto_enable.sql` é a função do **event trigger** `ensure_rls`, que liga
a RLS em toda tabela nova do `public`. O event trigger não tem arquivo
próprio; para recriar:

```sql
create event trigger ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();
```

## tabelas/ e views/

Geradas a partir do catálogo do Postgres, não do `pg_dump` (não há CLI nem
conexão direta nesta máquina). O gerador da primeira foto (12/09/2026) não
foi guardado; o de `conferir.sql` foi reconstruído em 26/10/2026 e reproduz
byte a byte os arquivos de 12/09 das 12 tabelas e 3 views que não tinham
mudado. As views saem de `pg_get_viewdef(oid, true)`, a forma "bonita": sem o
`true` o Postgres devolve outros parênteses e o md5 não bate.

O que cada arquivo carrega: colunas com tipo, default e `not null`;
constraints via `pg_get_constraintdef`; índices via `pg_get_indexdef`;
sequences com `owned by`; `enable row level security`; e as policies.

**O que não carrega, e é bom saber:**

- **Grants.** As tabelas daqui estão todas no padrão do Supabase — os sete
  privilégios para `anon`, `authenticated` e `service_role` — que o próprio
  Supabase aplica por default privilege. Quem segura a escrita é a RLS.
  Se alguma tabela sair desse padrão, o arquivo dela não vai refletir isso.
- **Ordem de criação.** O Postgres não guarda. Rodar a pasta de cima a baixo
  não funciona: há FK entre as tabelas e para `obras` e `clientes`.
- **Triggers.** Ficam com as funções, não com as tabelas.
- **Um índice sem `if not exists`:** `uq_ou_principal`, em `obra_usina`, é
  `CREATE UNIQUE INDEX` e ficou verbatim. Rodar duas vezes dá erro nele.

## Histórico

- **12/09/2026** — primeira foto: 66 funções, 18 tabelas e 3 views.
- **26/10/2026** — atualizado. Vieram do banco 8 funções e 5 tabelas que
  tinham mudado. Entraram a tabela `clientes` (criada fora de qualquer
  migração, tinha ficado fora da primeira foto) e a `rls_auto_enable`. Saíram
  as funções `zz_lista`, `zz_brindes`, `zz_det` e `_t_pend` e a tabela
  `usina_status`, apagadas no banco em 12/09 — o texto delas está no commit
  `e5a6232`. As views não tinham mudado. Conferido por md5: as 63 funções, as
  18 tabelas e as 3 views batem byte a byte com o banco.
