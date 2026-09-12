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
`usinas`, `usina_dia`, `usina_geracao` · `clima_dia` · `v_indice_dia` ·
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
| `economia_por_kwh` | **0,7968** | única fonte de economia. ⚠️ **PROVISÓRIO** — derivado de 0,73 × 1,0915 (reajuste CPFL de 22/04/2026), não de conta de luz. `tarifa_status()` devolve `provisorio: true`. Trocar assim que houver uma conta pós-abril: `select calibrar_tarifa(<valor>, '<de quem>')` |
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
| `recorde_min_dias` | 90 | histórico mínimo para avisar recorde |
| `recorde_margem` | 8% | quanto precisa superar o pico anterior |
| `recorde_intervalo_meses` | 6 | descanso entre avisos de recorde |

⚠️ A `config` tem RLS: a tela só enxerga `agenda_token`, `grupo_fixos`,
`iptu_envio_ativo` e `provisao_posvenda_desde`. Chave nova que a tela
precise ler tem de entrar na policy, senão o `select` volta vazio **sem
erro**. E a tela não escreve na `config` — escrita é por `ligar_automacao()`.

### Chaves que só as edge functions leem

Estas **não aparecem** se você procurar nos cron jobs ou nas funções do banco:
as edge functions leem a `config` pelo service role. Foi assim que a
`regua_ativa` passou por "morta" numa varredura — e ela é a trava mais
importante do sistema. Para saber se uma chave é viva, tem de abrir a edge
function.

| Chave | Valor | Onde é lida |
|---|---|---|
| `regua_ativa` | 1 | `regua-disparo` — **a trava dos 17h**; default `'0'`, some a chave e não envia |
| `regua_por_dia` | 15 | `regua-disparo` — teto de envios por dia |
| `usina_hora_ini` / `usina_hora_fim` | 9 / 17 | `usina-status` — janela de leitura |
| `usina_hora_min_alerta` | 12 | `usina-status` — não avisa antes disso (inversor acordando) |
| `usina_limite_geral` | 0,5 | `usina-status` — se mais que isso está ruim, cala: é pane geral, não usina |
| `usina_alerta_comunicacao_dias` | 2 | `usina-status` — dias mudo **e sem gerar** antes de avisar |
| `solarview_vincular_ativo` | 1 | `solarview-vincular` |
| `solarview_etapa_minima` | 7 | `solarview-vincular` |
| `vinculo_palavra_comum` | 3 | `solarview-vincular` — palavra que aparece demais não vale como prova |
| `vinculo_min_palavras_iguais` | 2 | `solarview-vincular` |
| `solarview_avisa_pendente` | 1 | `solarview-vincular` |
| `ger_dias_janela` | 35 | `solarview-diario` |
| `hsp` | 4,9 | `conferencia-geracao` — horas de sol pleno |
| `perf_ratio` | 0,78 | `conferencia-geracao` |

⚠️ `hsp` e `perf_ratio` entram no **mesmo cálculo de economia que o cliente
lê**, junto com `economia_por_kwh`. Calibrar uma sem as outras desloca o
número. O `perf_ratio` já está calibrado (0,78); o `economia_por_kwh` não.

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

56 usinas · **50 normais, 6 sem comunicação** · 29 cron jobs, **todos
ativos** · 21 chaves de automação em `config`, 20 ligadas — a única
desligada é `iptu_envio_ativo`, de propósito (ver pendência abaixo). A
`solarview_ativo` foi **removida** em 12/09: estava em 0, ninguém lia, e fazia
parecer que o monitoramento estava desligado enquanto ele entregava dado todo
dia.

As 6 sem comunicação não são iguais, e tratar como um número só esconde o
que importa:

| Quantas | Situação | Vale agir? |
|---|---|---|
| 3 | sem medição há 1 dia (última 11/09) | não — é o normal do datalogger |
| 1 | **sem medição há 21 dias** (última 22/08) | **sim, é a única urgente** |
| 2 | nunca comunicaram desde a instalação | sim — nasceram mudas |

Lembre da armadilha 5: datalogger offline reporta zero, e zero aqui
significa "não medi", não "não gerou". Conferido no banco em 12/09/2026.

- [ ] **Importar o extrato anterior a agosto/2026.** O extrato começa em
      03/08. Maio, junho e julho têm zero lançamento vindo do banco — o que
      está neles é orçamento da ficha, não realizado. Comparar a margem de
      julho com a de agosto é comparar orçado com realizado. Bloqueante para
      análise de margem, e a causa é esta, não "faltam despesas": junho tem
      R$ 124.167 e julho R$ 120.328 lançados, só que pela ficha.
- [ ] **Calibrar `economia_por_kwh` com uma conta de luz de verdade.** Está em
      0,7968 desde 12/09, mas é **provisório**: saiu de 0,73 × 1,0915, e não de
      uma conta. Basta uma conta pós-abril de qualquer cliente — total em R$
      dividido pelo total em kWh — e um `calibrar_tarifa()`. O
      `tarifa_status()` marca `provisorio: true` e conta 8 meses desde a
      última calibração real, então o lembrete continua cobrando.
- [ ] Completar distância em km e valor. De **71 obras**: **58 sem km**,
      **23 sem valor**, 22 sem os dois — **59 com pelo menos um furo**.
      Toda obra tem ficha financeira criada; o que falta é preencher.
      Somam-se a isso **13 obras** cujas parcelas não fecham com o preço
      (diferença acima de R$ 1,00).
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
