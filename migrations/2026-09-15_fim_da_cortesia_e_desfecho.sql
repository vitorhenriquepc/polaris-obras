-- Fim da cortesia: avisar antes, e registrar o que o cliente decidiu.
--
-- O PROBLEMA
-- ----------
-- A `plano-vencimento` e o cron `plano-vencimento-diario` ('0 12 * * 1-5',
-- 9h de Brasilia) ja existiam e estao ativos, com aviso em D-30 e D-7 pela
-- `contratos_para_avisar()`. Nunca dispararam: o primeiro vencimento e
-- 17/04/2027 e nenhum contrato tem `aviso_30_em` ou `aviso_7_em` preenchido.
--
-- So que o texto tinha sido escrito para RENOVACAO PAGA, e os 54 contratos
-- ativos sao todos CORTESIA de um ano. Do jeito que estava, o cliente
-- receberia um aviso que:
--   - nao dizia que o acompanhamento era cortesia;
--   - nao dizia que a Polaris para de monitorar a geracao;
--   - nao trazia preco nenhum para continuar.
-- `contratos_para_avisar()` ja devolvia `forma`; a edge function ignorava.
--
-- Nao havia tambem onde guardar se o cliente FIDELIZOU ou nao no fim da
-- cortesia -- o contrato so virava 'encerrado', sem dizer por que.

-- 1. O desfecho do contrato.
alter table plano_contratos
  add column if not exists desfecho        text,
  add column if not exists desfecho_em     date,
  add column if not exists desfecho_motivo text;

alter table plano_contratos drop constraint if exists plano_contratos_desfecho_ok;
alter table plano_contratos add constraint plano_contratos_desfecho_ok
  check (desfecho is null or desfecho in ('renovou','nao_renovou'));

comment on column plano_contratos.desfecho is
  'Como o contrato terminou: renovou (fidelizou) ou nao_renovou. Null = ainda aberto.';

-- 2. `plano_desfecho()` -- fecha o contrato antigo e, quando renovou, ja cria
--    o novo na MESMA chamada, herdando obra, CPF/CNPJ e nome da nota. O novo
--    nasce 'aguardando_pagamento' por padrao (p_aguardando), porque plano so
--    comeca quando o dinheiro entra -- mesma regra da
--    `plano_registrar_pagamento()`.
--
--    Nao apaga historico (regra 3.6): o contrato antigo continua la, com o
--    desfecho carimbado, e o novo aponta para ele na observacao.
--    Fechar duas vezes e recusado com a data do primeiro fechamento.
create or replace function public.plano_desfecho(
  p_contrato uuid, p_desfecho text, p_motivo text default null,
  p_plano_codigo text default null, p_valor numeric default null,
  p_forma text default 'anual', p_meses integer default 12,
  p_aguardando boolean default true)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare v record; v_novo uuid; v_fim date;
begin
  if not is_autorizado() then return json_build_object('erro','Sem permissao.'); end if;
  if p_desfecho not in ('renovou','nao_renovou') then
    return json_build_object('erro','Desfecho deve ser renovou ou nao_renovou.');
  end if;

  select * into v from plano_contratos where id = p_contrato;
  if not found then return json_build_object('erro','Contrato nao encontrado.'); end if;
  if v.desfecho is not null then
    return json_build_object('erro','Este contrato ja foi fechado como '
      || case v.desfecho when 'renovou' then 'renovado' else 'nao renovado' end
      || ' em ' || to_char(v.desfecho_em,'DD/MM/YYYY') || '.');
  end if;

  if p_desfecho = 'renovou' then
    if coalesce(btrim(coalesce(p_plano_codigo,'')),'') = '' then
      return json_build_object('erro','Escolha o plano da renovacao.');
    end if;
    if not exists (select 1 from planos where codigo = p_plano_codigo) then
      return json_build_object('erro','Plano nao encontrado.');
    end if;
    if p_forma <> 'cortesia' and coalesce(p_valor,0) <= 0 then
      return json_build_object('erro','Informe o valor do contrato novo.');
    end if;

    -- o novo comeca quando o antigo acaba, salvo se for aguardar pagamento
    v_fim := case when p_aguardando then null
                  else (coalesce(v.fim, current_date)
                        + (coalesce(p_meses,12)||' months')::interval)::date end;

    insert into plano_contratos (obra_id, plano_codigo, inicio, meses, fim, valor,
                                 forma, status, nota_documento, nota_nome, observacao)
    values (v.obra_id, p_plano_codigo,
            case when p_aguardando then null else coalesce(v.fim, current_date) end,
            coalesce(p_meses,12), v_fim, p_valor, coalesce(p_forma,'anual'),
            case when p_aguardando then 'aguardando_pagamento' else 'ativo' end,
            v.nota_documento, v.nota_nome,
            'Renovacao do contrato que venceu em '
              || coalesce(to_char(v.fim,'DD/MM/YYYY'),'?') || '.')
    returning id into v_novo;
  end if;

  update plano_contratos
     set status = 'encerrado',
         desfecho = p_desfecho,
         desfecho_em = current_date,
         desfecho_motivo = nullif(btrim(coalesce(p_motivo,'')),'')
   where id = p_contrato;

  return json_build_object('ok', true, 'desfecho', p_desfecho,
                           'contrato_novo', v_novo);
end;
$function$;

