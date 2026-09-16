-- 2026-09-16 — Cliente de plano que ficou sem contrato
--
-- O QUE ACONTECEU
-- O UNI AUTO POSTO DE ARACATUBA LTDA foi cadastrado em 16/09 pela aba
-- "Novo cliente" e nao apareceu no Acompanhamento. Nao foi erro de quem
-- cadastrou: gravou cliente, obra, DUAS usinas (235 kWp, 420 modulos), os dois
-- vinculos em obra_usina e a ficha financeira -- e ZERO contrato.
--
-- A causa esta na propria plano_cadastrar_cliente: o contrato so nasce
-- `if v_plano_cod is not null`. Com o select de plano na opcao default
-- ("— sem plano por enquanto —") ela grava o resto, devolve `ok: true` e nao
-- diz nada. E o get_painel_planos le `from plano_contratos`, entao um cliente
-- de plano sem contrato simplesmente NAO EXISTE para aquele painel.
--
-- Cadastro parcial que se anuncia como sucesso e o pior dos dois mundos: a
-- pessoa vai embora achando que gravou.
--
-- O QUE ESTA MIGRACAO FAZ
-- 1. plano_contrato_criar(): fecha o contrato numa obra que JA existe, com as
--    mesmas validacoes do cadastro. E o caminho de volta para quem ficou sem.
-- 2. get_painel_planos(): passa a devolver `sem_contrato` -- os clientes de
--    plano que nao tem contrato aberto. Eles param de sumir.
--
-- O que NAO faz: nao proibe cadastrar sem plano. Cadastrar o cliente antes de
-- fechar o preco e legitimo -- o UNI AUTO tem 420 modulos, cai na
-- completo_especial e o valor e negociado. O que nao pode e ele sumir depois.

-- ---------------------------------------------------------------------------
-- 1. Fechar o contrato de uma obra que ja existe
-- ---------------------------------------------------------------------------
create or replace function public.plano_contrato_criar(p jsonb,
                                                       p_simular boolean default true)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_erros text[] := array[]::text[];
  v_obra uuid := nullif(p->>'obra_id','')::uuid;
  v_cod  text := nullif(btrim(coalesce(p->>'plano_codigo','')),'');
  v_valor numeric := nullif(p->>'valor','')::numeric;
  v_forma text := coalesce(nullif(btrim(coalesce(p->>'forma','')),''),'anual');
  v_meses int  := coalesce(nullif(p->>'meses','')::int, 12);
  v_aguardando boolean := coalesce((p->>'aguardando')::boolean, true);
  v_inicio date := nullif(p->>'inicio','')::date;
  v_notadoc text := nullif(regexp_replace(coalesce(p->>'nota_documento',''),'\D','','g'),'');
  v_cliente text; v_plano_nome text; v_aberto record; v_id uuid;
