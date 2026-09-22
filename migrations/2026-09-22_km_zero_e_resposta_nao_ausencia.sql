-- 22/09/2026 — Km zero é resposta, não ausência.
--
-- ⚠️ ACHADO QUE MOTIVOU ESTA MIGRAÇÃO.
-- O Vitor: *"tem clientes que são de Araçatuba que a gente não coloca KM,
-- porque o KM é zerado, para não gerar uma trava"*. A obra é na própria
-- cidade — a distância dela **é** zero. Mas o teste era:
--
--   coalesce(v_km,0) <= 0   →  falta 'distância em km'
--
-- ou seja, **o zero era lido como "ninguém preencheu"**, e a única saída era
-- deixar o campo em branco. A trava que existia para cobrar o preenchimento
-- estava produzindo exatamente o buraco que queria evitar.
--
-- **Medido em 22/09, no banco:**
--
--   · obras com `distancia_km = 0`    → **ZERO**  (a trava nunca deixou gravar uma)
--   · obras com `distancia_km` nulo   → 57
--   · dessas, de Araçatuba            → **30**
--
-- Trinta obras sem km onde o km é conhecido e vale zero. O número da pendência
-- do §10 ("58 sem km") nunca foi só desleixo: mais da metade é esta trava.
--
-- É a armadilha 16 ao contrário. Lá o zero **exibido** virava afirmação ("este
-- item custou zero"); aqui o zero **digitado** virava ausência. A pergunta é a
-- mesma nos dois casos: *este zero é medição ou é silêncio?* Para distância,
-- é medição.
--
-- Negativo continua recusado: não existe distância negativa.
--
-- ⚠️ **O mesmo defeito estava em mais DOIS lugares, na tela** (corrigidos no
-- `painel.html`, no mesmo commit) — e nenhum deles dava erro, só não deixava:
--
--   1. a lista de campos obrigatórios do `salvarForm()` testava
--      `parseFloat(v) > 0`, então digitar 0 pintava o campo de vermelho;
--   2. `distancia_km: parseFloat(...) || null` — **`0 || null` é `null`**.
--      Mesmo se os outros dois passassem, o zero seria gravado como nulo.
--
-- Três camadas cometendo o mesmo erro. Consertar uma só teria dado a impressão
-- de resolvido sem resolver: a tela seguiria recusando, ou gravando nulo em
-- silêncio.

CREATE OR REPLACE FUNCTION public.trava_campos_financeiro()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare faltam text[] := array[]::text[]; v_km numeric; v_valor numeric;
begin
  -- reflexo do valor digitado na obra nao e edicao da ficha: nao exige nada
  if coalesce(current_setting('app.espelhando', true),'') = '1' then return new; end if;
  if coalesce(new.dispensado,false) then return new; end if;

  select distancia_km, valor_projeto into v_km, v_valor from obras where id = new.obra_id;
  if exists (select 1 from campos_obrigatorios where campo='preco_negociado' and ativo)
     and coalesce(new.preco_negociado,0) <= 0 and coalesce(v_valor,0) <= 0
     then faltam := faltam || array['valor do projeto']; end if;

  -- ZERO E RESPOSTA, NAO AUSENCIA. Obra em Aracatuba tem distancia zero: e na
  -- propria cidade. O teste antigo lia o zero como "ninguem preencheu" e
  -- travava o salvamento -- e por isso havia ZERO obras com km = 0 no banco.
  -- Negativo continua recusado, porque nao existe distancia negativa.
  if exists (select 1 from campos_obrigatorios where campo='distancia_km' and ativo)
     and (v_km is null or v_km < 0) then faltam := faltam || array['distância em km']; end if;

  if array_length(faltam,1) > 0 then
    raise exception 'Para salvar, preencha: %', array_to_string(faltam, ', ') using errcode='P0001';
  end if;
  return new;
end $function$;

-- ── Conferência ──────────────────────────────────────────────────────────────
-- Armadilha 2: conferido DEPOIS do DDL, em comando separado, e pelo
-- comportamento — não por `pg_get_functiondef like ...`, que dava falso
-- positivo porque o comentário acima cita o teste antigo.
--
-- Numa obra real de Araçatuba, tudo dentro de begin/rollback, nada gravado:
--
--   km = 0        → PASSOU, a ficha salvou
--   km nulo       → recusado: "Para salvar, preencha: distância em km"
--   km negativo   → recusado: "Para salvar, preencha: distância em km"
