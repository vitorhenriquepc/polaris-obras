-- 22/09/2026 — A régua voltou a ser gerada. Duas falhas, e uma era minha.
--
-- ⚠️ O VITOR PERGUNTOU: *"quando o sistema entra ativo, ele já está fazendo
-- tudo e jogando direto para o pós-venda?"*. Fui medir na CELIA REGINA (4133),
-- que entrou na etapa 8 hoje às 16:40, e ela estava com **zero régua**.
-- Puxando o fio apareceram DUAS falhas, e elas estavam **se escondendo uma
-- atrás da outra**.
--
-- ── FALHA 1: o segundo caminho da etapa não preenche `data_conclusao` ────────
--
-- `trg_gerar_regua` exige `etapa_numero >= 8` **E** `data_conclusao is not
-- null`. Faltando a data, o trigger simplesmente não roda — e a obra fica
-- **sem régua nenhuma, para sempre**, sem erro em lugar nenhum.
--
-- `mudarEtapa()` (arrastar no kanban, ou o select do topo do card) preenchia a
-- data. O `salvarForm()` — trocar a etapa **dentro** do formulário e salvar —
-- não preenchia: ele grava `data_conclusao` a partir do campo de data, que
-- está vazio.
--
-- É a armadilha 11 de novo, e desta vez pelo conserto dela. Em 15/09 eu levei
-- o **aviso ao cliente** para o `salvarForm()` e deixei o **efeito de dado**
-- para trás. O comentário que escrevi lá dizia *"avisa o cliente igual a
-- arrastar no kanban"* — igual só no aviso.
--
-- Corrigido no `painel.html`: os dois caminhos passam por `dataDeConclusao()`,
-- e o número da etapa virou `ETAPA_CONCLUSAO`, uma constante só.
--
-- ── FALHA 2: eu quebrei a `gerar_regua` hoje de manhã ────────────────────────
--
-- A migração `2026-09-22_regua_modelo_de_evento_pode_repetir.sql` trocou o
-- índice `UNIQUE (obra_id, modelo)` por um **parcial**:
--
--   regua_contatos_uma_por_obra ... (obra_id, modelo) WHERE (NOT repetivel)
--
-- e a `gerar_regua` ficou com a inferência velha, `on conflict (obra_id,
-- modelo)`. O Postgres **não casa** isso com um índice parcial:
--
--   ERROR: there is no unique or exclusion constraint matching the
--          ON CONFLICT specification
--
-- Levantado de dentro do trigger, o erro **aborta o UPDATE da obra inteiro**.
-- Ou seja: a primeira obra a chegar na etapa 8 com `data_conclusao` preenchida
-- daria erro na cara da pessoa, e a etapa não salvaria.
--
-- ⚠️ **As duas falhas se mascararam.** A CELIA passou justamente porque a
-- falha 1 deixou a data nula, então a falha 2 nunca foi alcançada. Se eu
-- tivesse corrigido só o `painel.html`, teria trocado uma falha silenciosa por
-- uma falha dura em toda ativação. Foi a simulação que pegou isso — o
-- `begin/rollback` explodiu antes de qualquer tela ver.
--
-- Nenhuma outra obra foi atingida: a CELIA é a única com etapa >= 8 e
-- `data_conclusao` nula, e nenhuma outra tentou ativar entre a migração da
-- manhã e esta.

CREATE OR REPLACE FUNCTION public.gerar_regua(p_obra uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_obra record; v_m record; v_criados int := 0; v_base date;
begin
  select * into v_obra from obras where id = p_obra;
  if not found then return json_build_object('erro','Obra não encontrada'); end if;
  if v_obra.etapa_numero < 8 or v_obra.data_conclusao is null then
    return json_build_object('erro','Obra ainda não está ativa');
  end if;

  v_base := v_obra.data_conclusao;

  for v_m in select * from regua_modelos where ativo and dia > 0 order by ordem loop
    -- O ON CONFLICT precisa do MESMO predicado do indice. Em 22/09 o indice
    -- `UNIQUE (obra_id, modelo)` virou PARCIAL (`where not repetivel`), para o
    -- modelo de evento poder repetir -- e esta funcao ficou com a inferencia
    -- velha, que o Postgres nao consegue casar com indice parcial. Resultado:
    -- `there is no unique or exclusion constraint matching the ON CONFLICT
    -- specification`, levantado de dentro do trigger, o que ABORTA o update da
    -- obra inteiro. Os 8 modelos que entram aqui sao todos de calendario e
    -- `repetivel = false`, e o trigger que carimba a coluna e BEFORE INSERT,
    -- entao o predicado ja vale na hora do conflito.
    insert into regua_contatos (obra_id, modelo, data_programada, data_limite)
    values (p_obra, v_m.codigo, v_base + v_m.dia, v_base + v_m.dia + v_m.janela_dias)
    on conflict (obra_id, modelo) where not repetivel do nothing;
    if found then v_criados := v_criados + 1; end if;
  end loop;

  return json_build_object('ok', true, 'criados', v_criados, 'base', v_base);
end; $function$;

-- ── Correção da CELIA (aplicada) ─────────────────────────────────────────────
-- A data veio de `obra_ativa_em()`, que lê o `etapas_historico` — não foi
-- inventada (regra 3.1). Nada foi apagado (regra 3.6).
--
--   update obras set data_conclusao = obra_ativa_em(id)::date
--    where id = '12994b0f-3522-48ef-a74c-f10bdef5c7bd' and data_conclusao is null;
--
-- O próprio trigger gerou as 8 mensagens, de `d2_boasvindas` em 24/09 a
-- `d365_aniversario` em 22/09/2027.

-- ── Conferência ──────────────────────────────────────────────────────────────
-- Armadilha 2: tudo conferido DEPOIS do DDL, em comandos separados.
--
--   · simulação na CELIA, em begin/rollback: 8 linhas criadas, e a chamada
--     explícita logo depois do trigger NÃO duplicou nenhuma (idempotente)
--   · caminho novo, numa obra de etapa 7 em begin/rollback:
--     `update obras set etapa_numero=8, data_conclusao=current_date`
--     → 8 linhas de régua, sem erro. Antes desta migração, esse mesmo update
--       levantava o erro do ON CONFLICT e desfazia a etapa junto.
