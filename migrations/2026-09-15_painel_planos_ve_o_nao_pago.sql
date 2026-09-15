-- O painel de planos passa a enxergar o contrato assinado e ainda nao pago.
--
-- get_painel_planos() filtrava `status = 'ativo'`. Com a chegada do status
-- 'aguardando_pagamento' um contrato recem-fechado sumiria da tela -- que e
-- justamente a hora em que alguem precisa olhar para ele e cobrar.
--
-- O contrato nao pago entra como CONTAGEM PROPRIA e fica FORA da receita:
-- dinheiro que ainda nao entrou nao e MRR. Ele tambem fica fora da onda de
-- vencimentos (nao tem `fim` ate o pagamento) e fora do potencial (que mede
-- quem esta em cortesia e pode virar pagante).

create or replace function public.get_painel_planos()
returns json
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;

  with base as (
    select c.id, c.obra_id, c.plano_codigo, c.inicio, c.fim, c.forma, c.status,
           c.primeiro_pagamento_em,
           coalesce(c.valor,0) as valor,
           o.cliente, o.qtd_modulos, o.potencia_kwp, o.whatsapp_grupo_id,
           coalesce(o.cliente_externo,false) as externo,
           (c.fim - current_date) as dias,
           (select p.codigo from planos p
             where p.ativo and p.nivel=3
               and coalesce(o.qtd_modulos,0) between coalesce(p.mod_min,0) and coalesce(p.mod_max,999)
             order by p.mod_min limit 1) as completo_cod
    from plano_contratos c
    join obras o on o.id = c.obra_id
    where c.status in ('ativo','aguardando_pagamento')
  ),
  comp as (
    select b.*, p.nome as completo_nome, p.preco_anual as completo_anual,
           p.preco_mensal as completo_mensal,
           pp.nome as plano_nome
    from base b
    left join planos p  on p.codigo = b.completo_cod
    left join planos pp on pp.codigo = b.plano_codigo
  )
  select json_build_object(
    'resumo', (select json_build_object(
        'contratos',  count(*) filter (where status='ativo'),
        'aguardando', count(*) filter (where status='aguardando_pagamento'),
        'cortesias',  count(*) filter (where forma='cortesia' and status='ativo'),
        'pagos',      count(*) filter (where forma<>'cortesia' and status='ativo'),
        'mrr', round(coalesce(sum(case when status<>'ativo' then 0
                                       when forma='mensal' then valor
                                       when forma='anual'  then valor/12 else 0 end),0),2),
        'arr', round(coalesce(sum(case when status<>'ativo' then 0
                                       when forma='mensal' then valor*12
                                       when forma='anual'  then valor else 0 end),0),2),
        'vencidos',  count(*) filter (where status='ativo' and dias < 0),
        'vence_90',  count(*) filter (where status='ativo' and dias between 0 and 90)
      ) from comp),

    'potencial', (select json_build_object(
        'total_anual',  round(coalesce(sum(completo_anual),0),2),
        'ticket_medio', round(coalesce(avg(completo_anual),0),2),
        'c20', round(coalesce(sum(completo_anual),0)*0.20,2),
        'c30', round(coalesce(sum(completo_anual),0)*0.30,2),
        'c50', round(coalesce(sum(completo_anual),0)*0.50,2)
      ) from comp where forma='cortesia' and status='ativo'),

    'onda', (select coalesce(json_agg(x order by x.ord),'[]'::json) from (
        select to_char(fim,'MM/YYYY') as mes, date_trunc('month',fim) as ord,
               count(*) as contratos,
               round(sum(coalesce(completo_anual,0)),2) as potencial
        from comp where status='ativo' and fim is not null
        group by date_trunc('month',fim), to_char(fim,'MM/YYYY')) x),

    'portes', (select coalesce(json_agg(y order by y.anual),'[]'::json) from (
        select coalesce(completo_nome,'Sem porte definido') as porte,
               count(*) as clientes,
               coalesce(completo_anual,0) as anual,
               round(count(*)*coalesce(completo_anual,0),2) as potencial
        from comp where status='ativo'
        group by completo_nome, completo_anual) y),

    'lista', (select coalesce(json_agg(json_build_object(
        'obra_id',obra_id,'cliente',cliente,'modulos',qtd_modulos,'kwp',potencia_kwp,
        'plano',plano_codigo,'plano_nome',plano_nome,'forma',forma,'status',status,
        'inicio',inicio,'fim',fim,'dias',dias,'externo',externo,
        'valor',valor,'tem_grupo',(whatsapp_grupo_id is not null),
        'completo_nome',completo_nome,'completo_anual',completo_anual,
        'completo_mensal',completo_mensal
      ) order by (status='aguardando_pagamento') desc, fim nulls first, cliente),'[]'::json)
      from comp)
  ) into v;
  return v;
end;
$function$;
