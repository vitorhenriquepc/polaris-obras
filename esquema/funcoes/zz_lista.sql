CREATE OR REPLACE FUNCTION public.zz_lista()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nivel text; v_eq uuid;
begin
  v_nivel := public.meu_nivel();
  if v_nivel = 'nenhum' then return null; end if;
  v_eq := public.minha_equipe_id();
  return json_build_object(
    'nivel', v_nivel,
    'pode_agir', public.pode_agir_posvenda(),
    'clientes', (select coalesce(json_agg(t order by t.data_conclusao desc nulls last), '[]'::json) from (
      select o.id, o.cliente, o.contrato, o.slug, o.cidade, o.categoria,
             o.potencia_kwp, o.data_conclusao, o.ultima_resposta_em,
             o.optin_em, o.optout_em, o.nascimento_dia, o.nascimento_mes,
             (current_date - o.data_conclusao) as dias_ativo,
             (select e.nome from equipe e where e.id = o.vendedor_id) as vendedor,
             (select n.nota from nps n where n.obra_id = o.id) as nps,
             (select count(*) from mensagens_recebidas m
               where m.obra_id = o.id and m.lida_em is null and not coalesce(m.da_equipe,false)) as pendentes,
             (o.etapa_numero >= 8) as ativo
      from obras o
      where (o.etapa_numero >= 8
             or exists (select 1 from mensagens_recebidas mm
                        where mm.obra_id = o.id and mm.lida_em is null
                          and not coalesce(mm.da_equipe,false)))
        and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)
    ) t),
    'resumo', (select json_build_object(
      'respostas_pendentes', (select count(*) from mensagens_recebidas m
        join obras o on o.id = m.obra_id
        where m.lida_em is null and m.da_equipe = false and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)),
      'indicacoes_pendentes', (select count(*) from mensagens_recebidas m
        join obras o on o.id = m.obra_id
        where m.lida_em is null and m.da_equipe = false and m.contexto = 'indicacao'
          and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)),
      'clientes_ativos', (select count(*) from obras o
        where o.etapa_numero >= 8 and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)),
      'com_optin', (select count(*) from obras o
        where o.etapa_numero >= 8 and o.optin_em is not null and o.optout_em is null
          and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)),
      'sem_aniversario', (select count(*) from obras o
        where o.etapa_numero >= 8 and o.nascimento_dia is null
          and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq)),
      'sem_nps', (select count(*) from obras o
        where o.etapa_numero >= 8 and not exists(select 1 from nps n where n.obra_id = o.id)
          and (v_nivel <> 'vendedor' or o.vendedor_id = v_eq))
    ))
  );
end; $function$
