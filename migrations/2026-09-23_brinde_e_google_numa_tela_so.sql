-- 23/09/2026 — Brinde e Google numa tela só, lida direto da tabela `nps`.
--
-- ⚠️ O VITOR: *"ainda estou tendo dificuldade para identificar quem já avaliou
-- e quem já recebeu o brinde"*, e *"a lista não está puxando as informações
-- corretas"*. As duas queixas se confirmaram, por motivos diferentes.
--
-- ── 1. A Lista não via quem estava em obra de manutenção ─────────────────────
-- `get_posvenda_lista` só devolve obra com `etapa_numero >= 8` (ou com mensagem
-- pendente). Obra de manutenção vai só até a etapa 4. Medido em 23/09:
--
--   · promotores sem avaliar no Google, no banco ........ 2
--   · o chip "Google pendente" da Lista contava ......... 0
--
-- Os dois são **Fatima Rino (3067)** e **Jose Antonio Bassetto**, nota 10, os
-- dois em obra de manutenção — invisíveis para o filtro. É a mesma família das
-- armadilhas 11, 20 e 21: um `>= 8` escrito à mão onde a regra certa é "chegou
-- na última etapa da própria trilha".
--
-- ── 2. 41 dos 52 brindes "entregues" não têm data de retirada ────────────────
--
--   · brindes marcados como entregues ....................... 52
--   · `entregue_em = brinde_em` AO MILISSEGUNDO ................ 41
--   · desses, também = `avaliou_google_em` ..................... 40
--   · com data de retirada própria ............................. 11
--
-- Os 41 foram marcados no mesmo instante em que o brinde foi escolhido — o
-- cadastro retroativo de 08/08, 14/08 e 02/09 carimbou escolha, avaliação e
-- entrega de uma vez. Isso **não é data de retirada**, e a tela antiga
-- mostrava as duas coisas igual: "✓ copo entregue". Por isso ninguém consegue
-- confiar no "já recebeu".
--
-- O dado **não foi alterado** (regra 3.6 — e só quem entregou sabe a verdade).
-- A função passa a devolver `entregue_no_cadastro`, e a tela diz "marcado
-- entregue no cadastro de DD/MM · sem data de retirada" em vez de afirmar uma
-- retirada que ninguém registrou.
--
-- ── O que muda ──────────────────────────────────────────────────────────────
-- `get_brinde_google()` lê de `nps`, não da lista de clientes: quem respondeu a
-- pesquisa aparece qualquer que seja a etapa. Devolve o resumo (avaliaram,
-- faltam avaliar, entregues, marcados no cadastro, a retirar, não escolheu) e
-- uma linha por cliente, com o pendente primeiro.
--
-- Na tela, os três chips soltos da Lista ("Brinde a retirar", "Google
-- pendente", "Brinde entregue") viram UM: "🎁⭐ Brinde e Google".

CREATE OR REPLACE FUNCTION public.get_brinde_google()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nivel text; v_eq uuid;
begin
  v_nivel := public.meu_nivel();
  if v_nivel = 'nenhum' then return null; end if;
  v_eq := public.minha_equipe_id();

  -- Le da tabela `nps`, e NAO da lista de clientes. A lista corta em
  -- `etapa_numero >= 8`, e obra de manutencao vai so ate a etapa 4: por isso
  -- em 23/09 o filtro "Google pendente" contava ZERO enquanto havia DOIS
  -- promotores sem avaliar (Bassetto e Fatima, os dois em manutencao).
  -- Quem respondeu a pesquisa aparece aqui, qualquer que seja a etapa.
  --
  -- `entregue_no_cadastro`: 41 dos 52 brindes "entregues" em 23/09 tem
  -- `entregue_em = brinde_em` ao milissegundo -- foram marcados no mesmo
  -- instante em que o brinde foi escolhido, quase todos no cadastro
  -- retroativo de 08/08, 14/08 e 02/09. Isso NAO e data de retirada. O dado
  -- nao e corrigido aqui (regra 3.6, e ninguem sabe a verdade sem conferir);
  -- a tela so deixa de apresentar os dois casos como se fossem iguais.
  return (
    with base as (
      select o.id as obra_id, o.cliente, o.contrato, o.cidade,
             (o.whatsapp_grupo_id is not null) as tem_grupo,
             n.nota, n.criado_em as respondeu_em, n.origem,
             n.avaliou_google_em, n.avaliou_origem,
             coalesce(n.lembretes_google,0) as lembretes_google, n.lembrete_google_em,
             n.brinde, n.voucher, n.brinde_em, n.entregue_em,
             (n.entregue_em is not null and n.entregue_em = n.brinde_em) as entregue_no_cadastro,
             (n.nota >= 9 and n.avaliou_google_em is null)                as google_pendente,
             (n.brinde is not null and n.entregue_em is null)              as brinde_pendente
        from nps n join obras o on o.id = n.obra_id
       where (n.nota >= 9 or n.brinde is not null)
         and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)
    )
    select json_build_object(
      'pode_agir', public.pode_agir_posvenda(),
      'resumo', (select json_build_object(
          'promotores',      count(*) filter (where nota >= 9),
          'avaliaram',       count(*) filter (where nota >= 9 and avaliou_google_em is not null),
          'google_pendente', count(*) filter (where google_pendente),
          'escolheram',      count(*) filter (where brinde is not null),
          'entregues',       count(*) filter (where brinde is not null and entregue_em is not null),
          'entregue_no_cadastro', count(*) filter (where brinde is not null and entregue_no_cadastro),
          'a_retirar',       count(*) filter (where brinde_pendente),
          'nao_escolheu',    count(*) filter (where nota >= 9 and brinde is null)
        ) from base),
      'linhas', (select coalesce(json_agg(json_build_object(
          'obra_id', obra_id, 'cliente', cliente, 'contrato', contrato, 'cidade', cidade,
          'tem_grupo', tem_grupo, 'nota', nota, 'respondeu_em', respondeu_em, 'origem', origem,
          'avaliou_google_em', avaliou_google_em, 'avaliou_origem', avaliou_origem,
          'lembretes_google', lembretes_google, 'lembrete_google_em', lembrete_google_em,
          'brinde', brinde, 'voucher', voucher, 'brinde_em', brinde_em, 'entregue_em', entregue_em,
          'entregue_no_cadastro', entregue_no_cadastro,
          'google_pendente', google_pendente, 'brinde_pendente', brinde_pendente)
          order by (google_pendente or brinde_pendente) desc, cliente), '[]'::json) from base)
    )
  );
end $function$;

-- Armadilha 10: os DOIS revokes.
revoke execute on function public.get_brinde_google() from public;
revoke execute on function public.get_brinde_google() from anon;
grant  execute on function public.get_brinde_google() to authenticated;

-- ── Conferência (23/09, em comandos separados do DDL) ───────────────────────
--   ACL → {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   has_function_privilege('anon', ...) → false
--   resumo real → promotores 55 · avaliaram 53 · google_pendente 2 ·
--                 escolheram 52 · entregues 52 · entregue_no_cadastro 41 ·
--                 a_retirar 0 · nao_escolheu 3
--   as 2 pendentes → Fatima Rino (3067) e Jose Antonio Bassetto
--
-- A tela foi aberta no Chromium com o Supabase trocado por um dublê que
-- devolve estes dados: 23 verificações, nenhuma falha, nenhum erro de JS.
