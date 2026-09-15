-- A ficha financeira de um cliente de plano nasce dispensada.
--
-- Descoberto na simulacao do cadastro da Tays, antes de gravar:
--
--   ERROR: Para salvar, preencha: valor do projeto, distância em km
--   CONTEXT: trava_campos_financeiro() <- abre_financeiro_obra()
--
-- O trigger abre_financeiro_obra() cria a ficha de toda obra com etapa >= 1,
-- e trava_campos_financeiro() exige preco_negociado e distancia_km. Um
-- cliente de plano nao tem nenhum dos dois: nao ha projeto vendido e nao ha
-- deslocamento de obra. O cadastro ficava impossivel.
--
-- A saida ja existia: `dispensado`, que 19 das 72 fichas ja usam e que a
-- propria trava respeita na primeira linha. A ficha continua existindo (o
-- plano gera receita e ela vai precisar de lugar), mas nao cobra campo de
-- venda.

create or replace function public.abre_financeiro_obra()
returns trigger
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if coalesce(new.etapa_numero,0) >= 1 then
    insert into obra_financeiro (obra_id, dispensado)
    values (new.id,
            coalesce(new.cliente_externo,false)
            or coalesce(new.trilha,'padrao') = 'manutencao')
    on conflict (obra_id) do nothing;
  end if;
  return new;
end;
$function$;
