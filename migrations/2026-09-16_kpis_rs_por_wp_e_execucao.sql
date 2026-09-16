-- As recomendacoes da auditoria, construidas. E uma delas NAO construida.
--
-- MEDI ANTES DE CONSTRUIR, porque KPI em cima de dado faltando e numero
-- inventado (regra 3.1). Das 52 obras de venda:
--
--   R$/Wp .... 50 tem potencia E preco .................. 96%  -> construido
--   Execucao . 3 tem os dois lados confiaveis ............  6%  -> construido, com a cobertura na cara
--   DSO ...... 16 tem parcelas, extrato de 5 semanas ..... -    -> NAO construido
--
-- 1. TOLERANCIA DA CONCILIACAO: 90 -> 30 DIAS
--    Os 18 casamentos feitos ate aqui tiveram TODOS diferenca de R$ 0,00 e
--    0 dias. A folga de 90 dias nunca foi usada, e era ela que permitia um
--    pagamento de setembro alcancar a parcela de dezembro. Trinta dias mantem
--    um mes inteiro de atraso e para de alcancar a parcela do mes seguinte.
--      update config set valor='30' where chave='conciliacao_dias_max';
--    A tolerancia em reais (R$ 1,00) ficou, e para arredondamento.
--
-- 2. R$/Wp -- a metrica que compara com o mercado
--    Margem em reais nao compara com ninguem. Levantamentos de 2026 poem o
--    residencial brasileiro entre R$ 3,50 e 5,50 por Wp instalado.
--    A mediana da casa hoje e R$ 2,54/Wp (R$ 2.540 por kWp), com a tendencia
--    dos proprios meses sendo o que importa acompanhar -- escopo e regiao
--    mudam demais o numero de mercado para ele virar meta.
--
-- 3. EXECUCAO x FATURAMENTO (WIP, custo-a-custo)
--    Avanco medido por custo incorrido sobre custo estimado, comparado com o
--    quanto ja foi cobrado. Positivo = cobrou adiantado.
--
--    A PRIMEIRA VERSAO MENTIA e eu joguei fora: devolvia "1847% executado"
--    para a Zuleica (4618), porque a ficha dela tinha R$ 661,83 de custo
--    estimado contra R$ 12.229,80 de gasto real. Nao e obra 18 vezes pronta,
--    e a estimativa que nao existe. E o `ja_recebido` sai do extrato, que
--    comeca em 03/08 -- obra anterior aparecia com 0% faturado mesmo tendo
--    recebido, e o desvio saia invertido.
--
--    Agora exige os DOIS lados confiaveis: estimativa de pelo menos 30% do
--    preco (obra solar custa 60-75%; "estimativa" de 4% e campo em branco) E
--    obra fechada dentro da janela do extrato. Sobram 3 de 52 -- e a funcao
--    diz isso na cara, com o bloco `o_que_falta`, que e a parte acionavel:
--      34 fecharam antes de 03/08 (e o extrato antigo que falta importar)
--      27 sem gasto classificado · 20 sem estimativa · 5 com estimativa furada
--
-- 4. DSO -- NAO CONSTRUIDO, de proposito
--    So 16 das 52 obras tem parcelas, e o extrato cobre 5 semanas. O numero
--    sairia com cara de autoridade e sem lastro. Nasce sozinho quando o
--    extrato anterior a agosto entrar (pendencia do §10).
--
-- O QUE A CONSTRUCAO ACHOU DE QUEBRA
-- ----------------------------------
-- O THALES (4695) estava com preco de R$ 14,00 numa obra de R$ 14.000,00 --
-- erro de mil. As parcelas somavam R$ 14.000 e o banco recebeu R$ 14.000; so
-- o campo de preco dizia 14. Apareceu porque o R$/Wp dele saiu R$ 0,00 num
-- grupo todo entre 2,40 e 3,00. Corrigido (o trigger trg_sincroniza_valor
-- espelhou), e as fichas que nao fecham cairam de 14 para 13 na mesma hora.
--
-- A `conferir_financeiro()` das 7h30 passou a procurar isso sozinha, mais o
-- caso de parcelas iguais no mesmo vencimento, que e o que faz a conciliacao
-- recusar o casamento.

