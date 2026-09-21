-- 21/09/2026 — O clima aparece junto da mensagem de geração baixa.
--
-- Pedido do Vitor: "às vezes a geração está baixa por causa da chuva — o banco
-- consegue se comunicar com a previsão do tempo?"
--
-- Consegue, e já se comunica. O que faltava era isso APARECER para quem aprova.
--
-- Como a regra já trata chuva hoje (`queda_geracao`):
--   · ela lê `usina_dias(usina, 21)`, que já cruza `clima_dia` e o índice da
--     vizinhança (`v_indice_regiao`);
--   · **descarta o dia inteiro quando o índice da vizinhança fica <= 1,5** —
--     ou seja, dia em que os vizinhos também geraram mal (chuva, frente fria)
--     não entra na conta;
--   · e compara pela `razao`, que já é a usina CONTRA os vizinhos daquele dia.
--
-- Por isso "gerando 72% do padrão dela em 10 dias de sol" não é chuva: os dias
-- de chuva já saíram. Só que o card de aprovação não dizia isso, e quem lê
-- tinha de confiar às cegas.
--
-- ⚠️ E existe um furo real, que este contexto expõe em vez de esconder.
-- O clima vem de UM ponto só (`clima_lat`/`clima_lon`, default Araçatuba) e o
-- índice da vizinhança só separa cidade com 5+ usinas — hoje só Araçatuba.
-- Todas as outras 18 cidades caem num balde único chamado `regiao`. Para uma
-- usina de Guarulhos ou Araçariguama isso significa que:
--   · o clima que temos é de outro lugar, a ~500 km;
--   · e o índice que decide o descarte é puxado pelo interior — se chove lá e
--     faz sol aqui, o dia NÃO é descartado e a razão dela cai sem culpa.
-- As duas mensagens paradas em 18/09 são exatamente desses dois casos.
--
-- `geracao_contexto()` devolve tudo isso junto, inclusive o aviso de quando a
-- comparação é fraca. Ela não muda nenhum critério — só mostra o que sustenta
-- o aviso.

-- de onde o clima é medido, e para quais cidades ele vale (§7: parâmetro, não
-- número chumbado). Cidade fora da lista ganha aviso no card.
insert into config (chave, valor) values
  ('clima_cidade_base', 'Araçatuba'),
  ('clima_cidades', 'Araçatuba, Bilac, Birigui, Promissão, Sabino, Clementina, Guaiçara, Buritama, Coroados, Penápolis, Pereira Barreto, Santo Antônio do Aracanguá, José Bonifácio')
on conflict (chave) do nothing;

create or replace function public.geracao_contexto(p_usina uuid)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_cidade text; v_base text; v_lista text; v_vale boolean;
  d record; q record;
begin
  if not public.is_autorizado() then return null; end if;

  select u.cidade into v_cidade from usinas u where u.id = p_usina;
  select valor into v_base  from config where chave = 'clima_cidade_base';
  select valor into v_lista from config where chave = 'clima_cidades';
  v_base := coalesce(v_base, 'Araçatuba');

  -- a cidade da usina está na lista que o clima cobre?
  v_vale := coalesce(v_cidade, '') <> '' and exists (
    select 1 from unnest(string_to_array(coalesce(v_lista, v_base), ',')) c
    where lower(btrim(c)) = lower(btrim(v_cidade)));

  -- os mesmos 21 dias que a queda_geracao olha
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

  -- o veredito que a regra já calculou, para o card não recalcular nada
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

revoke execute on function public.geracao_contexto(uuid) from public;
revoke execute on function public.geracao_contexto(uuid) from anon;
grant  execute on function public.geracao_contexto(uuid) to authenticated;
