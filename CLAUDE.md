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

⚠️ **A conciliação automática não adivinha no empate.** `casar_na_hora` é um
trigger em `extrato_rateio`: entrada de dinheiro apontada para uma obra procura
a parcela aberta de valor parecido (`conciliacao_tolerancia`, R$ 1,00) com o
vencimento mais próximo (`conciliacao_dias_max`, 90 dias), marca como recebida
e cria o lançamento no DRE.

**Medido em 15/09:** os 18 casamentos feitos até então estavam **todos** com
diferença de R$ 0,00 e 0 dias. Zero falso positivo — e também o sinal de que a
folga de R$ 1,00 e 90 dias nunca foi usada.

O risco era o empate: com `limit 1`, duas parcelas igualmente plausíveis viravam
cara ou coroa. O EDVALDO (4657) tem **4 parcelas abertas de R$ 1.500,00, duas
vencendo no mesmo dia**. Desde 15/09 o trigger busca as **duas** melhores
candidatas e, se empatarem na distância, **não casa** — o movimento vai para a
fila humana. Não recusa todo empate de valor de propósito: o João Vitor (4425)
tem duas parcelas de R$ 1.000,00 com vencimentos diferentes e o critério
acertou as duas.

O lançamento no DRE guarda a **evidência** do casamento (`diferença R$ X · Y
dia(s) do vencimento`), para dar para revisar depois se foi certeiro ou chute.

`valor_projeto` e `preco_negociado` são espelhados pelo trigger
`trg_sincroniza_valor`. **Já existia — não crie outro.**

### Indicadores (`get_kpis_financeiro`)
**R$ por Watt-pico** é a métrica que compara com o mercado — margem em reais
não compara com ninguém. A mediana da casa é **R$ 2,54/Wp** (R$ 2.540 por kWp)
em 50 das 52 obras de venda. Levantamentos de 2026 põem o residencial
brasileiro entre **R$ 3,50 e 5,50/Wp**; é referência, não meta, porque escopo e
região mudam o número. O que vale seguir é a tendência dos próprios meses.

**Execução × faturamento** (WIP, método custo-a-custo) mede o avanço pelo custo
incorrido sobre o estimado e compara com o quanto já foi cobrado.

⚠️ **A primeira versão do WIP mentia e foi jogada fora.** Ela devolvia
*1847% executado* para a Zuleica (4618): R$ 661,83 de custo estimado na ficha
contra R$ 12.229,80 de gasto real. Não é obra 18 vezes pronta — é a estimativa
que não existe. Hoje o WIP exige os **dois** lados confiáveis: estimativa de
pelo menos **30% do preço** e obra fechada **dentro da janela do extrato**.
Sobram **3 de 52**, e a função devolve `o_que_falta` justamente para a tela
poder dizer isso em vez de fingir retrato da carteira.

**DSO não existe de propósito.** Só 16 obras têm parcelas e o extrato cobre 5
semanas — o número sairia com cara de autoridade e sem lastro. Nasce sozinho
quando o extrato anterior a agosto entrar.

⚠️ **Todo custo de obra tem até TRÊS números, e eles moram em lugares
diferentes:** o **previsto** (`obra_financeiro.previsto_*`, calculado por
telhado/km/módulos), o **no banco** (`extrato_rateio` → `dre_lancamentos`, via
`obra_custos_realizados`) e o **na ficha** (digitado). Até 16/09 a ficha
mostrava os três em blocos separados que nunca se encontravam, e a margem lia
**só a ficha** — por isso o GILSON (4678), com a ficha zerada, aparecia com
*"margem 100,0%"* enquanto o banco já tinha pago R$ 1.151,09 e o orçamento era
R$ 8.195,83. Pior: a tabela "Orçado × Realizado" lia a ficha na coluna
*Realizado* e pintava **−R$ 7.836 de verde**, como economia.

Hoje é **uma linha por item com as três colunas**, e a margem segue a **ordem
de confiança `ficha → banco → previsto`**: dinheiro confirmado nunca perde para
palpite, e o veredito diz em voz alta quanto do custo ainda é estimativa. Obra
de ficha zerada não aparece mais com 100% de lucro.

⚠️ **A ficha não repete o extrato: ela lê.** Até 15/09 a Ana classificava o
movimento no extrato (o que **já vincula a obra** — 55 dos 60 custos estão
ligados) e depois digitava o mesmo valor na ficha, porque nada trazia o número
de volta. Medido: **6 campos digitados duas vezes**, **39 só no extrato** com a
ficha zerada, e **5 divergentes**. Hoje `obra_custos_realizados(obra)` soma por
obra e por campo, e a ficha mostra o valor com um botão "usar".

O mapa conta → campo vive em **`dre_plano_contas.campo_ficha`**, não no código:
`03.1.01 → valor_kit`, `03.2.01 → instalacao`, `04.1.01 → comissao_valor`… Conta
nova ganha o campo dela sem mexer em tela.

⚠️ **Não sobrescreva a ficha pelo extrato em lote.** O extrato cobre
**03/08 a 08/09/2026**, e de 27 obras com custo lançado **14 fecharam antes de
03/08** — o custo delas foi pago fora da janela. O caso que prova: o carport do
Jose Antonio (4674), ficha R$ 9.386,01 contra R$ 268,65 no extrato, obra
fechada em 28/07. Puxar por cima apagaria R$ 9.117,36 de custo real e inflaria
a margem. Por isso o "Puxar do extrato" só mexe sozinho no que está **vazio**,
divergente pergunta antes, e obra fora da janela ganha aviso próprio. Some
quando o extrato anterior a agosto for importado (pendência no §10).

### Pós-venda
⚠️ **Geração mora em `usina_geracao` (por usina), não em `geracao` (por obra).**
A `geracao` existe para entrada manual e está **vazia**. Até 15/09 a tela lia
dela, e por isso "Geração e desempenho" aparecia vazia para todos os clientes.
Uma obra pode ter **várias usinas** (o Gilberto tem 4), então **nunca some
sozinho**: use `obra_geracao_total(obra)`, que é a definição única — soma as
usinas, ignora os meses de zero que o SolarView devolve antes da instalação,
deixa o mês corrente de fora e compara contra a mediana da vizinhança.
A tela, a régua e os painéis leem todos dali, então o que o cliente recebe
bate com o que a equipe vê. Só `get_geracao_bruta` ainda lê a tabela vazia —
é código morto, sem nenhum chamador.

⚠️ **`obra_usina` é a ligação obra ↔ usina, não `usinas.cliente_id`.**
**Vinte e quatro funções** leem essa tabela — `obra_geracao_total`,
`get_geracao`, `get_ficha_cliente`, `get_posvenda_lista`, `usina_estado`,
`pendencias_posvenda`, `linha_do_tempo` entre elas. Usina criada sem essa
linha nasce meio conectada e some de tudo. Aconteceu em 15/09 com as duas da
Tays, e o achado **"usina sem obra"** da `conferir_saude_base()` é a rede que
pega isso.

| coluna | o que guarda |
|---|---|
| `papel` | `propria` · `expansao` · `herdada` (instalou outra empresa) |
| `medicao` | `inversor_proprio` · `compartilhado` (aí `kwp_parte` é obrigatório) |
| `principal` | uma só por obra, garantido por índice único parcial |
| `entrou_em` / `saiu_em` | vigência |