create or replace function public.get_kpis_financeiro(p_ini date, p_fim date)
returns json language plpgsql stable security definer set search_path to 'public' as $function$
declare v json; v_desde date;
begin
  if not is_financeiro() then return null; end if;
  select min(data_mov) into v_desde from extrato_movimentos;

  with base as (
    select o.id, o.contrato, o.cliente, o.potencia_kwp, o.qtd_modulos,
           o.data_fechamento, o.etapa_numero, o.vendedor_id,
           f.preco_negociado,
           nullif(coalesce(nullif(f.previsto_total,0),
             coalesce(f.valor_kit,0)+coalesce(f.material_ca,0)+coalesce(f.material_eletrico,0)
            +coalesce(f.cabo,0)+coalesce(f.instalacao,0)+coalesce(f.deslocamento,0)
            +coalesce(f.art,0)+coalesce(f.seguro,0)+coalesce(f.frete,0)
            +coalesce(f.estrutura_carport,0)+coalesce(f.carregador,0)+coalesce(f.obra_civil,0)
            +coalesce(f.pecas,0)+coalesce(f.custo_operacional,0)+coalesce(f.comissao_valor,0)),0) as custo_estimado,
           (select coalesce(sum(r.valor),0) from extrato_rateio r
              join extrato_movimentos m on m.id=r.movimento_id
             where r.obra_id=o.id and m.classificacao='custo_obra') as custo_incorrido,
           (select coalesce(sum(r.valor),0) from extrato_rateio r
              join extrato_movimentos m on m.id=r.movimento_id
             where r.obra_id=o.id and m.classificacao='recebimento') as ja_recebido
      from obras o
      join obra_financeiro f on f.obra_id = o.id
     where coalesce(o.trilha,'padrao') <> 'manutencao'
       and not coalesce(o.cliente_externo,false)
       and not coalesce(f.dispensado,false)
       and o.data_fechamento between p_ini and p_fim
  ),
  wp as (
    select b.*, round(b.preco_negociado / (b.potencia_kwp * 1000), 2) as rs_wp
      from base b where b.potencia_kwp > 0 and b.preco_negociado > 0
  ),
  wip as (
    select b.*,
           round(b.custo_incorrido / b.custo_estimado * 100, 1) as pct_executado,
           round(b.ja_recebido / nullif(b.preco_negociado,0) * 100, 1) as pct_faturado
      from base b
     where b.preco_negociado > 0
       and b.custo_incorrido > 0
       and b.custo_estimado > b.preco_negociado * 0.30
       and b.data_fechamento >= v_desde
  )
  select json_build_object(
    'rs_wp', json_build_object(
      'obras', (select count(*) from wp),
      'de_quantas', (select count(*) from base),
      'mediana', (select round(percentile_cont(0.5) within group (order by rs_wp)::numeric,2) from wp),
      'media',   (select round(avg(rs_wp),2) from wp),
      'minimo',  (select min(rs_wp) from wp),
      'maximo',  (select max(rs_wp) from wp),
      'por_mes', (select coalesce(json_agg(x order by x.ord),'[]'::json) from (
          select to_char(data_fechamento,'MM/YYYY') as mes,
                 date_trunc('month',data_fechamento) as ord, count(*) as obras,
                 round(percentile_cont(0.5) within group (order by rs_wp)::numeric,2) as mediana
            from wp group by 1,2) x),
      'por_vendedor', (select coalesce(json_agg(y order by y.mediana),'[]'::json) from (
          select coalesce(e.nome,'sem vendedor') as vendedor, count(*) as obras,
                 round(percentile_cont(0.5) within group (order by w.rs_wp)::numeric,2) as mediana
            from wp w left join equipe e on e.id = w.vendedor_id group by 1) y)),
    'wip', json_build_object(
      'obras', (select count(*) from wip),
      'de_quantas', (select count(*) from base),
      'lista', (select coalesce(json_agg(w order by abs(w.desvio) desc),'[]'::json) from (
          select contrato, cliente, etapa_numero, preco_negociado,
                 custo_estimado, custo_incorrido, ja_recebido,
                 pct_executado, pct_faturado,
                 round(coalesce(pct_faturado,0) - pct_executado, 1) as desvio
            from wip) w),
      'o_que_falta', json_build_object(
        'sem_estimativa', (select count(*) from base where coalesce(custo_estimado,0) = 0),
        'estimativa_furada', (select count(*) from base
                               where coalesce(custo_estimado,0) > 0
                                 and custo_estimado <= preco_negociado * 0.30),
        'fechadas_antes_do_extrato', (select count(*) from base where data_fechamento < v_desde),
        'sem_gasto_classificado', (select count(*) from base where custo_incorrido = 0))),
    'cobertura', json_build_object(
      'obras_no_periodo', (select count(*) from base),
      'extrato_desde', v_desde)
  ) into v;
  return v;
end $function$;

-- Armadilha 10: os dois revokes, conferidos pela ACL depois.
revoke execute on function public.get_kpis_financeiro(date,date) from public;
revoke execute on function public.get_kpis_financeiro(date,date) from anon;
grant  execute on function public.get_kpis_financeiro(date,date) to authenticated;
