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

1. ~~Exportar as 66 funções órfãs.~~ **Feito** — estão em `esquema/funcoes/`,
   uma por arquivo, conferidas por md5 uma a uma contra o banco.
2. ~~Exportar as 18 tabelas e 3 views.~~ **Feito** — estão em
   `esquema/tabelas/` e `esquema/views/`, geradas do catálogo e conferidas
   por md5. Não precisou de `pg_dump`: o gerador monta o DDL dentro do
   próprio banco. O que ele não cobre está listado no `esquema/README.md`.
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

## Achado de segurança (12/09/2026)

Ao levantar as permissões das 66 funções apareceram **três que o `anon` pode
executar, são `security definer` e não conferem permissão nenhuma por dentro**.
`security definer` passa por cima da RLS, e `anon` é o papel de quem não fez
login — a chave dele está no código das páginas, à vista de qualquer um.

| Função | O que faz |
|---|---|
| `_t_pend(uuid)` | devolve o extrato bancário: até 400 movimentos com valor, memo, banco e conta |
| `zz_det(uuid)` | devolve dados da usina com nome do cliente e contrato |
| `manutencao_usinas()` | **escreve**: cria previsões e altera `fator_local` das usinas |

Os nomes (`_t`, `zz_`) sugerem função de teste que ficou para trás. Nenhuma
página do repositório chama qualquer uma delas — conferido por busca nos HTML.

**Corrigido no mesmo dia**, com o Vitor de acordo:
`migrations/2026-09-12_revoga_anon_funcoes_expostas.sql`. Depois do revoke o
`anon` não executa nenhuma das três; `authenticated`, `service_role` e
`postgres` têm grant próprio e seguem iguais.

Uma correção ao que ficou escrito antes: **`manutencao_usinas` não é sobra de
teste.** É o cron `manutencao-usinas` (jobid 30, `0 12 * * *`), a automação
das 9h. Roda como `postgres`, então o revoke não a atinge — mas apagar
quebraria a manutenção diária. `_t_pend` e `zz_det` é que têm cara de
rascunho; ficaram no ar, só fechadas.

A varredura geral feita junto encontrou mais 10 funções `security definer`
que o `anon` executa, e **nenhuma é buraco**: 6 são fluxo público protegido
por slug + token da obra, 2 são o relatório público por slug (que é o que o
`relatorio.html` serve de propósito) e 2 têm guarda própria
(`pode_ver_posvenda`, `pode_agir_posvenda`). Fica registrado para não se
refazer essa investigação.

## Recontagem em 12/09/2026, depois do export

| | funções | tabelas | views |
|---|---:|---:|---:|
| Total no banco | 231 | 77 | 7 |
| No histórico do Supabase | 151 | 58 | 2 |
| Coberto pelo repositório | 80 | 19 | 5 |
| **Em lugar nenhum** | **0** | **0** | **0** |

Os 315 objetos de `public` estão todos em algum lugar. Continua valendo que
o repositório **não levanta o banco do zero**: falta a ordem de criação, que
o Postgres não guarda.

## Auditoria do banco, 12/09/2026

`conferir_saude()` — a conferência das 7h30 — devolveu seis achados, todos
de dado e não de estrutura:

| Achado | Onde olhar |
|---|---|
| 40 fichas financeiras incompletas | falta valor do projeto ou distância em km |
| 15 movimentos de extrato sem classificar | conciliar no financeiro |
| 13 fichas com parcelas que não fecham com o preço | abrir o financeiro |
| 5 cards de obra incompletos | contratos 4349, 4420, 4483, 4563, 4808 |
| 1 parcela recebida sem extrato | contrato 4657 |
| 1 obra finalizada sem usina | — |

Os 5 cards batem com a lista do `CLAUDE.md`. As 40 fichas e as 13 com
parcela furada são bem mais do que o `CLAUDE.md` sugere — vale olhar antes
de confiar em margem.

O linter do Supabase deu 177 achados em 6 regras. Tratados:

- `function_search_path_mutable` (2) — **corrigido**, ver
  `2026-09-12_fixa_search_path_duas_funcoes.sql`
- `anon_security_definer_function_executable` — caiu de 16 para 13 com o
  revoke; os 13 restantes foram auditados um a um e nenhum é buraco
- `rls_enabled_no_policy` (1) — `usina_status`, ver abaixo

Não tratados, de propósito:

- `auth_leaked_password_protection` — é a pendência que já está no
  `CLAUDE.md`. Não se liga por SQL: é Authentication → Policies no painel
  do Supabase. Só o Vitor tem essa tela.
- `extension_in_public` — `pg_net` no schema `public`. Mover quebraria todos
  os crons que chamam `net.http_post`. Risco alto, ganho baixo.
- `authenticated_security_definer_function_executable` (159) — é o desenho
  do sistema: as telas falam com o banco por RPC `security definer`. Mudar
  isso é reescrever o modelo de acesso, não corrigir um bug.

## `usina_status` está morta

Tabela com RLS ligada e **zero policies** — ou seja, inalcançável pela API.
Tem 0 linhas, nenhuma função a menciona e nenhum cron a usa. Investiguei a
edge function de nome parecido: `usina-status` escreve em `usina_leitura` e
em `usinas`, nunca nela.

Foi substituída por `usinas.status_atual` + `usina_leitura`. Está versionada
em `esquema/tabelas/usina_status.sql` caso alguém precise dela de volta.
Não apaguei: é decisão do Vitor, e depois do caso `manutencao_usinas` ficou
claro que nome parecido não é prova de nada.

---

## A superfície `anon`, medida de verdade (12/09/2026, depois das revogações)

Rodei o linter de segurança do Supabase depois de revogar as três funções
abertas. Resultado, por regra:

| Nível | Regra | Quantas |
|---|---|---|
| WARN | `authenticated_security_definer_function_executable` | 159 |
| WARN | `anon_security_definer_function_executable` | 13 |
| WARN | `extension_in_public` (`pg_net`) | 1 |
| WARN | `auth_leaked_password_protection` | 1 |
| INFO | `rls_enabled_no_policy` (`usina_status`) | 1 |

As 159 do `authenticated` são o sistema inteiro: a tela é gente logada
chamando RPC, e cada função confere permissão por dentro. Não é achado.

**As 13 do `anon` eu conferi uma por uma — chamando de fato como `anon`, não
lendo o código.** Isso importa: minha primeira leitura, por regex, deu cinco
delas como "sem guarda", e estava errada. `get_ficha_cliente` usa
`pode_ver_posvenda()`, `indicacao_status` usa `pode_agir_posvenda()`,
`zz_lista` e `zz_brindes` usam `meu_nivel()` — nomes que minha busca não
cobria. Teste é medição; regex é palpite.

O que cada uma devolve para o `anon`:

| Função | Como se defende | Resposta ao `anon` |
|---|---|---|
| `get_ficha_cliente` | `pode_ver_posvenda()` | `Sem permissão para ver este cliente` |
| `indicacao_status` | `pode_agir_posvenda()` | `Sem permissão` (antes de qualquer `update`) |
| `zz_lista`, `zz_brindes` | `meu_nivel() = 'nenhum'` | `null` |
| `get_optin_status` | idem | `null` |
| `get_agenda` | token | `null` com token errado |
| `get_nps`, `get_obra_instalador` | slug + token | `null` com par errado |
| `salvar_nps`, `declarar_avaliacao_google` | slug + token | `Link inválido` |
| `salvar_brinde` | slug + token | `Link inválido` — a checagem do par vem antes do `update`; o `Brinde inválido` que aparece primeiro é só validação de entrada |
| `get_obra_publica`, `get_relatorio_publico` | o slug **é** o segredo | `null` para slug inexistente |

Nenhuma vaza. As duas últimas são públicas de propósito: é o que a
`relatorio.html` serve para o cliente.

### O que o linter não pega

`config` **não** aparece em `rls_enabled_no_policy`, porque ela tem policy —
de leitura. Não tem de escrita. O linter só acusa tabela com *zero* policy,
então o bug que fazia o interruptor da régua mentir passou invisível por ele.
Vale a regra: RLS ligada com policy só de leitura devolve **sucesso sem erro**
no `update`, e isso nenhum alerta automático conta.

### O que deixei como está, e por quê

- **`pg_net` no schema `public`** — mover quebra as chamadas `net.http_post()`
  de todos os cron jobs. Risco alto, ganho baixo.
- **Proteção de senha vazada** — é chave de dashboard, não sai por SQL.
- **`usina_status`** — RLS ligada e zero policy: ninguém lê, ninguém escreve.
  Está morta e inofensiva. Apagar é decisão do Vitor, não minha.

---

## Linter de performance (12/09/2026) — e o que dele não é performance

| Regra | Quantas | Veredito |
|---|---|---|
| `multiple_permissive_policies` | 54 | **uma parte é permissão, não performance — ver abaixo** |
| `unindexed_foreign_keys` | 33 | irrelevante nesta escala (dezenas a milhares de linhas) |
| `unused_index` | 7 | índices criados "por via das dúvidas"; deixar |
| `no_primary_key` | 2 | `nps_backup_20260902`, `backup_valores_20260910` — são backups |
| `duplicate_index` | 1 | `geracao`: `geracao_obra_id_referencia_key` e `uq_geracao_obra_dia` são idênticos |
| `auth_rls_initplan` | 1 | `usuarios_autorizados.ua_admin_del` reavalia por linha — a tabela tem 3 linhas |

### O achado que não é performance: o delete "só admin" não é só admin

Cinco tabelas — `clientes`, `obra_relatorios`, `obra_usina`, `usinas`,
`usina_monitoramento` — têm duas policies permissivas:

```
<tabela>_auth   ALL      using (is_autorizado())
<tabela>_del    DELETE   using (is_admin())
```

Policy permissiva **soma**, não subtrai. Num delete o Postgres avalia as duas
e aceita se qualquer uma passar: `is_autorizado() OR is_admin()`. A policy
`_del` não restringe nada — ela alarga.

**Ainda não estourou** porque as três pessoas em `usuarios_autorizados` são
todas `is_admin = true`: os dois lados do OR dão o mesmo resultado. No dia em
que entrar um vendedor não-admin, ele passa a poder apagar cliente, usina,
vínculo obra-usina e relatório de obra. Isso bate de frente com a regra 3.6
do CLAUDE.md (não apagar histórico).

A correção está escrita em `migrations/PROPOSTA_2026-09-12_delete_so_admin.sql`
e **não foi aplicada** — mexer em quem pode apagar é decisão do Vitor.
Aplicar hoje não muda nada para ninguém; o ganho é no dia em que mudar.

### E o `anon`? Não alcança essas tabelas

As policies são `to public`, e `public` inclui `anon` — foi por isso que o
linter listou `anon` nas linhas de DELETE. Testei: como `anon`, a consulta
morre antes, com `permission denied for function is_autorizado`. O `anon` não
tem EXECUTE na função que a policy chama, então nem chega a avaliar. Sem
buraco.

### Um detalhe para o Vitor conferir

`contato@polarisenergiasolar.com` (Ana Claudia) está com `is_admin = true` e
`nivel = 'financeiro'`. As outras duas contas admin têm `nivel = 'admin'`.
Pode ser proposital, pode ser engano — não mexi.