### Chuva, geração baixa e o card de aprovação
⚠️ **A chuva já entra na conta — o que faltava era mostrar.** `queda_geracao`
lê `usina_dias(usina, 21)`, que cruza `clima_dia` e o índice da vizinhança, e
**descarta o dia inteiro quando o índice fica ≤ 1,5** — dia em que os vizinhos
também geraram mal não conta. Depois compara pela `razao`, que já é a usina
**contra os vizinhos daquele dia**. Por isso "gerando 72% do padrão dela em 10
dias de sol" **não é chuva**: os dias de chuva já saíram. O card "Escritas pela
IA — esperando você" não dizia nada disso, e quem aprovava confiava às cegas.
Desde 21/09 ele mostra `geracao_contexto(usina)`.

⚠️ **O clima vem de UM ponto só, e a vizinhança de quase todo mundo é um balde
único.** `clima_lat`/`clima_lon` têm default **-21,2089 / -50,4328 = Araçatuba**
— `clima_dia` não tem coluna de cidade. E `v_indice_regiao` só separa cidade com
**5+ usinas no dia**: hoje **só Araçatuba**; as outras 18 cidades caem juntas num
balde chamado `regiao`. Para uma usina de Guarulhos ou Araçariguama isso
significa que o clima é de ~500 km de distância **e** que o descarte de dia
fechado é decidido pelo interior — chove lá, faz sol aqui, o dia não é
descartado e a razão dela cai sem culpa. `geracao_contexto` **expõe** isso em
vez de esconder: `clima_vale`, `usina_cidade`, `clima_medido_em` e um `aviso`
em português. A lista de cidades cobertas é `config.clima_cidades` (default
`clima_cidade_base`), para o dia em que houver mais de um ponto.

⚠️ **Mensagem parada na fila envelhece.** As duas de `geracao_baixa` escritas
em 18/09 estavam **falsas** em 21/09: Jaqueline 73% → **78%** e Marcia 72% →
**75%**, `queda_geracao.caiu = false` nas duas. Aprovar mandaria alerta de
geração baixa para cliente cujo problema acabou. Por isso o contexto traz
`ainda_caida` — o `caiu` **de agora**, recalculado ao abrir a tela, não o de
quando a IA escreveu — e o card pinta em vermelho quando é `false`. Não
bloqueia o envio (regra 3.5, quem decide é a pessoa); garante que ela decida
vendo.

### NPS e avaliação no Google
⚠️ **O convite AUTOMÁTICO do Google sai UMA vez e nunca mais.** Quem agenda é o
`nps-resposta`, no instante em que a nota entra (`nps.google_agendado_para`); a
`nps-google-fila` manda uns minutos depois e apaga o agendamento. Não existe
segunda cobrança automática, e não vai existir: a segunda é **na mão**, pelo
botão *"⭐ Cobrar no grupo"* da ficha, onde o clique da pessoa é a aprovação da
regra 3.5 — ela lê o texto inteiro antes de mandar. O texto vem de
`nps_cobranca_google(obra)`, com o link saindo da `config.google_review_url` e
o da pesquisa da `relatorio_base_url`; nada chumbado na tela. Ela recusa nota
abaixo de 9, quem já avaliou e obra sem grupo.

⚠️ **`nps_para_lembrete_google()` foi APAGADA em 17/09**, junto com a chave
`lembrete_google_max`. Não tinha chamador nenhum desde que a fila virou
`google_agendado_para` — ficava na documentação parecendo viva. A
`lembrete_google_dias` (3) **ficou**: é o corte de dias do aviso das 8h.
`registrar_lembrete_google()` também era morta e voltou, agora chamada pela
tela (com trava de `is_autorizado()`), para carimbar cada cobrança manual.

⚠️ **`nps.lembretes_google` conta mal até 17/09.** O `registrar_nps_manual`
grava `1` já no insert, e 44 dos 51 são o backfill que a equipe digitou entre
08/08 e 02/09 — não era lembrete nenhum. O KPI *"Lembretes enviados"* do
`metricas.html` lia esse campo e **foi removido** (§3.1). No lugar entrou a
divisão que importa: `automaticos` × `manuais` em `get_horarios_resposta`,
ou seja quanto veio da esteira e quanto veio da mão da equipe. Daqui em diante
o campo só cresce por cobrança de verdade.

⚠️ **Ser promotor já libera o convite — a ressalva não cala mais.** Decisão do
Vitor em 17/09. Até então o `nps-resposta` exigia `nota >= 9` **e** `tipo =
elogio` puro, e nota 10 com qualquer ressalva junto ficava sem convite **para
sempre**, porque o automático sai uma vez só. Hoje `pedeGoogle` é só
`nota >= 9`, e `avisaEquipe` virou condição **independente** (`ressalva ou nota
< 9`) — quem apontou algo continua acionando a equipe e agora também recebe o
convite. O **agradecimento** segue a ressalva, não o convite: quem reclamou
recebe *"obrigado pela sinceridade"*, nunca a comemoração.

Conferido em modo simular, sem gravar nem enviar: nota 10 com ressalva devolve
`pede_google: true, avisa_equipe: true`; nota 6 devolve `false/true`; elogio
limpo devolve `true/false`.

⚠️ **O convite e o aviso de ressalva saem quase juntos.** O agradecimento sai
na hora e o convite ~3 minutos depois, enquanto o aviso à equipe também acabou
de sair — ou seja, o cliente é convidado a avaliar publicamente **antes** de
alguém ter resolvido o que ele apontou. Foi decidido assim; se um dia
incomodar, o lugar de segurar é o `google_agendado_para` do `nps-resposta`.

⚠️ **O NPS é por CLIENTE desde 17/09** (decisão do Vitor). A tabela `nps`
continua **única por `obra_id`** — o que mudou é quem é *perguntado*:
`obras_para_nps()` exclui obra cujo `cliente_id` já respondeu em outra. A trava
**só vale quando `cliente_id` existe** (4 das 75 obras não têm, porque a tela
grava `cliente` texto e o id vem depois); sem ele cai no comportamento antigo,
por obra — o lado seguro, que nunca cala um NPS legítimo. Medido: **1 obra**
muda de comportamento, o eletroposto do Bassetto (4674, etapa 1), cujo cliente
já deu 10 na manutenção. Consequência a saber: quem comprar um **segundo
sistema** daqui a dois anos também não será perguntado.

**Medido em 17/09:** 55 obras ativas, 55 pediram a nota, **54 responderam
(98%)**, 54 promotores (nota ≥ 9 em todas), **52 avaliaram no Google**, 51
escolheram brinde, 50 entregues. 44 das 54 respostas são backfill manual — o
caminho automático tem 10 registros e é de setembro. O resultado é ótimo, mas
quem o fez foi a equipe; a esteira ainda está provando.

`usinas`, `usina_dia`, `usina_geracao` · `clima_dia` · `v_indice_dia` ·
`v_indice_regiao` (cidade com 5+ usinas ganha grupo próprio) ·
`regua_contatos` + `regua_modelos` · `usina_marco` · `nps`

### Planos
`planos` (tabela de preço por faixa de módulos) · `plano_contratos` (o que
cada cliente assinou). Os **53 contratos até 15/09 eram todos cortesia de
R$ 0,00** — o módulo nunca tinha registrado dinheiro, e os painéis de receita
mostravam zero desde abril.

