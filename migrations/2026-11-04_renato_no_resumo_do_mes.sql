-- 04/11: a academia do Renato (ATA ACADEMIA, 4563) entra no resumo do mês do
-- cliente modelo (Vitor, 04/11: "pode colocar o Renato nessa lista teste de
-- clientes que a gente está enviando esse relatório"). O de setembro dele foi um
-- piloto, com o texto ajustado à mão (contato 662). Gerado pela função como ela
-- estava, o de outubro saía com três erros:
--
--   1) "Olá, Ata!"  -> clientes.chamar_de = 'Renato' (só o resumo lê esse campo);
--   2) "Casa do dono (Renato Tozin)", o nome que a EQUIPE dá à usina, no texto
--      do cliente -> usinas.apelido_cliente (coluna nova): o nome que o cliente
--      lê, quando o da equipe é interno. Vazio = o apelido de sempre. A casa
--      vira "Sua casa", como no piloto;
--   3) "Desde a instalação (julho/2025) ... Isso já é 74,1% do investimento de
--      R$ 59.872": somava as duas usinas que OUTRA empresa instalou em 2021
--      (obra_usina.papel = 'herdada') com a nossa, de julho/2026. O certo é 9,6%
--      (7.194 kWh, R$ 5.732). Quando a obra tem usina herdada, o acumulado passa
--      a dizer "Desde <mês/ano> (desde quando temos o registro das N usinas)" e o
--      retorno conta só o que a Polaris instalou -- o formato do piloto de
--      setembro, que o Vitor aprovou:
--
--        📈 *Desde julho/2025*
--        _(desde quando temos o registro das 3 usinas)_
--        55.703 kWh gerados · *R$ 44.384 de economia*
--
--        💡 *O sistema que instalamos* (julho/2026) já gerou 7.194 kWh · *R$ 5.732 de economia*
--        Isso já é 9,6% do investimento de R$ 59.872.
--
-- Quem não tem usina herdada lê o texto de antes, byte a byte (conferido: o do
-- Gilberto e o do Júnior de outubro, contatos 776 e 777, saem iguais). O Júnior
-- e a Tays têm só usina herdada, mas o Júnior não recebe o acumulado
-- (resumo_sem_acumulado_obras) e a Tays não está na lista.
--
-- A função é alterada por recorte da definição publicada (marcadores conferidos
-- um a um, como em 2026-10-15_resumo_mensal_tempo_mais_claro.sql). Rodar de
-- novo não muda nada.

alter table public.usinas add column if not exists apelido_cliente text;
comment on column public.usinas.apelido_cliente is
  'Nome da usina que o cliente lê no resumo do mês, quando o apelido da equipe é interno (04/11: "Sua casa" para a "Casa do dono (Renato Tozin)" da academia, 4563). Vazio = o apelido.';

create or replace function public._rm_usinas(p_obra uuid, p_fim date)
 returns table(id uuid, apelido text, kwp numeric, inst date, la numeric, lo numeric, desliga smallint[], principal boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- o nome que o cliente lê (usinas.apelido_cliente, 04/11) vem antes do da equipe
  select u.id, coalesce(nullif(btrim(u.apelido_cliente), ''), u.apelido, 'Usina'), u.potencia_kwp, u.data_instalacao,
         round(coalesce(u.latitude, -21.2089), 1), round(coalesce(u.longitude, -50.4328), 1),
         coalesce(u.desliga_dias_semana, '{}'), coalesce(ou.principal, false)
  from obra_usina ou join usinas u on u.id = ou.usina_id
  where ou.obra_id = p_obra and ou.saiu_em is null and u.ativa
    and (u.data_instalacao is null or u.data_instalacao <= p_fim);
$function$;

do $do$
declare
  d text := pg_get_functiondef('public.resumo_mensal_obra(uuid,date)'::regprocedure);
  m1 constant text := $m$  v_eco_soma numeric;
$m$;
  m2 constant text := $m$    into v_acum, v_desde, v_hist
  from public._rm_usinas(p_obra, v_fim) u join usinas uu on uu.id = u.id;
$m$;
  m3 constant text := $m$  if not v_sem_acum then
  t := t || E'\n📈 *Desde a instalação*'$m$;
  m5 constant text := $m$'pct', round(v_acum * v_tar / v_o.valor_projeto * 100, 1))$m$;