-- Armadilha 10: DOIS revokes, sempre. O gabarito e
-- {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke execute on function public.plano_desfecho(uuid,text,text,text,numeric,text,integer,boolean) from public;
revoke execute on function public.plano_desfecho(uuid,text,text,text,numeric,text,integer,boolean) from anon;
grant  execute on function public.plano_desfecho(uuid,text,text,text,numeric,text,integer,boolean) to authenticated;

-- 3. `contratos_para_avisar()` passa a levar o que a oferta precisa: quantos
--    modulos a obra tem, qual faixa do Completo cai nesse tamanho, e quantos
--    enderecos distintos as usinas ativas ocupam (a visita anual e por
--    endereco -- o Gilberto tem 4 usinas e 1 endereco).
--    `endereco` vazio cai para a cidade, entao a conta SUBESTIMA, que e o
--    lado seguro: nunca cobra a mais.
drop function if exists public.contratos_para_avisar();
create or replace function public.contratos_para_avisar()
returns table(id uuid, obra_id uuid, cliente text, telefone text, grupo text,
              plano_nome text, inicio date, fim date, dias integer, valor numeric,
              forma text, tipo_aviso text, modulos integer, completo_nome text,
              completo_anual numeric, completo_mensal numeric, enderecos integer,
              endereco_adicional numeric)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, o.id, o.cliente, o.telefone, o.whatsapp_grupo_id,
         coalesce(p.nome, c.plano_codigo), c.inicio, c.fim, (c.fim - current_date),
         c.valor, c.forma,
         case when (c.fim - current_date) <= 7  and c.aviso_7_em  is null then 'd7'
              when (c.fim - current_date) <= 30 and c.aviso_30_em is null then 'd30' end,
         o.qtd_modulos,
         cp.nome, cp.preco_anual, cp.preco_mensal,
         greatest(1, coalesce((select count(distinct coalesce(nullif(btrim(coalesce(u.endereco,'')),''), u.cidade))
                                 from obra_usina ou join usinas u on u.id = ou.usina_id
                                where ou.obra_id = o.id and u.ativa), 1))::int,
         (select valor::numeric from config where chave = 'plano_endereco_adicional')
  from plano_contratos c
  join obras o on o.id = c.obra_id
  left join planos p on p.codigo = c.plano_codigo
  left join lateral (
    select pl.nome, pl.preco_anual, pl.preco_mensal
      from planos pl
     where pl.ativo and pl.nivel = 3
       and coalesce(o.qtd_modulos,0) between coalesce(pl.mod_min,0) and coalesce(pl.mod_max,9999)
     order by pl.mod_min limit 1) cp on true
  where c.status = 'ativo' and c.fim >= current_date
    and ( ((c.fim - current_date) <= 7  and c.aviso_7_em  is null)
       or ((c.fim - current_date) <= 30 and c.aviso_30_em is null) )
  order by c.fim limit 30;
$function$;

revoke execute on function public.contratos_para_avisar() from public;
revoke execute on function public.contratos_para_avisar() from anon;
grant  execute on function public.contratos_para_avisar() to authenticated;

-- 4. `get_painel_planos()` ganhou 'conversao' (quantos renovaram sobre quantos
--    ja tiveram desfecho) e 'contrato_id' em cada linha, para a tela saber
--    qual contrato fechar. Editada no lugar com pg_get_functiondef + replace,
--    e conferida numa chamada SEPARADA -- armadilha 2: `rollback` desfaz DDL,
--    e um teste dentro do begin/rollback passa mesmo com a funcao intacta.
--    Os dois trechos que entraram:
--
--      'conversao', (select json_build_object(
--          'renovaram',     count(*) filter (where desfecho = 'renovou'),
--          'nao_renovaram', count(*) filter (where desfecho = 'nao_renovou'),
--          'decididos',     count(*) filter (where desfecho is not null)
--        ) from plano_contratos),
--
--      'lista', (select coalesce(json_agg(json_build_object(
--          'contrato_id',id,                     <- novo
--          'obra_id',obra_id, ...
--
--    `dias` continua sendo (c.fim - current_date), entao vem NULL para contrato
--    em 'aguardando_pagamento' -- e e desse null que a tela depende para nao
--    oferecer "fidelizou?" a quem ainda nem comecou.

-- 5. A edge function `plano-vencimento` (v6) passou a olhar `forma`:
--      - forma = 'cortesia'  -> texto de fim de cortesia. Diz que foi
--        cortesia, lista o que PARA de acontecer (monitoramento, alerta de
--        parada, relatorio), e so entao traz o preco da faixa certa.
--      - qualquer outra      -> o texto de renovacao que ja existia.
--    A previa em modo simular pegou tres defeitos antes de qualquer envio:
--    texto sem acento nenhum, "GILBERTO" gritando, e "R$ 1990,00" sem ponto
--    de milhar. Corrigidos com primeiroNome() e toLocaleString('pt-BR').
--    Quando a faixa nao tem preco de tabela (completo_especial, acima de 125
--    modulos), o texto vira "preparamos uma proposta" em vez de imprimir
--    R$ 0,00 -- numero inventado indo para o cliente.
--
--    ATENCAO, decisao do Vitor: esta automacao ENVIA DIRETO ao cliente as 9h,
--    sem passar pela regua e sem aprovacao da Livia. Ja era assim antes desta
--    mudanca (o cron e a function existem desde antes e nunca dispararam
--    porque o primeiro vencimento e 17/04/2027). Nao mexi nisso, mas agora a
--    mensagem carrega PRECO e OFERTA, e nao so um lembrete -- o que aumenta o
--    custo de sair errado. A equipe recebe o resumo no mesmo disparo, depois
--    do cliente. Se for para exigir aprovacao antes, a mudanca e na
--    `plano-vencimento`, e tem de ser decidida.