⚠️ **`plano_contratos.obra_id` e `regua_contatos.obra_id` são NOT NULL.** A
obra é a espinha: sem ela não existe contrato nem régua. É por isso que um
**cliente de plano** — quem paga o acompanhamento sem ter comprado a usina —
entra como obra de trilha `manutencao` com `cliente_externo = true` e
`valor_projeto` nulo. Não é venda: fica fora de conversão, margem e funil,
mas ganha régua, monitoramento e contrato.

Para quem a nota é emitida vive no **contrato**, não em `clientes`:
`nota_documento` aceita CPF (11 dígitos) ou CNPJ (14) e o tipo se deduz do
tamanho — não existe campo separado, para não divergir do número.

⚠️ **Cliente de plano sem contrato some do painel.** `plano_cadastrar_cliente`
só cria o contrato quando o plano foi escolhido — deixar em branco é legítimo, e
`get_painel_planos` lê `from plano_contratos`, então o cliente ficava invisível.
Aconteceu em 16/09 com o **UNI AUTO POSTO DE ARACATUBA LTDA**: gravou cliente,
obra, **duas usinas** (235 kWp, 420 módulos), os dois vínculos em `obra_usina` e a
ficha — e **zero contrato** —, devolveu `ok: true` e não apareceu no
Acompanhamento. Desde então o painel devolve `sem_contrato`, a tela mostra a
seção **"Cliente de plano sem contrato"** com o botão de fechar, e
`plano_contrato_criar()` fecha o contrato numa obra que já existe (um contrato
aberto por vez — clicar duas vezes contaria receita em dobro).

⚠️ **Cortesia não tem pagamento para aguardar.** Cortesia com "começa no 1º
pagamento" ficaria em `aguardando_pagamento` para sempre: sem início, sem fim,
fora de todo número e sem ninguém para dar baixa. As **duas** funções recusam
(`plano_contrato_criar` e `plano_cadastrar_cliente`), e a tela já desmarca a
opção quando a cobrança vira cortesia. Conferido: a recusa vale mesmo quando a
trava da tela é contornada na mão.

⚠️ **A ficha financeira de cliente de plano nasce `dispensado = true`.**
`abre_financeiro_obra()` cria ficha para toda obra com etapa >= 1, e
`trava_campos_financeiro()` exige `preco_negociado` e `distancia_km`. Um
cliente de plano não tem nenhum dos dois e o cadastro ficava **impossível** —
descoberto na simulação, antes de gravar. A ficha continua existindo (o plano
gera receita e ela vai precisar de lugar), mas não cobra campo de venda.

A tabela do Completo vai até **125 módulos**. As faixas acima de 45 foram
criadas em 15/09 a partir da regra que a própria tabela já seguia — as duas
últimas faixas antigas sobem **exatamente R$ 20,00 por módulo/ano**, e o
preço é sempre o do **topo da faixa**:

`anual = 1.290 + 20 × (topo − 45)` · `mensal = anual ÷ 10,716`

Conferido contra o contrato real da Tays (120 módulos, R$ 2.990/ano e
R$ 279/mês): a razão da tabela devolve R$ 279,02, e a regra dos módulos dá
R$ 2.790 — os R$ 200 que faltam são o segundo endereço.

Acima de 125 fica a `completo_especial`, **sem preço de tabela de propósito**:
o valor é negociado e vive no contrato. Quem lê `planos` tem de tratar
`preco_mensal`/`preco_anual` nulos como "sob consulta"; `moedaBR(null)`
imprime `R$ 0,00`, que é número inventado indo para o cliente.

⚠️ **Endereço, não usina.** O Completo vende uma visita anual em cada
endereço, então a proposta soma `plano_endereco_adicional` por endereço além
do primeiro. A conta é
`count(distinct coalesce(endereco, cidade))` entre as usinas ativas do
cliente — o Gilberto tem **4 usinas e 1 endereço** e não paga extra. Quando
`endereco` está vazio a conta cai para a cidade, então ela **subestima**, que
é o lado seguro: nunca cobra a mais, e se corrige quando alguém preencher.

### Laudo de manutenção
⚠️ **Já existe, e já rodou ponta a ponta.** Não crie relatório de manutenção do
zero. O caminho inteiro está de pé: `checklist_itens` tem **11 itens próprios da
trilha `manutencao`** (9 obrigatórios, incluindo *"Apontamentos e laudo"*), o
instalador alimenta pelo `instalador.html` com o `instalador_token`,
`get_relatorio_publico` **filtra a checklist pela trilha** e devolve
`apontamentos`, e o `relatorio.html` muda sozinho o título para *Relatório de
Manutenção Preventiva/Corretiva* ou *Laudo de Avaliação Técnica*.

A prova: **Jose Antonio Bassetto** (corretiva, `manutencao-bassetto-2026-08`) —
35 fotos e vídeos em 19/08, 1 apontamento, termo assinado em **07/09**.

`obra_itens_relatorio` (via `salvar_secoes_relatorio`) **renomeia e oculta item
por obra** — foi assim que aquele laudo virou "Estrutura: folgas corrigidas e
reforço galvanizado" em vez do título genérico.

⚠️ **Obrigatoriedade é por tipo de manutenção.** `checklist_itens.obrig_tipos`
(`text[]`, nulo = todos os tipos) e a regra única `checklist_exige(obrigatorio,
obrig_tipos, tipo_manutencao)`. Hoje só *"Limpeza executada"* está marcada, com
`{preventiva}` — antes ela era cobrada numa **corretiva** em que a limpeza não
tinha sido aprovada, e virava cobrança falsa no grupo do instalador. **Três**
funções usam a regra: `get_status_relatorio`, `obras_cobranca_fotos` e
`get_obra_instalador` — essa última para a estrela que o instalador vê no
celular seguir o mesmo critério.

⚠️ **Cada visita tem a SUA obra de manutenção, e é dela que sai o laudo.**
`plano_visita.obra_id` aponta para uma obra criada por `plano_visita_abrir_obra()`
— trilha `manutencao`, etapa 1, herdando cliente, grupo, endereço e a data
prevista. Não foi preciso inventar relatório de visita: obra de manutenção já
traz link do instalador, checklist de 11 itens, fotos, apontamentos e relatório
público. **Uma obra por visita** é o que impede visitas de anos diferentes de
apontarem todas para o mesmo link.

É seguro do lado financeiro porque `abre_financeiro_obra()` nasce com
`dispensado = true` para **qualquer** obra de trilha `manutencao` — o mesmo
motivo pelo qual o cliente de plano consegue ser cadastrado.

`plano_visita_registrar` cai em `plano_visita_laudo_da_obra()` quando ninguém
colou link, e devolve `laudo_automatico`. Ela usa a obra da visita e, **se a
visita ainda não tiver obra**, cai na obra do contrato — as visitas antigas não
ficam sem nada. **Relatório sem foto não vira laudo**, de propósito: o cliente
abriria uma página vazia. A URL sai de `config.relatorio_base_url`.

⚠️ `obra_relatorios` guarda **PDF anexado à mão** (`origem = 'arquivo'`, 37
registros). O laudo que o sistema gera **não** é arquivado ali — ele vive como
link para o `relatorio.html`.

