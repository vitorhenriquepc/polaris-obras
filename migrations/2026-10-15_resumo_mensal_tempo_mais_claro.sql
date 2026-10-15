-- Resumo mensal: o bloco "O tempo em <mês>" ficou confuso (Vitor, 15/10, lendo o
-- resumo de setembro da Tays):
--
--   ☀️ 17 dias de sol / ⛅ 11 dias parcialmente nublados / ☁️ 2 dias nublados
--   🌧️ Choveu em 16 desses dias (155 mm no mês)
--
-- Os números estavam certos, mas "17 de sol" e "choveu em 16" pareciam se
-- contradizer: a chuva não é um quarto grupo, ela cai DENTRO dos outros três
-- (setembro no ponto da Tays: 3 dos 17 de sol tiveram chuva rápida; choveu nos
-- 11 parcialmente nublados e nos 2 nublados; 62 dos 155 mm caíram no dia 14).
--
-- Agora cada dia entra uma vez só, com a chuva junto do tipo de dia, e o total
-- em mm vem por último — com o dia mais chuvoso quando ele explica boa parte do
-- total (>= 20 mm e >= 30% do mês):
--
--   ☀️ 17 dias de sol (3 com chuva rápida)
--   ⛅ 11 dias parcialmente nublados (choveu em todos)
--   ☁️ 2 dias nublados (choveu nos dois)
--
--   🌧️ 155 mm de chuva no mês — 62 mm só no dia 14/09
--
-- Dia de chuva continua sendo >= 1 mm (garoa abaixo disso não conta). Todo
-- número sai de radiacao_dia (regra 3.1). Muda só o texto e o json 'clima';
-- o resto da função fica igual. Vale para todos os clientes do resumo modelo.
--
-- Aplicado por recorte da definição publicada (marcadores em ASCII, conferidos
-- um a um), para não reescrever as 400 linhas da função à mão.
do $do$
declare
  d text := pg_get_functiondef('public.resumo_mensal_obra(uuid,date)'::regprocedure);
  m1 constant text := 'count(*) filter (where d.chuva_mm >= 1) as dias_chuva,';
  m2 constant text := '|| case when v_cl.sol > 0 then';
  m3 constant text := '|| case when v_rad_ant > 0';
  m4 constant text := '''dias_chuva'', v_cl.dias_chuva, ''chuva_mm'', v_cl.chuva_mm,';
  i int; j int;
  novo text;
begin
  -- cada marcador tem de aparecer exatamente uma vez
  if (length(d) - length(replace(d, m1, ''))) / length(m1) <> 1 then raise exception 'marcador 1 (dias_chuva) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m2, ''))) / length(m2) <> 1 then raise exception 'marcador 2 (linha do sol) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m3, ''))) / length(m3) <> 1 then raise exception 'marcador 3 (comparação de sol) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m4, ''))) / length(m4) <> 1 then raise exception 'marcador 4 (json clima) não está uma vez só'; end if;

  -- 1) quantos dias de chuva caíram em cada tipo de dia, e o dia mais chuvoso
  d := replace(d, m1, m1 || $q$
         count(*) filter (where d.chuva_mm >= 1 and d.kwh_m2 >= m.mx * v_solpct / 100) as sol_chuva,
         count(*) filter (where d.chuva_mm >= 1 and d.kwh_m2 >= v_radmin and d.kwh_m2 < m.mx * v_solpct / 100) as parcial_chuva,
         count(*) filter (where d.chuva_mm >= 1 and d.kwh_m2 < v_radmin) as nublado_chuva,
         round(max(d.chuva_mm)) as chuva_max_mm,
         (array_agg(d.dia order by d.chuva_mm desc nulls last))[1] as chuva_max_dia,$q$);

  -- 2) o texto: cada dia uma vez só, a chuva junto do tipo de dia, o total no fim
  novo := $q$-- Cada dia entra uma vez só, e a chuva vai JUNTO do tipo de dia (Vitor,
      -- 15/10: "17 dias de sol" + "choveu em 16 desses dias" parecia contradição —
      -- a chuva não é um quarto grupo). O total em mm vem por último, com o dia
      -- mais chuvoso quando ele explica boa parte do mês.
      || case when v_cl.sol > 0 then '☀️ ' || v_cl.sol || case when v_cl.sol = 1 then ' dia de sol' else ' dias de sol' end
           || case when v_cl.sol_chuva = 0 then ''
                   when v_cl.sol_chuva = v_cl.sol then case when v_cl.sol = 1 then ' (com uma chuva rápida)' else ' (todos com alguma chuva rápida)' end
                   else ' (' || v_cl.sol_chuva || ' com chuva rápida)' end
           || E'\n' else '' end
      || case when v_cl.parcial > 0 then '⛅ ' || v_cl.parcial || case when v_cl.parcial = 1 then ' dia parcialmente nublado' else ' dias parcialmente nublados' end
           || case when v_cl.parcial_chuva = 0 then ''
                   when v_cl.parcial_chuva = v_cl.parcial and v_cl.parcial = 1 then ' (com chuva)'
                   when v_cl.parcial_chuva = v_cl.parcial and v_cl.parcial = 2 then ' (choveu nos dois)'
                   when v_cl.parcial_chuva = v_cl.parcial then ' (choveu em todos)'
                   else ' (choveu em ' || v_cl.parcial_chuva || ')' end
           || E'\n' else '' end
      || case when v_cl.nublado > 0 then '☁️ ' || v_cl.nublado || case when v_cl.nublado = 1 then ' dia nublado' else ' dias nublados' end
           || case when v_cl.nublado_chuva = 0 then ''
                   when v_cl.nublado_chuva = v_cl.nublado and v_cl.nublado = 1 then ' (com chuva)'
                   when v_cl.nublado_chuva = v_cl.nublado and v_cl.nublado = 2 then ' (choveu nos dois)'
                   when v_cl.nublado_chuva = v_cl.nublado then ' (choveu em todos)'
                   else ' (choveu em ' || v_cl.nublado_chuva || ')' end
           || E'\n' else '' end
      || E'\n'
      || case when v_cl.dias_chuva = 0 then '🌂 Não choveu no mês'
              else '🌧️ ' || public._rm_num(v_cl.chuva_mm, 0) || ' mm de chuva no mês'
                   || case when v_cl.chuva_max_mm >= 20 and v_cl.chuva_max_mm >= v_cl.chuva_mm * 0.3
                           then ' — ' || public._rm_num(v_cl.chuva_max_mm, 0) || ' mm só no dia '
                                || to_char(v_cl.chuva_max_dia, 'DD/MM')
                           else '' end end
      || E'\n'
      $q$;
  i := position(m2 in d);
  j := position(m3 in d);
  if j <= i then raise exception 'marcadores 2 e 3 fora de ordem'; end if;
  d := substr(d, 1, i - 1) || novo || substr(d, j);

  -- 3) o json 'clima' devolve também o detalhe novo
  d := replace(d, m4, m4 || $q$
                                'sol_chuva', v_cl.sol_chuva, 'parcial_chuva', v_cl.parcial_chuva,
                                'nublado_chuva', v_cl.nublado_chuva,
                                'chuva_max_mm', v_cl.chuva_max_mm, 'chuva_max_dia', v_cl.chuva_max_dia,$q$);

  execute d;
end $do$;
