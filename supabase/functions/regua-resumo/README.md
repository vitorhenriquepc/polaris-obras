# regua-resumo

O resumo que a Lívia recebe às 11h em dia útil: o que está esperando a
autorização dela, o que sai às 17h sozinho e o que perde a validade amanhã.
Se não há nada a dizer, não manda nada — aviso que sempre chega vira ruído.

Fonte baixado do projeto `dakubhcgohiwzyqiegqf` em 12/09/2026 (versão 1).
Estava publicado e ativo sem estar no repositório.

## Como é chamado

Pelo cron `regua-resumo`, `0 14 * * 1-5` em UTC (11h de Brasília), agendado na
seção 9 de `migrations/2026-09-12_travas_conciliacao_linha_do_tempo.sql`.

Não usa JWT (`verify_jwt = false`). Quem autoriza é o `token` no corpo do
POST, conferido contra a chave `cron_token` da tabela `config`. Ao publicar
pela CLI isso precisa ser explícito:

    supabase functions deploy regua-resumo --no-verify-jwt

## Do que depende

| Variável de ambiente | Para quê |
|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | acesso ao banco |
| `ZAPI_INSTANCE_ID` | instância POS-VENDA |
| `ZAPI_TOKEN` ou `ZAPI_INSTANCE_TOKEN` | token da instância |
| `ZAPI_CLIENT_TOKEN` | header `Client-Token` da Z-API |

Nenhum valor fica no código — são variáveis de ambiente do Supabase.

No banco: a função `regua_resumo_dia()`, as chaves `cron_token` e
`regua_resumo_ativa` em `config`, e uma linha em `equipe` com
`resp_posvenda = true` e `ativo = true`, que é para quem a mensagem vai.
Sem responsável ou sem canal, responde 500 e não manda nada.

## Corpo do POST

| Campo | Efeito |
|---|---|
| `token` | obrigatório; sem ele responde 403 |
| `simular` | devolve a mensagem pronta sem enviar |
| `forcar` | manda mesmo com `regua_resumo_ativa` desligada |

Para ver o texto de hoje sem mandar nada para ninguém, use `simular`.