begin
  if position('v_herd' in d) > 0 then
    raise notice 'resumo_mensal_obra já separa a usina herdada; nada a fazer';
    return;
  end if;
  -- cada marcador tem de aparecer exatamente uma vez
  if (length(d) - length(replace(d, m1, ''))) / length(m1) <> 1 then raise exception 'marcador 1 (declare) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m2, ''))) / length(m2) <> 1 then raise exception 'marcador 2 (acumulado) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m3, ''))) / length(m3) <> 1 then raise exception 'marcador 3 (texto do acumulado) não está uma vez só'; end if;
  if (length(d) - length(replace(d, m5, ''))) / length(m5) <> 1 then raise exception 'marcador 5 (json do retorno) não está uma vez só'; end if;

  -- 1) as variáveis
  d := replace(d, m1, m1 || $q$  -- usina instalada por outra empresa (obra_usina.papel = 'herdada'): entra na
  -- geração e no acumulado, mas não no retorno do investimento (academia, 04/11)
  v_herd int := 0; v_n_prop int := 0; v_acum_prop numeric; v_inst_prop date;
$q$);

  -- 2) quanto o que a Polaris instalou gerou desde a instalação
  d := replace(d, m2, m2 || $q$
  select count(*) filter (where ou.papel = 'herdada'),
         count(*) filter (where coalesce(ou.papel, '') <> 'herdada'),
         sum(case when coalesce(ou.papel, '') <> 'herdada' then
               coalesce(case when uu.historico_ate <= v_fim then uu.historico_kwh end, 0)
             + coalesce((select sum(g.kwh) from usina_geracao g
                          where g.usina_id = u.id and g.referencia <= v_mes
                            and (u.inst is null or g.referencia >= date_trunc('month', u.inst)::date)
                            and (uu.historico_ate is null or uu.historico_ate > v_fim
                                 or g.referencia > uu.historico_ate)), 0) end),
         min(u.inst) filter (where coalesce(ou.papel, '') <> 'herdada')
    into v_herd, v_n_prop, v_acum_prop, v_inst_prop
  from public._rm_usinas(p_obra, v_fim) u
  join usinas uu on uu.id = u.id
  left join obra_usina ou on ou.obra_id = p_obra and ou.usina_id = u.id and ou.saiu_em is null;
$q$);

  -- 3) o texto: com usina herdada, o acumulado é desde o registro e o retorno é
  --    só do que instalamos; sem herdada, o bloco de antes, igual
  d := replace(d, m3, $q$  if not v_sem_acum and v_herd > 0 then
    -- Usina que OUTRA empresa instalou (obra_usina.papel = 'herdada'), como as duas
    -- de 2021 da academia do Renato (4563, 04/11): não dá para dizer "desde a
    -- instalação", e somá-las no retorno dava 74% do investimento em vez de 9,6%.
    -- Mesmo formato do piloto de setembro que o Vitor aprovou (contato 662).
    t := t || E'\n📈 *' || coalesce('Desde ' || v_nomes[extract(month from v_desde)::int] || '/' || extract(year from v_desde), 'Acumulado') || '*' || E'\n'
      || '_(desde quando temos o registro ' || case when v_n > 1 then 'das ' || v_n || ' usinas' else 'da usina' end || ')_' || E'\n'
      || case when v_hist or v_manual
              then '≈ ' || public._rm_num(round(v_acum, -3), 0) || ' kWh gerados · *≈ R$ ' || public._rm_num(round(v_acum * v_tar, -3), 0)
              else public._rm_num(v_acum, 0) || ' kWh gerados · *R$ ' || public._rm_num(v_acum * v_tar, 0) end
      || ' de economia*' || E'\n';
    if v_n_prop > 0 and coalesce(v_acum_prop, 0) > 0 then
      t := t || E'\n💡 *' || case when v_n_prop > 1 then 'Os sistemas que instalamos' else 'O sistema que instalamos' end || '*'
        || coalesce(' (' || v_nomes[extract(month from v_inst_prop)::int] || '/' || extract(year from v_inst_prop) || ')', '')
        || case when v_n_prop > 1 then ' já geraram ' else ' já gerou ' end
        || public._rm_num(v_acum_prop, 0) || ' kWh · *R$ ' || public._rm_num(v_acum_prop * v_tar, 0) || ' de economia*' || E'\n';
      if coalesce(v_o.valor_projeto, 0) > 0 and not v_o.externo then
        t := t || 'Isso já é ' || public._rm_num(v_acum_prop * v_tar / v_o.valor_projeto * 100, 1)
          || '% do investimento de R$ ' || public._rm_num(v_o.valor_projeto, 0) || '.' || E'\n';
      end if;
    end if;
  elsif not v_sem_acum then
  t := t || E'\n📈 *Desde a instalação*'$q$);

  -- 4) o json do retorno segue o texto
  d := replace(d, m5, $q$'pct', round(case when v_herd > 0 then coalesce(v_acum_prop, 0) else v_acum end * v_tar / v_o.valor_projeto * 100, 1),
                 'kwh_instalado_por_nos', case when v_herd > 0 then round(v_acum_prop) end)$q$);

  execute d;
end $do$;

-- o Renato: nome, a casa dele e a lista do resumo do mês
update public.clientes set chamar_de = 'Renato'
 where id = '2ebf46e7-51fa-4b9e-aa3d-2f1885a52856' and chamar_de is null;
update public.usinas set apelido_cliente = 'Sua casa'
 where id = '97d000cf-d46e-4866-8a63-ad151aecd217' and apelido_cliente is null;
update public.config set valor = valor || ',0f6c28e6-e200-46be-aafd-9f367a30bc65'
 where chave = 'resumo_mensal_obras' and position('0f6c28e6-e200-46be-aafd-9f367a30bc65' in valor) = 0;

-- O resumo de outubro dele entra na régua à parte, como aguardando, para as 9h de
-- 05/11 (resumo_mensal_enfileirar('2026-10-01', '2026-11-05', false) -- pula o
-- Gilberto e o Júnior, que já estão lá).