### Visitas do plano
**A primeira visita do sistema nasceu em 16/09**: UNI AUTO POSTO, prevista para
**16/12/2026**, no meio da cortesia de 6 meses. Ela ficou **uma só** porque as
duas usinas dele estão no mesmo lugar — o `endereco` estava escrito de dois
jeitos (`AREA RURAL CLEMENTINA` e `CLEMENTINA`) e foi padronizado, decisão do
Vitor. A visita ancora na usina de **maior potência** do endereço (129,60 kWp),
que é o critério da própria `plano_visitas_gerar`.

⚠️ **Endereço escrito de dois jeitos vira endereço a mais.** A conta de visitas
e a de `plano_endereco_adicional` são as duas `count(distinct endereco)`: texto
divergente cobra R$ 200/ano a mais e manda a equipe à mesma cidade duas vezes.
Antes de gerar visita para cliente com várias usinas, **olhe os endereços**.

`plano_visita` (contrato → endereço → prevista/realizada, com laudo). Nascem
**uma por endereço**, no meio do período, por dois caminhos: quando
`plano_registrar_pagamento()` dá baixa no contrato que esperava pagamento, e
quando `plano_contrato_criar()` fecha um contrato que já nasce **ativo**
(cortesia, ou pago com data de início informada).

⚠️ **O segundo caminho não existia até 16/09.** `plano_visitas_gerar()` só era
chamada pelo registro de pagamento, então contrato nascido ativo prometia visita
e não marcava nenhuma. Não aparecia porque as 54 cortesias antigas são todas
`essencial`, que tem `inclui_visita = false` — o buraco só podia surgir no dia
em que existisse um **Completo ativo**, e foi o UNI AUTO POSTO. `plano_visitas_gerar`
é idempotente e checa `inclui_visita` e `inicio` sozinha, então chamar nos dois
lugares é seguro. A tela conta separadamente as **realizadas sem laudo**:
laudo com foto é o que o fabricante pede no acionamento de garantia.

### Fim da cortesia
Os 54 contratos ativos são **todos cortesia de um ano**, e o cliente não tem
como adivinhar que ela acaba. `plano-vencimento` avisa em **D-30 e D-7** pela
`contratos_para_avisar()`, e desde 15/09 o texto distingue cortesia de
renovação paga: diz que foi cortesia, lista **o que para de acontecer**
(monitoramento, aviso de parada, relatório) e só então traz o preço da faixa
do porte dele. Ainda não disparou para ninguém — o **primeiro vencimento é
17/04/2027**.

⚠️ **Esse aviso sai direto para o cliente, sem passar pela régua e sem a
aprovação da Lívia.** Já era assim antes de 15/09; o que mudou é que agora a
mensagem carrega preço e oferta. A equipe recebe o resumo no mesmo disparo,
**depois** do cliente. Se for para exigir aprovação, a mudança é na
`plano-vencimento` e é decisão do Vitor.

`plano_contratos.desfecho` guarda **como** o contrato terminou —
`renovou` · `nao_renovou` · nulo enquanto aberto. Antes disso, cortesia que
virou plano pago e cortesia que se perdeu ficavam as duas em `encerrado`, e
não dava para responder "de 54 cortesias, quantas viraram cliente?".
`plano_desfecho()` fecha a antiga e, quando renovou, **cria a nova na mesma
chamada** (herdando obra, CPF/CNPJ e nome da nota), já em
`aguardando_pagamento` — plano só começa quando o dinheiro entra. Não apaga
nada: a antiga fica com o desfecho carimbado e a nova aponta para ela na
observação. Fechar duas vezes é recusado com a data do primeiro fechamento.

O botão "fidelizou?" no painel só aparece a **90 dias ou menos** do
vencimento e **nunca** em contrato aguardando pagamento — ali `dias` é nulo, e
`n(null)` devolve `0`, que passaria por "vence hoje".

### Autoleitura
`unidade_consumidora` (o relógio; um cliente rural pode ter vários) +
`uc_leitura_prevista` (o calendário que a conta de luz mostra, com
`responsavel` = cliente ou distribuidora). Só as de responsabilidade do
**cliente** geram aviso.

⚠️ **Não entrou na régua de propósito.** `regua_contatos` tem
`UNIQUE (obra_id, modelo)` — uma mensagem por modelo por obra, para sempre, e
é isso que impede a régua de repetir boas-vindas. Autoleitura é mensal, então
ou criaria um modelo por mês ou afrouxaria esse índice. Ganhou casa própria.

**Ligada desde 15/09**, com os horários que o Vitor definiu: **9h o aviso do
dia** (quem lê o relógio faz de manhã) e **18h a véspera** (depois da régua das
17h, para não disputar). Quem envia é a edge function `autoleitura-aviso`, no
mesmo desenho do `regua-disparo`: `verify_jwt` false, autorizada pelo
`cron_token`, e só marca como avisado **depois** que a Z-API aceita.

Aceita `{"simular":true}`, que lista quem receberia sem enviar nada.

Para desligar não se mexe em cron nem em código:
`update config set valor='0' where chave='autoleitura_ativo'` — a função lê a
chave em toda rodada.

⚠️ **A autoleitura é o único lugar com canal pessoal.** Desde 16/09 ela manda
no grupo **e** no WhatsApp pessoal do cliente, e só marca como avisado se pelo
menos um dos dois aceitou. Isso **não encosta na régua**: a autoleitura tem
edge function própria, então o canal pessoal aqui não passa pela
`regua-disparo`. **A régua continua só no grupo** — ali sim mexer no canal
significa mexer na trava dos 17h.

Cobertura: **72 das 73** obras ativas têm celular cadastrado, 73 têm grupo. A
fila aceita quem tem grupo **ou** celular.

### Lançar e corrigir as datas
A conta de luz mostra as "Próximas Leituras" em bloco. `uc_leituras_salvar_lote`
grava todas de uma vez; linha em branco é ignorada sem virar erro, e data
inválida vira aviso sem derrubar as outras.

`uc_leitura_atualizar` corrige uma data. `uc_leitura_apagar` **recusa apagar o
que já virou mensagem para o cliente** — regra 3.6: data futura digitada errada
não é histórico, aviso que já saiu é.

`autoleitura_resumo_texto(uc)` monta o calendário inteiro para mandar no grupo,
e **só promete o canal pessoal quando a obra tem celular** — sem número, diz
apenas "aqui no grupo".

⚠️ O botão "Enviar o calendário no grupo" **não marca as leituras como
avisadas**, de propósito. O calendário é informativo; marcar ali calaria os
lembretes da véspera e do dia, que é o oposto do que ele serve.

### Quem recebe o quê
`equipe` tem dois papéis, e é por eles que as automações escolhem o destino —
não pelo nome nem pelo número:

| coluna | quem é hoje | o que chega |
|---|---|---|
| `resp_posvenda` | Lívia de Paula | vínculo de usina pendente, conferência das 7h30, resumo da autoleitura |
| `resp_alertas` | Vitor | vencimento de plano |

`definir_responsavel(equipe, funcao)` troca a pessoa (`is_admin()`), e
`get_responsavel_posvenda()` diz quem são os dois. **Nenhuma das duas tem tela**
— a troca é na mão, no banco.

