# CLAUDE.md — SaaS Polaris Energia Solar

Leia este arquivo inteiro antes de qualquer tarefa.

---

## 1. O que é

Sistema interno da **Polaris Energia Solar** (Araçatuba/SP), empresa de
instalação de energia solar com ~20 pessoas. Cobre o ciclo todo:

1. **Obras** — kanban de 8 etapas, da venda à usina ligada
2. **Financeiro** — orçado x realizado por obra, conciliação bancária, DRE
3. **Pós-venda** — monitoramento de 56 usinas e régua de mensagens no WhatsApp
4. **Indicações** — programa de indicação de clientes

Responsável pelo pós-venda: **Lívia de Paula**. Quem decide: **Vitor**.

---

## 2. Onde as coisas vivem

| O quê | Onde |
|---|---|
| Banco | Supabase, projeto `dakubhcgohiwzyqiegqf` |
| Código | GitHub `vitorhenriquepc/polaris-obras`, branch `main` |
| Sites | `obras.polarisenergiasolar.com` |
| WhatsApp | Z-API, instância POS-VENDA |
| Monitoramento | SolarView (API) |

Páginas (HTML puro, sem framework, um arquivo cada):

- `painel.html` — kanban, card da obra, relatórios, linha do tempo
- `financeiro.html` — ficha, parcelas, extrato, DRE
- `posvenda.html` — régua, usinas, aprovações
- `relatorio.html` — relatório público da obra

---

## 3. Regras que não se quebram

### 3.1 A IA escreve o tom, nunca os números
Números vêm do banco. Existe conferência que acusa número inventado. Se
precisar de um valor, busque — nunca estime.

### 3.2 Simular antes de gravar
Toda rotina em lote tem modo `simular`. Use primeiro, mostre, só então grave.
Já evitou: vínculo de usina no cliente errado, mensagem com mês trocado,
marco de retorno inconsistente.

### 3.3 Validar sintaxe antes de publicar
Depois de editar HTML, baixe o arquivo publicado e valide o JavaScript antes
de dizer que está pronto. Já quebramos a página por escape de aspas.

### 3.4 Nunca pedir credencial pelo chat
Tokens ficam em variáveis de ambiente do Supabase ou na tabela `config`.

### 3.5 Nada sai para o cliente sem aprovação humana
Mensagem de IA entra na régua como `aguardando`. A Lívia aprova. Sai às 17h.

### 3.6 Não apagar histórico
Anotação e linha do tempo se corrigem, não se apagam.

---

## 4. Modelo de dados

### Obras
`obras` (contrato, cliente TEXTO, cliente_id, etapa_numero, trilha, valor_projeto,
distancia_km, vendedor_id, origem_lead, tipo_telhado, endereco, whatsapp_grupo_id,
optout_em) · `etapas` + `etapas_historico` · `travas_historico` ·
`obra_relatorios` · `obra_nota`

⚠️ A tela grava **`cliente` (texto)**. O `cliente_id` vem depois, por outro
processo. Nunca exija `cliente_id` numa trava.

### Financeiro
`obra_financeiro` (preco_negociado, custos, dispensado) · `obra_parcelas`
(previsão de recebimento) · `extrato_movimentos` (OFX) · `extrato_rateio`
(movimento → obra → conta → parcela) · `dre_lancamentos` + `dre_plano_contas`

**A fonte da verdade do realizado é o extrato.** Os campos de custo da ficha
são orçamento. Não some os dois.

`valor_projeto` e `preco_negociado` são espelhados pelo trigger
`trg_sincroniza_valor`. **Já existia — não crie outro.**

### Pós-venda
`usinas`, `usina_dia`, `usina_mes` · `clima_dia` · `v_indice_dia` ·
`v_indice_regiao` (cidade com 5+ usinas ganha grupo próprio) ·
`regua_contatos` + `regua_modelos` · `usina_marco` · `nps`

### Indicações
`indicacoes` — nova → contatada → visita → fechada/perdida

---

## 5. Funções principais

| Função | Para quê |
|---|---|
| `usina_estado(usina)` | normal, sem comunicação, parada, recém-ligada… |
| `usina_dias(usina, dias)` | geração diária com esperado, clima e base usada |
| `queda_geracao(usina)` | queda contra o padrão da própria usina |
| `usina_retorno(usina)` | quanto já se pagou do investimento |
| `linha_do_tempo(obra)` | história completa da obra |
| `conferir_saude()` | conferência geral das 7h30 |
| `casar_recebimentos(simular)` | casa entrada do banco com parcela |
| `indicacoes_resumo(obra)` | funil; só conta o que fechou |
| `regua_fila(limite)` | o que sai hoje às 17h |
| `regua_resumo_dia()` | o que a Lívia recebe às 11h |

