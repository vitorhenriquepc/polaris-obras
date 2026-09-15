-- Adicionar uma usina a um cliente que ja existe.
--
-- O caso: cliente rural com uma propriedade nova, ou quem ampliou. Ate aqui
-- usina so nascia do casamento automatico com o SolarView -- nao havia como
-- criar uma a mao em tela nenhuma.
--
-- DUAS DECISOES QUE VALEM EXPLICAR
--
-- 1. So recalcula o total da obra quando ela e CLIENTE DE PLANO.
--    Em obra de venda, `potencia_kwp` e o projeto vendido: alimenta a ficha
--    financeira, o relatorio e a margem. Somar uma usina nova ali mudaria o
--    tamanho de uma venda que ja aconteceu. Nesse caso a funcao grava a usina
--    e AVISA que o total da obra ficou como estava.
--
-- 2. Soma incremental, nao recalculo.
--    `usinas` nao tem coluna de modulos -- o numero vive na obra. Entao nao da
--    para recontar a partir da tabela; soma-se o que chega.

create or replace function public.usina_adicionar(
  p jsonb, p_simular boolean default true)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_erros  text[] := array[]::text[];
  v_avisos text[] := array[]::text[];
  u jsonb := coalesce(p->'usina','{}'::jsonb);
  v_obra_id uuid := nullif(p->>'obra_id','')::uuid;
  v_obra record;
  v_apelido text := btrim(coalesce(u->>'apelido',''));
  v_kwp numeric := nullif(u->>'potencia_kwp','')::numeric;
  v_mods int := coalesce(nullif(u->>'modulos','')::int, 0);
  v_cidade text := btrim(coalesce(u->>'cidade',''));
  v_comp uuid := nullif(u->>'compensa_em','')::uuid;
  v_inst text := nullif(btrim(coalesce(u->>'instalador_terceiro','')),'');
  v_uid uuid;
  v_locais int;
begin
  if not is_autorizado() then
    return json_build_object('ok', false, 'erros', json_build_array('Sem permissao.'));
  end if;

  select o.id, o.cliente, o.cliente_id, coalesce(o.cliente_externo,false) as externo,
         o.sistema_origem, o.potencia_kwp, o.qtd_modulos
    into v_obra
    from obras o where o.id = v_obra_id;

  if not found then
    return json_build_object('ok', false, 'erros', json_build_array('Obra nao encontrada.'));
  end if;
  if v_obra.cliente_id is null then
    return json_build_object('ok', false, 'erros', json_build_array(
      'Esta obra ainda nao tem cadastro de cliente ligado, e a usina pendura no cliente. Ligue o cliente primeiro.'));
  end if;

  if v_apelido = '' then
    v_erros := v_erros || array['De um apelido para a usina, como "Sitio — Birigui".'];
  end if;
  if coalesce(v_kwp,0) <= 0 then
    v_erros := v_erros || array['Informe a potencia em kWp.'];
  end if;
  if v_cidade = '' then
    v_erros := v_erros || array['Informe a cidade: e ela que define a vizinhanca de comparacao.'];
  end if;
  if v_comp is not null and not exists (
       select 1 from usinas x where x.id = v_comp and x.cliente_id = v_obra.cliente_id) then
    v_erros := v_erros || array['A usina que recebe os creditos precisa ser do mesmo cliente.'];
  end if;

  if array_length(v_erros,1) > 0 then
    return json_build_object('ok', false, 'erros', to_json(v_erros));
  end if;

  if exists (select 1 from usinas x
              where x.cliente_id = v_obra.cliente_id
                and unaccent_simples(x.apelido) = unaccent_simples(v_apelido)) then
    v_avisos := v_avisos || array['Ja existe uma usina com esse apelido neste cliente. Nomes iguais confundem na hora de abrir.'];
  end if;

  if not v_obra.externo then
    v_avisos := v_avisos || array[
      'Obra de venda: a potencia e os modulos da obra ficam como estao, porque ali e o projeto vendido. So a usina e criada.'];
  end if;

  select count(distinct coalesce(nullif(btrim(coalesce(x.endereco,'')),''), x.cidade))
    into v_locais
    from usinas x where x.cliente_id = v_obra.cliente_id and x.ativa;

  if p_simular then
    return json_build_object('ok', true, 'simulado', true,
      'avisos', to_json(v_avisos),
      'cliente', v_obra.cliente,
      'externo', v_obra.externo,
      'usinas_hoje', (select count(*) from usinas x
                       where x.cliente_id = v_obra.cliente_id and x.ativa),
      'enderecos_hoje', v_locais,
      'enderecos_depois', (
         select count(distinct e) from (
           select coalesce(nullif(btrim(coalesce(x.endereco,'')),''), x.cidade) e
             from usinas x where x.cliente_id = v_obra.cliente_id and x.ativa
           union
           select coalesce(nullif(btrim(coalesce(u->>'endereco','')),''), v_cidade)
         ) z),
      'kwp_obra_depois', case when v_obra.externo
                              then coalesce(v_obra.potencia_kwp,0) + v_kwp
                              else v_obra.potencia_kwp end,
      'modulos_obra_depois', case when v_obra.externo
                                  then coalesce(v_obra.qtd_modulos,0) + v_mods
                                  else v_obra.qtd_modulos end,
      'papel', coalesce(nullif(btrim(coalesce(u->>'papel','')),''),
                        case when v_obra.externo then 'herdada' else 'expansao' end));
  end if;

  insert into usinas (cliente_id, apelido, potencia_kwp, cidade, endereco,
                      data_instalacao, data_estimada, instalador_terceiro,
                      compensa_em, ativa)
  values (v_obra.cliente_id, v_apelido, v_kwp, v_cidade,
          nullif(btrim(coalesce(u->>'endereco','')),''),
          nullif(u->>'data_instalacao','')::date,
          coalesce((u->>'data_estimada')::boolean, false),
          coalesce(v_inst, case when v_obra.externo then v_obra.sistema_origem end),
          v_comp, true)
  returning id into v_uid;

  -- sem o vinculo em obra_usina a usina nasce meio conectada: 24 funcoes do
  -- pos-venda leem essa tabela, nao usinas.cliente_id.
  -- papel 'herdada' = instalou outra empresa; 'expansao' = a Polaris vendeu
  -- esta usina depois da obra original.
  insert into obra_usina (obra_id, usina_id, papel, medicao, principal, entrou_em)
  values (v_obra_id, v_uid,
          coalesce(nullif(btrim(coalesce(u->>'papel','')),''),
                   case when v_obra.externo then 'herdada' else 'expansao' end),
          'inversor_proprio',
          not exists (select 1 from obra_usina x
                       where x.obra_id = v_obra_id and x.principal),
          nullif(u->>'data_instalacao','')::date);

  if v_obra.externo then
    update obras
       set potencia_kwp = coalesce(potencia_kwp,0) + v_kwp,
           qtd_modulos  = nullif(coalesce(qtd_modulos,0) + v_mods, 0)
     where id = v_obra_id;
  end if;

  return json_build_object('ok', true, 'simulado', false,
    'avisos', to_json(v_avisos),
    'usina_id', v_uid, 'apelido', v_apelido,
    'total_atualizado', v_obra.externo);
end;
$function$;

-- Armadilha 10: os dois revokes.
revoke execute on function public.usina_adicionar(jsonb, boolean) from public;
revoke execute on function public.usina_adicionar(jsonb, boolean) from anon;
grant  execute on function public.usina_adicionar(jsonb, boolean) to authenticated;