⚠️ **Nem tudo segue o papel.** `alerta_destinos`, `alerta_credito_destinos` e
`grupo_fixos` guardam **número**, e trocar a pessoa em `equipe` não muda
nenhuma delas. Ver pendência no §10.

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
| `pendencias_posvenda()` | o que a Lívia recebe às 8h — mensagem sem resposta, promotor sem avaliação no Google, brinde a entregar, sem NPS, sem aniversário; **com nome, não só número** |
| `regua_fila(limite)` | o que sai hoje às 17h |
| `regua_resumo_dia()` | o que a Lívia recebe às 11h |
| `obras_para_nps()` | quem recebe o NPS: **só depois da última etapa da trilha**, e **um por cliente** — quem já respondeu numa obra não é perguntado de novo |
| `nps_cobranca_google(obra)` | o texto da **segunda cobrança** da avaliação, para a pessoa ler e mandar no grupo; recusa nota < 9, quem já avaliou e obra sem grupo |
| `obra_ativa(obra)` | **a definição única de "está ativa"**: chegou na última etapa da própria trilha |
| `obra_ativa_em(obra)` | desde quando está ativa (cai no `etapas_historico` se `data_conclusao` for nula) |
| `obra_geracao_total(obra)` | **quanto a obra já gerou**: kWh, economia, desempenho e meses — a fonte única |
| `geracao_contexto(usina)` | o que sustenta um aviso de geração baixa: dias usados × descartados por dia fechado, chuva e sol do período, a base da comparação, e **`ainda_caida`** — se a queda ainda existe **agora** |
| `plano_registrar_pagamento(contrato, data)` | liga o contrato no dia em que o primeiro pagamento entrou; é ela que calcula `inicio` e `fim` |
| `plano_cadastrar_cliente(json, simular)` | **cadastra cliente de plano inteiro**: cliente + obra + usinas + contrato numa transação. Com `simular = true` (o padrão) não grava nada e devolve a prévia ou a lista de erros |
| `plano_contrato_criar(json, simular)` | fecha o contrato numa obra que **já existe** — o caminho de volta para o cliente de plano que ficou sem. Um contrato aberto por vez |
| `plano_visitas_gerar(contrato)` | cria as visitas previstas, uma por endereço, no meio do contrato |
| `plano_visita_abrir_obra(visita, simular)` | cria a obra de manutenção **daquela visita**; é dela que sai o laudo |
| `plano_visita_laudo_da_obra(visita)` | a URL do relatório da obra da visita (cai na do contrato se não houver) — **nula se não tem foto** |
| `checklist_exige(obrigatorio, obrig_tipos, tipo_manutencao)` | **a regra única** de item obrigatório; três funções a usam |
| `get_relatorio_publico(slug)` | o laudo/relatório público, já filtrado pela trilha da obra |
| `plano_visita_registrar(visita, data, equipe, laudo, obs)` | dá baixa numa visita |
| `plano_desfecho(contrato, desfecho, motivo, plano, valor, forma, meses, aguardando)` | fecha o contrato como `renovou`/`nao_renovou` e, se renovou, já abre o novo na mesma chamada |
| `contratos_para_avisar()` | quem está a 30 ou 7 dias do fim, com módulos, faixa do Completo e quantos endereços |
| `autoleitura_fila()` | quem avisar hoje, com o texto pronto |
| `uc_leituras_salvar_lote(uc, itens)` | lança várias datas de leitura numa transação só |
| `uc_leitura_atualizar` · `uc_leitura_apagar` | corrigem uma data; apagar é recusado se o cliente já foi avisado |
| `autoleitura_resumo_texto(uc)` | o calendário inteiro para mandar no grupo, com os canais que de fato existem |
| `get_responsavel_posvenda()` | quem é o `resp_posvenda` e o `resp_alertas` hoje |
| `definir_responsavel(equipe, funcao)` | troca a pessoa de um dos dois papéis; só admin |
| `get_kpis_financeiro(ini, fim)` | R$/Wp e execução × faturamento, **com a cobertura junto** — quantas obras sustentam cada número e o que falta para as outras |
| `obra_custos_realizados(obra)` | o realizado da obra vindo do extrato, campo a campo; diz também se o extrato cobre o período da obra |
| `dia_util_ate(data)` | o último dia útil em `data` ou antes — é o que antecipa o aviso de fim de semana para a sexta |
| `usina_adicionar(json, simular)` | acrescenta uma usina a um cliente que já existe. **Só soma no total da obra se ela for cliente de plano** — em obra de venda a potência é o projeto vendido, e mexer ali muda o tamanho de uma venda que já aconteceu |

---

## 6. Automações (horário de Brasília)

**08h aviso de pendências do pós-venda** (seg–sex, `alerta-pendencias` →
`resp_posvenda`) · 07h30 conferência · 08h45 clima · 09h geração e manutenção ·
09h15/13h15/16h15 status das usinas · 10h20 gera mensagens (seg–sex) ·
10h40 vincula usina nova · 11h resumo da régua (seg–sex) ·
14h30 geração parcial (seg/qua/sex) · 17h dispara a régua (seg–sex) ·
**9h aviso de autoleitura no dia · 18h aviso da véspera** (seg–sex) ·
9h aviso de vencimento de plano, D-30 e D-7 (seg–sex) ·
dia 2 fechamento · dia 5 resumo mensal · dia 6 marcos · dia 10 lembrete de
tarifa · domingo 11h30 limpa órfãos

**Fim de semana: vigilância roda, mensagem para cliente não.** Decisão do Vitor.

⚠️ **NPS e convite do Google só saem depois da ATIVAÇÃO**, nunca depois da
vistoria. Na trilha padrão a etapa 7 é "Vistoria e Conexão" e a 8 é "Sistema
Ativo!" — é a 8 que libera. A trava é "chegou na última etapa da **própria
trilha**", porque `manutencao` vai só até a 4 ("Concluída") e um corte em
">= 8" a deixaria sem NPS para sempre. Até 14/09 existia um atalho pelo termo
assinado (`aceite_em`) que furava isso: três obras receberam o NPS na etapa 7,
e uma já estava na fila do Google com a usina desligada. Desde então existe
`obra_ativa()`: **toda automação que fala com o cliente deve passar por ela**,
em vez de escrever `etapa_numero >= 8` à mão. As outras automações foram
conferidas uma a uma e nenhuma dispara cedo.

⚠️ **Cliente de plano não recebe NPS nem convite do Google.** Uma obra de
trilha `manutencao` na etapa 4 é a última da própria trilha, então
`obra_ativa()` devolve **true** — e sem trava a Tays receberia uma pesquisa
perguntando como foi a instalação que a **Eco Solar** fez. Desde 15/09
`obras_para_nps()` corta por `not coalesce(cliente_externo, false)` — e a
`nps_cobranca_google()`, a `pendencias_posvenda()` e a fila do `nps-resposta`
seguem o mesmo critério.

---

## 7. Parâmetros (tabela `config`)

Prefira criar parâmetro a chumbar número no código.