---

## 6. Automações (horário de Brasília)

07h30 conferência · 08h45 clima · 09h geração e manutenção ·
09h15/13h15/16h15 status das usinas · 10h20 gera mensagens (seg–sex) ·
10h40 vincula usina nova · 11h resumo da régua (seg–sex) ·
14h30 geração parcial (seg/qua/sex) · 17h dispara a régua (seg–sex) ·
dia 2 fechamento · dia 5 resumo mensal · dia 6 marcos · dia 10 lembrete de
tarifa · domingo 11h30 limpa órfãos

**Fim de semana: vigilância roda, mensagem para cliente não.** Decisão do Vitor.

---

## 7. Parâmetros (tabela `config`)

Prefira criar parâmetro a chumbar número no código.

| Chave | Valor | O que faz |
|---|---|---|
| `economia_por_kwh` | 0,73 | única fonte de economia. ⚠️ sem calibrar desde antes do reajuste de abril |
| `conciliacao_automatica` | 1 | liga o casamento extrato ↔ parcela |
| `conciliacao_tolerancia` | 1,00 | diferença aceita em reais |
| `conciliacao_dias_max` | 90 | distância entre vencimento e data do banco |
| `conciliacao_conta_receita` | 01.1.06 | conta usada no DRE |
| `usina_carencia_dias` | 15 | usina recém-ligada não vira problema |
| `vizinhanca_min_usinas` | 5 | cidade com esse tanto ganha grupo próprio |
| `ger_desvio_alerta` | 25% | queda que dispara investigação |
| `ger_faixa_boa` | 85% | abaixo disso não vira boa notícia |
| `msg_ia_intervalo_dias` | 20 | descanso entre mensagens de cortesia |
| `msg_ia_intervalo_urgente` | 7 | descanso entre urgentes |

`campos_obrigatorios` define o que trava o salvamento — é `update`, não código.

---

## 8. Convenções de código

- HTML/JS puro, sem build. ES5-ish (`var`, `function`).
- Um arquivo por tela. CSS no topo, JS no fim.
- Supabase via `sb`, já inicializado.
- Erro vira `toast()` legível em português — nunca "erro ao salvar".
- **Toda gravação confere o erro antes de seguir.** Já houve perda de dados
  porque a tela apagava parcelas antes de confirmar o salvamento.

---

## 9. Armadilhas conhecidas

1. **Trigger duplicado** — procure antes de criar. Já criamos um espelhamento
   que existia há meses.
2. **`rollback` desfaz DDL** — se testar em transação, aplique a correção da
   função fora do bloco `begin/rollback`.
3. **Trigger adiado só age no commit** — `constraint trigger deferrable` não
   reflete dentro da mesma transação.
4. **CDN do GitHub leva ~3 min** — validar o arquivo publicado e esperar.
5. **Datalogger offline reporta zero** — significa "não medi", não "não gerou".
6. **Mês corrente nunca entra em comparação de desempenho.**
7. **`extrato_rateio.lancamento_id` é ON DELETE SET NULL** — por isso o trigger
   de desfazer é `deferrable`.

---

## 10. Estado e pendências

56 usinas · 50 normais, 6 sem comunicação · 22 automações ligadas.

- [ ] Lançar despesas de **junho e julho/2026** — mostram lucro que não existe.
      Bloqueante para análise de margem.
- [ ] Calibrar `economia_por_kwh` (estimativa 0,78–0,82)
- [ ] Completar distância em km e valor nas fichas incompletas
- [ ] 5 cards incompletos: 4349, 4420, 4483, 4563, 4808
- [ ] Confirmar se as parcelas de ~30% são entrada de financiamento
- [ ] Ligar proteção de senha vazada no Supabase
- [ ] Conferir cidades com IPTU Sustentável antes da última automação

Próximos módulos: garantia e nota fiscal · tela de indicação com o funil novo ·
comercial (só depois do financeiro confiável).

---

## 11. Como trabalhar aqui

1. Leia este arquivo.
2. Antes de criar, **procure se já existe**.
3. Mudou banco? Vira arquivo em `migrations/`, numerado por data.
4. Mudou tela? Valide a sintaxe do arquivo publicado.
5. Vai alterar em lote? Simule, mostre, só então grave.
6. Terminou? Diga o que testou e o que **não** testou.

Quando algo der errado, diga o que aconteceu de fato. O Vitor prefere saber do
erro do que receber um "está tudo certo" que não se sustenta.
