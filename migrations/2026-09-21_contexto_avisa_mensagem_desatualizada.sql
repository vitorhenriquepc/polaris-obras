-- 21/09/2026 — O card de aprovação passa a mostrar o contexto, e a avisar
-- quando a mensagem já ficou velha.
--
-- Continuação direta da migração anterior do mesmo dia
-- (2026-09-21_clima_no_card_de_aprovacao.sql), que criou `geracao_contexto()`.
-- Faltavam duas coisas: ligar a função no que a tela lê, e responder a
-- pergunta que nem tínhamos feito ainda — "isso ainda é verdade hoje?".
--
-- ⚠️ ACHADO QUE MOTIVOU ESTA MIGRAÇÃO.
-- As duas mensagens de `geracao_baixa` paradas na fila desde 18/09 **não são
-- mais verdade**. Medido em 21/09, com `queda_geracao`:
--
--   · Jaqueline (Guarulhos):      73% → 78%, `caiu = false`
--   · Marcia (Araçariguama):      72% → 75%, `caiu = false`
--
-- As duas usinas voltaram ao padrão sozinhas enquanto o texto esperava
-- aprovação. Se a Lívia clicasse "Aprovar" hoje, mandaria aviso de geração
-- baixa para duas clientes cujo problema acabou. Nada na tela dizia isso: o
-- card mostra o texto escrito no dia 18 e mais nada.
--
-- Por isso `geracao_contexto` ganha `ainda_caida` (o `caiu` de AGORA, não o de
-- quando a IA escreveu) e a tela pinta de vermelho quando ele é `false`.
--
-- Nada aqui bloqueia o envio — regra 3.5: quem decide é a pessoa. O que muda é
-- que ela decide vendo.

-- ── 1. geracao_contexto: acrescenta `ainda_caida` ────────────────────────────
-- (recriada por inteiro; é a definição corrente, com o único acréscimo sendo
--  a chave `ainda_caida`)

CREATE OR REPLACE FUNCTION public.geracao_contexto(p_usina uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cidade text; v_base text; v_lista text; v_vale boolean;
  d record; q record;
begin
  if not public.is_autorizado() then return null; end if;

  select u.cidade into v_cidade from usinas u where u.id = p_usina;
  select valor into v_base  from config where chave = 'clima_cidade_base';
  select valor into v_lista from config where chave = 'clima_cidades';
  v_base := coalesce(v_base, 'Araçatuba');

  v_vale := coalesce(v_cidade, '') <> '' and exists (
    select 1 from unnest(string_to_array(coalesce(v_lista, v_base), ',')) c
    where lower(btrim(c)) = lower(btrim(v_cidade)));

  select
    count(*) filter (where x.razao is not null and not x.sem_medicao
                       and coalesce(x.indice,0) > 1.5)                as usados,
    count(*) filter (where coalesce(x.indice,0) <= 1.5)               as descartados,
    count(*) filter (where x.sem_medicao)                             as sem_medicao,
    round(sum(x.chuva_mm), 1)                                         as chuva_mm,
    round(avg(x.sol_horas), 1)                                        as sol_h,
    count(*) filter (where x.chuva_mm >= 1)                           as dias_chuva,
    (array_agg(distinct x.base_usada))[1]                             as base
  into d
  from usina_dias(p_usina, 21) x;

  select * into q from queda_geracao(p_usina);

  return json_build_object(
    'dias_usados',      coalesce(d.usados, 0),
    'dias_descartados', coalesce(d.descartados, 0),
    'sem_medicao',      coalesce(d.sem_medicao, 0),
    'chuva_mm',         d.chuva_mm,
    'sol_horas_media',  d.sol_h,
    'dias_com_chuva',   coalesce(d.dias_chuva, 0),
    'razao_media',      q.razao_recente,
    'motivo',           q.motivo,
    -- o estado de AGORA. A mensagem foi escrita num dia e pode estar parada na
    -- fila há dias; se a usina já voltou ao normal, aprovar manda um alerta
    -- para cliente cujo problema acabou.
    'ainda_caida',      coalesce(q.caiu, false),
    'base_comparacao',  d.base,
    'clima_medido_em',  v_base,
    'usina_cidade',     v_cidade,
    'clima_vale',       v_vale,
    'aviso', case
      when not v_vale then
        'O clima acima é medido em ' || v_base || ', e esta usina fica em ' ||
        coalesce(v_cidade, 'cidade não informada') ||
        '. Não vale para ela — e o descarte de dias de chuva também não, porque ' ||
        'a vizinhança usada na comparação é o interior.'
      when d.base = 'regiao' then
        'A comparação usa o balde "regiao" (todas as cidades com menos de 5 usinas ' ||
        'juntas), então é mais frouxa que a de Araçatuba.'
      else null end
  );
end; $function$;

-- ── 2. get_regua_aprovacoes: devolve o contexto junto ────────────────────────
-- Só para contato que tem `usina_id`. Modelo que não é de usina (boas-vindas,
-- aniversário) continua sem contexto, e a tela não desenha nada.

CREATE OR REPLACE FUNCTION public.get_regua_aprovacoes()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(json_build_object(
    'id', c.id, 'modelo', c.modelo, 'nome_modelo', m.nome,
    'cliente', o.cliente, 'contrato', o.contrato, 'obra_id', o.id, 'usina_id', c.usina_id,
    'texto', coalesce(c.texto_custom, regua_texto(c.obra_id, c.modelo)),
    'motivo', c.bloqueio_motivo,
    'programada', c.data_programada,
    -- o que sustenta o aviso, para quem aprova não decidir às cegas:
    -- dias usados, dias de chuva descartados, o clima e o estado de agora
    'contexto', case when c.usina_id is not null
                     then public.geracao_contexto(c.usina_id) end,
    'bloqueio', case when o.whatsapp_grupo_id is null then 'esta obra não tem grupo no WhatsApp'
                     when o.optout_em is not null then 'este cliente pediu para sair'
                     else null end
  ) order by c.criado_em),'[]'::json) into v
  from regua_contatos c
  join regua_modelos m on m.codigo=c.modelo
  join obras o on o.id=c.obra_id
  where c.status='pendente' and c.status_aprovacao='aguardando';
  return v;
end $function$;

-- ── 3. Conferência ───────────────────────────────────────────────────────────
-- Armadilha 2: o `pg_get_functiondef` tem de ser conferido num comando
-- SEPARADO, depois. Conferido em 21/09:
--   `ainda_caida`      presente em geracao_contexto        → true
--   `geracao_contexto` presente em get_regua_aprovacoes    → true
--   chave `'contexto'` presente em get_regua_aprovacoes    → true
--
-- Saída real para as duas mensagens paradas (com claims de e-mail autorizado,
-- dentro de begin/rollback, sem gravar nada):
--   Jaqueline: ainda_caida false · motivo "dentro do padrao dela (78%)"
--              clima_vale false · usina_cidade Guarulhos · base_comparacao regiao
--   Marcia:    ainda_caida false · motivo "dentro do padrao dela (75%)"
--              clima_vale false · usina_cidade Araçariguama · base_comparacao regiao