| Chave | Valor | O que faz |
|---|---|---|
| `economia_por_kwh` | **0,7968** | única fonte de economia. ⚠️ **PROVISÓRIO** — derivado de 0,73 × 1,0915 (reajuste CPFL de 22/04/2026), não de conta de luz. `tarifa_status()` devolve `provisorio: true`. Trocar assim que houver uma conta pós-abril: `select calibrar_tarifa(<valor>, '<de quem>')` |
| `conciliacao_automatica` | 1 | liga o casamento extrato ↔ parcela |
| `conciliacao_tolerancia` | 1,00 | diferença aceita em reais |
| `conciliacao_dias_max` | **30** | distância entre vencimento e data do banco. Era 90 até 16/09 — e os 18 casamentos feitos nunca usaram um dia sequer de folga, então 90 só permitia um pagamento de setembro alcançar a parcela de dezembro |
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
| `plano_endereco_adicional` | 200 | R$/ano por endereço além do primeiro no Completo — a visita técnica é em cada um |
| `autoleitura_ativo` | 1 | envio automático do lembrete de autoleitura (9h no dia, 18h na véspera) |
| `clima_cidade_base` | Araçatuba | onde o `clima_dia` é medido de verdade — é só **um** ponto |
| `clima_cidades` | Araçatuba | para quais cidades o clima vale. Usina fora da lista ganha aviso no card de aprovação em vez de um número que não é dela |

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

   Em 15/09 eu caí nisso **duas vezes seguidas** e quase não percebi. O padrão
   perigoso é mandar, no mesmo comando:

   ```sql
   do $do$ ... execute replace(definicao, velho, novo); end $do$;   -- DDL
   begin;  select minha_funcao(...);  rollback;                     -- teste
   ```

   O teste **passa** — dentro da transação a função já está corrigida — e o
   `rollback` no fim desfaz a correção junto. `get_ficha_cliente` perdeu três
   alterações assim (`papel`, `plano`, `autoleitura`) e `get_plano_visitas`
   perdeu uma, e as duas continuaram *parecendo* aplicadas porque o resultado
   do teste tinha sido verdadeiro.

   O que pegou: conferir **num comando separado**, depois, se o trecho novo
   está na `pg_get_functiondef`. Teste que roda junto com o DDL não prova
   nada sobre o que ficou gravado.
3. **Trigger adiado só age no commit** — `constraint trigger deferrable` não
   reflete dentro da mesma transação.
4. **CDN do GitHub leva ~3 min** — validar o arquivo publicado e esperar.
5. **Datalogger offline reporta zero** — significa "não medi", não "não gerou".
6. **Mês corrente nunca entra em comparação de desempenho.**
7. **`extrato_rateio.lancamento_id` é ON DELETE SET NULL** — por isso o trigger
   de desfazer é `deferrable`.
8. **Policy permissiva SOMA, não subtrai.** Uma policy `ALL` com
   `is_autorizado()` ao lado de uma `DELETE` com `is_admin()` não restringe o
   delete: vale `is_autorizado() OR is_admin()`. Foi assim em seis tabelas até
   12/09 — e eu corrigi cinco na primeira passada e esqueci a `obras`, a mais
   importante. Para restringir de verdade, o comando amplo tem de ser
   `select`/`insert`/`update` explícitos, sem `ALL`.

   Em 15/09 a `plano_contratos` recebeu o mesmo tratamento, agora que guarda
   dinheiro: apagar contrato virou `is_admin()`, e `select`/`insert`/`update`
   seguem em `is_autorizado()` — encerrar e cancelar são `update`, então a
   Lívia trabalha igual. **Medido, não deduzido:** a conta do financeiro apaga
   **0 linhas** e o contrato sobrevive; a de admin apaga 1.

   ⚠️ **Isso conserta uma tabela de cinquenta.** Outras 49 ainda têm o formato
   `ALL`, várias com dinheiro dentro — `dre_lancamentos`, `obra_parcelas`,
   `extrato_movimentos`, `obra_financeiro`, `cartao_faturas`. Não é que o
   sistema esteja errado: ele é permissivo por padrão, e apertar cada uma é
   decisão do Vitor, não varredura automática.
9. **RLS com policy só de leitura devolve sucesso sem gravar.** O `update` não
   altera nada e o PostgREST não acusa erro. Foi o bug do interruptor da régua.
   Hoje 17 tabelas têm esse formato, mas nenhuma tela grava direto nelas
   (conferido) — a escrita passa por função `security definer`. Antes de criar
   gravação direta numa tabela nova, confira se existe policy de escrita.
