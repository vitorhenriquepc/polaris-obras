# solarview-usinas

Ferramenta de diagnóstico do portfólio do SolarView. **Não é o vínculo
automático** — esse é o `solarview-vincular`, que roda no cron das 10h40.
Esta aqui só lê e cruza; a única ação que grava é `vincular`, que mexe no
campo legado `obras.solarview_id`.

`verify_jwt` é **false** e a autorização é pelo `cron_token` no corpo.
Ao republicar, passe `verify_jwt: false` explicitamente — o padrão da
ferramenta de deploy é `true`, e isso quebraria a chamada.

## Ações

| `acao` | O que faz |
|---|---|
| `testar` (padrão) | só autentica e diz se o token foi reaproveitado |
| `listar` | conta as usinas e agrupa por status |
| `listar` + `busca` | **procura no portfólio por nome** |
| `vincular` | grava `obras.solarview_id` (legado) |

## A busca, e por que ela existe

Acrescentada em 15/09/2026. Antes, `listar` devolvia só uma amostra de 5 de
**611** usinas, e não havia como responder a pergunta que mais importa quando
uma obra não casa: *"a usina dessa cliente existe no SolarView?"*

Foi exatamente o caso da MARIA APARECIDA DE HOLANDA GOMES (contrato 4767). A
busca mostrou que a usina dela **existia**, com o nome completo e correto — o
que mudou o diagnóstico de "não está cadastrada" para "apareceu no portfólio
depois da última rodada do casador".

```json
{ "token": "...", "acao": "listar", "busca": "MARIA APARECIDA HOLANDA GOMES 4767" }
```

Procura por qualquer palavra com mais de 2 letras, sem acento e sem
maiúsculas. Devolve até 40 achados com nome, kWp, cidade e status.

## O que a busca ensinou sobre o portfólio

São **611 usinas**, não as 56 da Polaris — a conta é um portfólio grande, com
muitos clientes. É por isso que o casamento por nome é conservador: buscar
"Maria" traz dezenas. O `solarview-vincular` só liga com o contrato no nome,
ou com 3+ palavras iguais incluindo sobrenome. Ele prefere não ligar a ligar
errado, e isso é de propósito — a regra 3.2 do CLAUDE.md lembra que vínculo
no cliente errado já aconteceu uma vez.

**Cadastre no SolarView com o número do contrato no nome** e o vínculo sai
sozinho na rodada seguinte.
