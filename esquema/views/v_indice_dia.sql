create or replace view public.v_indice_dia as
 SELECT d.dia,
    count(*) FILTER (WHERE d.kwh_kwp IS NOT NULL) AS usinas,
    round(percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (d.kwh_kwp::double precision))::numeric, 3) AS mediana_kwh_kwp
   FROM usina_dia d
     JOIN usinas u ON u.id = d.usina_id AND u.ativa
  WHERE d.kwh_kwp IS NOT NULL
  GROUP BY d.dia;

alter view public.v_indice_dia set (security_invoker = true);

grant select on public.v_indice_dia to authenticated;