10. **Função nova precisa de DOIS revokes, não de um.** São duas concessões
    diferentes e cada uma exige o seu:
    - EXECUTE a **PUBLIC**, que inclui o anon — `revoke ... from anon` não
      tira essa, passa sem erro e não faz nada;
    - EXECUTE **direto ao `anon`**, que o Supabase dá a toda função nova por
      `alter default privileges` — e essa o `revoke ... from public` não tira.

    Em 15/09 apliquei só o revoke de `public` na
    `plano_registrar_pagamento` e conferi: `proacl` continuava com
    `anon=X/postgres` e `has_function_privilege('anon', ...)` era **true**.
    O certo é:

    ```sql
    revoke execute on function public.f(args) from public;
    revoke execute on function public.f(args) from anon;
    grant  execute on function public.f(args) to authenticated;
    ```

    Confira sempre pela ACL, não pelo comando ter passado. O gabarito são
    `calibrar_tarifa`, `ligar_automacao` e `regua_toggle`:
    `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
    — sem anon nenhum.

11. **Existem TRÊS caminhos para mudar a etapa, não dois.**
    Arrastar o card no kanban passa por `mudarEtapa()`, que chama o
    `notificar-grupo`. Trocar a etapa **dentro do card** e salvar passa por
    `salvarForm()`, que gravava `etapa_numero` junto com o resto do `rec` e
    **não avisava ninguém** — a tela dizia "Obra salva ✓" e a pessoa ia embora
    achando que o cliente tinha sido avisado. Quatro obras mudaram de etapa em
    15/09 sem nenhuma mensagem sair, e o log das edge functions foi o que
    provou: zero chamadas ao `notificar-grupo` nos horários das mudanças.
    Corrigido em 15/09. Antes de acrescentar efeito colateral a uma mudança de
    campo, **procure se o campo não é gravado por mais de um caminho**.

    ⚠️ **O terceiro caminho só apareceu em 17/09, e não é a tela: é o
    instalador.** A ação `enviar` do `foto-obra` (o instalador manda o
    relatório pelo `instalador_token`, sem login) faz
    `update obras set etapa_numero = ETAPA_POS_INSTALACAO` — **7, chumbado no
    código** — e avisa o cliente **ela mesma**, direto na Z-API, sem passar
    pelo `notificar-grupo`. Por isso um log com **zero chamadas ao
    `notificar-grupo`** não prova que ninguém foi avisado. Como não há JWT de
    usuário, a `fn_log_etapa` grava `por_usuario = 'sistema'` — é essa a
    assinatura desse caminho no `etapas_historico`.

    ⚠️ **E em obra de manutenção ele erra.** A trilha `manutencao` vai só até
    a etapa 4, então o `trg_valida_etapa` **clampa o 7 para 4** em silêncio
    (ele ajusta para a etapa válida mais próxima em vez de recusar). Mas a
    mensagem já foi montada buscando `etapas` com `numero = 7` **na trilha da
    obra** — que não existe —, então `proxNome` sai **string vazia** e o
    cliente lê *"Sua obra avançou para a etapa **."*. Pior: todo o texto é de
    instalação (*"Instalação concluída"*, *"finalizou a instalação do seu
    sistema"*, *"Relatório oficial da instalação"*) numa manutenção
    preventiva. Aconteceu de verdade em **17/09 13:01 BRT** com a **Fatima
    Rino e Antonio Monteiro (3067)**: `relatorio_enviado_em` 13:01:20, etapa
    2 → 4 às 13:01:28, oito segundos depois.

    **Corrigido em 18/09.** A etapa de destino agora sai da trilha:
    `min(7, maior etapa da trilha)` — **7** na padrão ("Vistoria e Conexão") e
    no eletroposto ("Comissionamento"), **4** na manutenção ("Concluída").
    Não é "a última da trilha": na padrão a última é a 8 ("Sistema Ativo!"),
    e mandar a obra para lá no fim da instalação dispararia NPS e convite do
    Google antes da vistoria — exatamente o que o §6 proíbe. Os textos
    passaram a seguir a trilha, e a frase da etapa **só sai se a etapa tiver
    nome**. Conferido fora do ar, trilha por trilha: padrão e eletroposto
    ficam idênticos ao que já faziam; só a manutenção muda.

    ⚠️ **O `foto-obra` não registra o que envia.** Não existe tabela de
    mensagens enviadas — só `mensagens_recebidas`. O que ele mandou só dá para
    ler no grupo do cliente ou deduzir do código.

12. **Cadastro parcial que devolve `ok: true` é pior que erro.** O cadastro de
    cliente de plano grava cliente, obra, usinas, vínculos e ficha, e só cria o
    contrato `if v_plano_cod is not null`. Sem plano escolhido, gravava tudo,
    dizia "Cadastrado ✓" e o cliente **não aparecia em lugar nenhum** — porque o
    painel de planos lê `from plano_contratos`. A pessoa vai embora achando que
    gravou. Duas lições: quando uma parte do cadastro é opcional, **a tela tem de
    dizer a consequência de pular** (o aviso cinza de "sem contrato por enquanto"
    não era lido), e **quem some de um painel precisa de um lugar onde aparece**.
    Antes de deixar um campo opcional, pergunte: sem ele, esse registro ainda é
    visível em alguma tela?

13. **Select fechado esconde a opção que a pessoa está procurando.** O
    formulário de contrato tinha "Cobrança" e "Duração" como `select`, abrindo
    em *Anual* e *12 meses*. O Vitor foi fechar uma cortesia de 6 meses, olhou a
    tela e disse que faltavam as duas coisas — elas estavam lá, dentro dos
    dropdowns fechados. Escolha de três ou quatro opções cabe na tela inteira,
    como `.chip`: a palavra aparece sem clicar, e no celular botão é mais fácil
    de acertar que select. O helper é `escolhas()` + `marcaEscolha()`, e o valor
    fica num `input hidden` para o resto do código não mudar. **Select só quando
    a lista é longa** — os 11 planos continuam em select, e está certo.

15. **Botão que escreve só no DOM morre no próximo render.** O "Puxar do
    extrato" preenchia os inputs e, na linha seguinte, chamava `renderFin()` —
    que redesenha a partir do `EDIT.fin` e jogava tudo fora. **O botão nunca
    funcionou**, desde que nasceu, e ninguém percebeu porque ele não dava erro:
    só não fazia nada. Provado no Chromium — `material_ca`, `instalacao` e `art`
    continuavam vazios depois do clique. Onde a tela tem um modelo em memória
    (`EDIT`, `FICHA`, `PLN`), **escrever no input não basta**: ou escreve nos
    dois, ou sincroniza o DOM para o modelo antes de qualquer redesenho. Aqui
    ficou `poeNoCampo()` e `sincronizaFicha()`.

16. **Zero gravado não é "custou zero", é "ninguém preencheu".** A ficha do
    Gilson tinha `0` em todos os campos de custo, e a tela mostrava `0` em cada
    um — o que lê como afirmação de que o item foi de graça. Campo zerado agora
    mostra o placeholder e salva `null`. Antes de exibir um número vindo do
    banco, pergunte se o zero dele é medição ou ausência (é a mesma lição da
    armadilha 5, do datalogger).

14. **Botão que só existe numa tela não existe para quem trabalha na outra.** O
    "Registrar 1º pagamento" morava só no card da obra, no `painel.html`. Quem
    cuida do pós-venda vivia no `posvenda.html`, via "aguardando o 1º pagamento"
    e não tinha o que fazer com a informação. Corrigido em 16/09. Quando uma tela
    **mostra** um estado que pede ação, ela precisa oferecer a ação.

17. **Tirar a aba não tira o código: deixa o botão órfão.** Em 10/09 a aba
    "Brindes" do `posvenda.html` saiu e a Lista absorveu só o **brinde a
    retirar**. O resto continuou no arquivo — `carregarBrindes`, `get_brindes`,
    o cartão "Sem avaliação no Google" e o `confirmarGoogle()` — atrás de um
    `if(VISAO==='brindes')` que **nenhum botão mais alcançava**. Sete dias sem
    nenhum caminho na tela para confirmar avaliação no Google ou dar baixa em
    brinde, e sem erro nenhum: o código parecia vivo. O `get_posvenda_lista` já
    devolvia `avaliou_google` por cliente esse tempo todo, e a tela nunca leu.
    Pior: `marcar_avaliou_google()` e `marcar_brinde_entregue()` pedem
    **voucher**, e promotor que não escolheu brinde não tem voucher — eram
    exatamente os **dois** casos pendentes em 17/09 (VALDETE, 4791, nota 10 pelo
    WhatsApp). Ou seja: mesmo que a aba voltasse, aqueles dois não dariam para
    confirmar. Corrigido em 17/09 pela **obra**, com `registrar_nps_manual`, que
    é coalesce-safe (só preenche o que está nulo, nunca desmarca — regra 3.6).
    Ao remover uma aba, **procure o `if(VISAO===...)` e o que só ele chamava**,
    e pergunte que ação some junto.

18. **Publicar edge function pelo MCP liga o `verify_jwt` de volta.** O
    parâmetro tem default `true`, e omitir não é "manter como estava" — é
    ligar. Em 17/09 eu republiquei a `alerta-pendencias` (que era `false`) sem
    passar o campo e ela voltou `true`. O cron chama sem header `Authorization`
    — só com o `cron_token` no corpo —, então o aviso das 8h da Lívia **passou
    a devolver 401** e ia sumir sem ninguém notar: cron job "succeeded", porque
    o `net.http_post` entrega e não olha a resposta. Peguei porque conferi na
    hora: `curl` sem auth devolvia **401**; com `verify_jwt` correto devolve
    **403 "Não autorizado."**, que é a trava da própria função respondendo.
    Toda função chamada por cron aqui é `verify_jwt: false` + `cron_token`.
    **Depois de publicar, confira o `verify_jwt` no retorno e bata um curl com
    token errado — tem de ser 403, nunca 401.**

---

## 10. Estado e pendências

**63 usinas ativas** · **55 normais, 4 sem comunicação, 4 sem dado** ·
**75 obras, 58 ativas** · 31 cron jobs, **todos ativos** · 22 chaves de
automação em `config`, 21 ligadas — a única desligada é `iptu_envio_ativo`,
de propósito (ver pendência abaixo). A `solarview_ativo` foi **removida** em
12/09: estava em 0, ninguém lia, e fazia parecer que o monitoramento estava
desligado enquanto ele entregava dado todo dia.

⚠️ **"Sem dado" não é o mesmo que "sem comunicação".** São as **4** usinas
com **zero registro** em `usina_dia` — elas existem aqui e **não existem no
SolarView**. São as duas do UNI AUTO POSTO (Clementina, 105,40 e 129,60 kWp,
cadastradas em 16/09) e as duas da Tays (açougue 29,25 e rancho 40,95), que a
pendência abaixo já cobre. Não é defeito: é cadastro que falta do outro lado.

As 4 sem comunicação não são iguais, e tratar como um número só esconde o que
importa:

| Usina | Situação | Vale agir? |
|---|---|---|
| Buritama 4,96 kWp | gerou ontem (17/09), medindo | não — é o normal do datalogger |
| **Araçatuba 6,20 kWp** (inst. 18/05) | **mede todo dia e não gera desde 22/08 — 27 dias** | **sim, é a mais urgente** |
| **Votuporanga 6,25 kWp** (inst. 24/04) | **55 dias de medição e NUNCA gerou nada** | **sim — nasceu muda há ~5 meses** |
| Araçatuba 8,68 kWp (inst. 27/07) | zero registro desde a instalação | sim — nunca comunicou |

⚠️ **As duas urgentes estão MEDINDO.** O doc dizia "sem medição há 21 dias"
para a Araçatuba de 6,20 — está errado, e a diferença importa: o datalogger
dela responde todo dia (última medição 17/09), o que ela não faz é **gerar**.
Não é a armadilha 5 (datalogger offline reportando zero); é usina parada de
verdade. O mesmo vale para a Votuporanga, que mede há 55 dias e nunca entregou
um kWh. Antes de classificar como "sem comunicação", **separe `ultima_medicao`
de `ultima_geracao`** — as duas saem de `usina_dia`, e confundir uma com a
outra transforma uma usina parada em "problema de sinal".

Conferido no banco em **18/09/2026**.

- [ ] **Importar o extrato anterior a agosto/2026.** O extrato começa em
      03/08. Maio, junho e julho têm zero lançamento vindo do banco — o que
      está neles é orçamento da ficha, não realizado. Comparar a margem de
      julho com a de agosto é comparar orçado com realizado. Bloqueante para
      análise de margem, e a causa é esta, não "faltam despesas": junho tem
      R$ 124.167 e julho R$ 120.328 lançados, só que pela ficha.
      **Também é isto que trava a ficha de ler o extrato sozinha:** 14 das 27
      obras com custo lançado fecharam antes de 03/08, então o realizado delas
      é parcial e a digitação manual ainda precisa existir.
      **E é o que trava os indicadores:** 34 das 52 obras fecharam antes de
      03/08, e por isso a execução × faturamento só vale para 3 delas.
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
- [ ] **EDVALDO MARCIO GONCALVES (4657): a 3ª e a 4ª parcela vencem no mesmo
      dia (15/11), as duas de R$ 1.500,00.** Cheira a erro de cadastro — e é
      o caso que faz a conciliação automática recusar o casamento. Enquanto
      não for corrigido, o pagamento dele cai na fila manual. A 5ª parcela
      (R$ 6.000, venc 01/09) também está marcada como recebida sem nenhum
      movimento no extrato; a obra fechou em 27/07, antes do extrato começar.
- [ ] **Quatro automações mensais nunca rodaram uma única vez.** Dia 2
      (fechamento), dia 5 (resumo mensal), dia 6 (marcos) e dia 10 (lembrete de
      tarifa) foram criadas em setembro **depois** da data delas, então a
      primeira chance real é em outubro. Não estão quebradas — estão por
      provar. Vale rodar cada uma em modo simular antes de outubro.
- [ ] **Registrar o 1º pagamento da TAYS VALESE DIAS DO PRADO.** Primeiro
      contrato pago do sistema: Completo anual, R$ 2.990,00, duas usinas
      instaladas pela **Eco Solar** (açougue em Araçatuba 29,25 kWp, rancho em
      Birigui 40,95 kWp — o rancho manda os créditos para o açougue). Está em
      `aguardando_pagamento`, sem início nem fim. Quando o dinheiro entrar,
      botão "Registrar 1º pagamento" no card da obra. Aí vira **R$ 249,17 de
      receita mensal**, o primeiro número diferente de zero desse painel.
      As duas usinas ainda **não estão no SolarView** — o Vitor vai cadastrar,
      e o vínculo é manual porque ela não tem número de contrato no nome.
      O aniversário (31/10) ficou só em `clientes`, fora de `obras`, para a
      automação de aniversário não mandar texto de cliente de instalação.
- [ ] **Decidir se o aviso de fim de cortesia passa por aprovação humana.**
      A `plano-vencimento` envia direto ao cliente às 9h, e agora com preço e
      oferta dentro. Tem folga para decidir: o primeiro vencimento é
      **17/04/2027**, e nenhum contrato tem `aviso_30_em` preenchido.
- [ ] **Tirar o número chumbado de três chaves da `config`.** A decisão do
      Vitor é endereçar por **papel**, para que trocar a pessoa do pós-venda
      seja só trocar o número. O aviso de vínculo já faz isso
      (`solarview-vincular` → `resp_posvenda`), e também a `conferencia-diaria`,
      a `autoleitura-aviso` e a `plano-vencimento` (essa por `resp_alertas`).
      Mas `alerta_destinos`, `alerta_credito_destinos` e `grupo_fixos` guardam
      **número**, não papel — conferido cruzando contra `equipe.telefone`: são
      a Lívia (...2573) e o Vitor (...2812). Se a Lívia sair, trocar a `equipe`
      **não muda essas três**. Nenhuma função do banco e nenhuma tela as lê —
      só edge function (`alerta-prazos` lê `alerta_destinos`). Mudar quem
      recebe alerta é decisão do Vitor, não varredura.
- [ ] **Não existe tela para trocar o responsável.** `definir_responsavel(equipe,
      funcao)` existe, é `is_admin()` e funciona — mas nenhuma tela chama.
      Hoje a troca só acontece pelo banco, na mão.
- [ ] **Duas mensagens de `geracao_baixa` paradas desde 18/09 e já vencidas.**
      Jaqueline (Guarulhos) e Marcia (Araçariguama): as duas usinas voltaram ao
      padrão sozinhas (78% e 75%, `caiu = false` em 21/09). O card agora avisa
      em vermelho; **recusar** é o desfecho certo, mas é clique da Lívia.
- [ ] **Um ponto de clima só, e vizinhança num balde único.** Enquanto
      `clima_dia` tiver apenas Araçatuba e `v_indice_regiao` juntar 18 cidades
      em `regiao`, todo aviso de geração baixa fora do interior nasce com
      ressalva. O caminho é uma coluna de cidade em `clima_dia` + uma chamada
      de Open-Meteo por cidade com usina — não é urgente enquanto forem 2 casos.
- [ ] Ligar proteção de senha vazada no Supabase
- [ ] **Prospecção de sistema órfão, se virar rotina.** A aba "Cliente de fora"
      foi removida em 15/09: ela gerava um texto de abordagem e **não gravava
      nada** — nenhum `insert`, nenhum envio, só copiar. Sem registro de quem
      foi abordado não havia o que mostrar, e por isso parecia parada. A ideia
      é boa (a Tays é justamente um cliente de fora que converteu), mas a
      versão certa guarda o prospect — nome, porte, quando foi abordado, o que
      respondeu — e desemboca no cadastro de cliente de plano. O texto antigo
      está no git.
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