begin
  if not is_autorizado() then
    return json_build_object('ok', false, 'erros', json_build_array('Sem permissao.'));
  end if;

  select o.cliente into v_cliente from obras o where o.id = v_obra;
  if v_cliente is null then
    v_erros := v_erros || array['Obra nao encontrada.'];
  end if;

  -- um contrato aberto por vez. Sem isso, clicar duas vezes cria dois
  -- contratos e o painel passa a contar receita em dobro.
  select c.id, c.status, c.plano_codigo into v_aberto
    from plano_contratos c
   where c.obra_id = v_obra and c.status in ('ativo','aguardando_pagamento')
   limit 1;
  if v_aberto.id is not null then
    v_erros := v_erros || array[('Este cliente ja tem contrato '
      || case when v_aberto.status='ativo' then 'ativo' else 'aguardando pagamento' end
      || '. Encerre o atual antes de abrir outro.')];
  end if;

  if v_cod is null then
    v_erros := v_erros || array['Escolha o plano.'];
  else
    select nome into v_plano_nome from planos where codigo = v_cod;
    if v_plano_nome is null then
      v_erros := v_erros || array['Plano nao encontrado.'];
    end if;
  end if;

  if v_forma not in ('anual','mensal','cortesia') then
    v_erros := v_erros || array['Cobranca deve ser anual, mensal ou cortesia.'];
  end if;
  if v_forma <> 'cortesia' and coalesce(v_valor,0) <= 0 then
    v_erros := v_erros || array['Informe o valor do contrato.'];
  end if;
  if v_meses <= 0 then
    v_erros := v_erros || array['Duracao em meses invalida.'];
  end if;
  if not v_aguardando and v_inicio is null then
    v_erros := v_erros || array['Informe a data de inicio, ou marque que comeca no 1o pagamento.'];
  end if;
  if v_notadoc is not null and length(v_notadoc) not in (11,14) then
    v_erros := v_erros || array['Documento da nota precisa ser CPF (11) ou CNPJ (14 digitos).'];
  end if;

  if array_length(v_erros,1) > 0 then
    return json_build_object('ok', false, 'erros', to_json(v_erros));
  end if;

  if p_simular then
    return json_build_object('ok', true, 'simulado', true,
      'cliente', v_cliente, 'plano', v_plano_nome, 'valor', v_valor,
      'forma', v_forma, 'meses', v_meses,
      'status', case when v_aguardando then 'aguardando_pagamento' else 'ativo' end,
      'fim', case when v_aguardando then null
                  else (v_inicio + (v_meses||' months')::interval)::date end);
  end if;

  insert into plano_contratos (obra_id, plano_codigo, inicio, meses, fim,
                               valor, forma, status,
                               nota_documento, nota_nome, observacao)
  values (v_obra, v_cod,
          case when v_aguardando then null else v_inicio end,
          v_meses,
          case when v_aguardando then null
               else (v_inicio + (v_meses||' months')::interval)::date end,
          v_valor, v_forma,
          case when v_aguardando then 'aguardando_pagamento' else 'ativo' end,
          v_notadoc,
          nullif(btrim(coalesce(p->>'nota_nome','')),''),
          nullif(btrim(coalesce(p->>'observacao','')),''))
  returning id into v_id;

  return json_build_object('ok', true, 'simulado', false,
    'contrato_id', v_id, 'cliente', v_cliente, 'plano', v_plano_nome,
    'status', case when v_aguardando then 'aguardando_pagamento' else 'ativo' end);
end;
$function$;

-- armadilha 10: sao DOIS revokes, e a conferencia e pela ACL
revoke execute on function public.plano_contrato_criar(jsonb, boolean) from public;
revoke execute on function public.plano_contrato_criar(jsonb, boolean) from anon;
grant  execute on function public.plano_contrato_criar(jsonb, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. O painel para de esconder quem nao tem contrato
-- ---------------------------------------------------------------------------
-- get_painel_planos() ganhou a chave `sem_contrato`: obras com
-- cliente_externo = true e nenhum contrato em ('ativo','aguardando_pagamento'),
-- com modulos, usinas e a faixa do Completo do porte. A definicao inteira esta
-- na funcao; aqui fica so o porque.
--
-- Medido em 16/09, logo apos: 1 cliente nessa situacao -- o UNI AUTO POSTO,
-- 420 modulos, faixa completo_especial, preco_anual NULO. A tela tem de tratar
-- isso como "sob consulta": moedaBR(null) imprime R$ 0,00, que e numero
-- inventado indo para o cliente.

-- ---------------------------------------------------------------------------
-- 3. Cortesia nao tem pagamento para aguardar
-- ---------------------------------------------------------------------------
-- Cortesia com 'comeca no 1o pagamento' ficaria em aguardando_pagamento para
-- sempre: sem inicio, sem fim, fora de todo numero e sem ninguem para dar
-- baixa. As DUAS funcoes passaram a recusar -- plano_contrato_criar e
-- plano_cadastrar_cliente -- porque a trava nao pode viver so na tela.
--
-- Aplicado por replace() sobre pg_get_functiondef. Armadilha 2: a conferencia
-- de que pegou foi num comando SEPARADO, depois, lendo a pg_get_functiondef de
-- novo. As duas voltaram com a trava dentro, e a ACL sobreviveu ao
-- create or replace: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
--
-- Testado como `authenticated` (Livia), em modo simular, sem gravar nada:
--   cortesia + aguardando .......... recusa com a mensagem certa
--   cortesia + inicio .............. ok, ativo ate 16/03/2027 (6 meses)
--   anual + aguardando ............. ok, aguardando_pagamento
--   obra inexistente ............... 'Obra nao encontrada.'
--   obra que ja tem contrato ....... recusa nomeando o status do atual
