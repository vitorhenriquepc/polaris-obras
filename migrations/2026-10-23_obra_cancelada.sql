-- Obra cancelada: sai do quadro, dos alertas e dos números; o histórico fica.
--
-- Por quê (23/10, BARBARA EDEN BINE, 4756): a cliente desistiu em 07/10 e o
-- Vitor pediu para "excluir do sistema". Excluir não dava e não devia:
--   * o botão de excluir (deletar-obra) daria erro — a obra tem dois movimentos
--     do extrato ligados (R$ 2.615,05 que entraram da BMP em 14/09, conciliados
--     como 1ª parcela, e R$ 108,39 da ART paga ao CREA em 14/08), e
--     extrato_rateio.obra_id não deixa apagar a obra (NO ACTION);
--   * mesmo forçando, levaria as 82 mensagens do grupo — inclusive a negociação
--     do cancelamento, que ainda está aberta (taxa da distribuidora, financiamento
--     com primeira parcela em 30/10) — e o vínculo do dinheiro que pode ter de
--     voltar para a financeira. Regra 3.6: histórico não se apaga.
-- O sistema já esperava um cancelamento: get_relatorios_painel,
-- obras_aguardando_ligacao e o solarview-vincular filtram status <> 'Cancelado'.
-- Mas a tela nunca gravou isso, o check de obras.status não aceita 'Cancelado' e
-- o fn_status_auto reescreve o status pela etapa — o filtro nunca fez nada.
--
-- O que muda:
--   1. obras.cancelada_em / cancelada_motivo / cancelada_por (o estado de hoje) e
--      obra_cancelamentos (o registro de cada cancelamento e de cada "desfazer";
--      não se apaga — é ele que a linha do tempo mostra);
--   2. obra_cancelar(obra, motivo, simular) e obra_cancelar_desfazer(obra, motivo,
--      simular), só admin (o mesmo de excluir), simular por padrão;
--   3. sincroniza_dre_obra: obra cancelada não tem venda no DRE (o lançamento de
--      origem 'obra' sai; desfazer devolve). O dinheiro do extrato não é tocado;
--   4. trava_campos_obra não cobra campo de venda de obra cancelada, nem no ato de
--      cancelar/desfazer — o card fica só de leitura e não há onde completar;
--   5. a obra cancelada sai de: alerta de prazo, fila e conferências do financeiro,
--      métricas, DRE por obra e faturado, R$/Wp, Início, relatórios pendentes,
--      agenda, lembrete da véspera, cobrança das fotos, travas e o link do
--      instalador (que passa a dizer "link inválido").
-- O que NÃO muda de propósito: a escada da Isabela continua lendo o grupo (a
-- conversa do cancelamento está viva), o extrato e a conciliação continuam
-- aceitando a obra (a devolução do dinheiro tem de ser classificada nela), e a
-- página do cliente (cliente.html) continua abrindo.
--
-- Teste: antes de aplicar, a saída de cada função alterada foi guardada (md5 por
-- chave); depois, sem nenhuma obra cancelada, tem de sair idêntica.

-- 1. estado e registro ---------------------------------------------------------

alter table public.obras
  add column if not exists cancelada_em timestamptz,
  add column if not exists cancelada_motivo text,
  add column if not exists cancelada_por text;

comment on column public.obras.cancelada_em is
  'Venda cancelada (cliente desistiu). Some do quadro, dos alertas e dos números; o histórico fica. Grava-se por obra_cancelar(), não pela tela.';

create table if not exists public.obra_cancelamentos (
  id bigint generated always as identity primary key,
  obra_id uuid not null references public.obras(id) on delete cascade,
  acao text not null check (acao in ('cancelada', 'reaberta')),
  motivo text,
  por text,
  em timestamptz not null default now()
);
create index if not exists obra_cancelamentos_obra on public.obra_cancelamentos (obra_id, em);

alter table public.obra_cancelamentos enable row level security;
create policy obra_cancelamentos_ler on public.obra_cancelamentos
  for select to authenticated using (public.is_autorizado());
-- escrita só pelas duas funções abaixo (security definer)
revoke all on public.obra_cancelamentos from anon;
revoke insert, update, delete, truncate on public.obra_cancelamentos from authenticated;

-- 2. cancelar e desfazer -------------------------------------------------------

create or replace function public.obra_cancelar(p_obra uuid, p_motivo text, p_simular boolean default true)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  o obras%rowtype;
  v_quem text := nullif(lower(coalesce(auth.jwt() ->> 'email', '')), '');
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_etapa text;
  v_entrou numeric; v_saiu numeric;
  v_abertas int; v_abertas_valor numeric;
  v_msgs int;
  v_venda numeric; v_venda_mes text;
  v_sai text[] := array[]::text[];
  v_fica text[] := array[]::text[];
  v_avisos text[] := array[]::text[];
begin
  if not is_admin() then
    return json_build_object('ok', false, 'erro', 'Só o administrador pode cancelar uma obra.');
  end if;
  select * into o from obras where id = p_obra;
  if not found then
    return json_build_object('ok', false, 'erro', 'Obra não encontrada.');
  end if;
  if o.cancelada_em is not null then
    return json_build_object('ok', false, 'erro', 'Esta obra já está cancelada desde '
      || to_char(o.cancelada_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      || coalesce(' — ' || o.cancelada_motivo, '') || '.');
  end if;
  if coalesce(obra_ativa(p_obra), false) then
    return json_build_object('ok', false, 'erro', 'Esta obra já foi entregue (última etapa da trilha). '
      || 'Obra entregue não se cancela por aqui; se o cliente desistiu do plano, é no Pós-venda.');
  end if;
  if v_motivo is null or length(v_motivo) < 5 then
    return json_build_object('ok', false, 'erro', 'Escreva o motivo do cancelamento — ele fica no histórico da obra.');
  end if;

  select e.nome into v_etapa from etapas e
   where e.trilha = coalesce(o.trilha, 'padrao') and e.numero = o.etapa_numero;
  select coalesce(sum(r.valor) filter (where m.valor > 0), 0),
         coalesce(sum(r.valor) filter (where m.valor < 0), 0)
    into v_entrou, v_saiu
    from extrato_rateio r join extrato_movimentos m on m.id = r.movimento_id
   where r.obra_id = p_obra;
  select count(*), coalesce(sum(valor), 0) into v_abertas, v_abertas_valor
    from obra_parcelas where obra_id = p_obra and not coalesce(recebida, false);
  select count(*) into v_msgs from mensagens_recebidas where obra_id = p_obra;
  select sum(valor), to_char(min(data_competencia), 'MM/YYYY') into v_venda, v_venda_mes
    from dre_lancamentos
   where obra_id = p_obra and origem = 'obra' and conta_codigo in ('01.1.01', '01.1.02');

  v_sai := v_sai || 'o quadro de obras e a TV'::text;
  if o.data_fechamento is not null then
    v_sai := v_sai || ('o alerta de prazo (fechada há ' || (current_date - o.data_fechamento) || ' dias)');
  end if;
  v_sai := v_sai || ('as métricas de venda'
    || case when coalesce(o.valor_projeto, 0) > 0
            then ': R$ ' || _rm_num(o.valor_projeto, 2)
                 || coalesce(' fechados em ' || to_char(o.data_fechamento, 'MM/YYYY'), '')
            else '' end);
  v_sai := v_sai || 'a fila e as conferências do financeiro'::text;
  if o.data_instalacao is not null then
    v_sai := v_sai || ('a agenda, o lembrete da véspera e a cobrança das fotos (instalação em '
      || to_char(o.data_instalacao, 'DD/MM/YYYY') || ')');
  end if;
  if o.instalador_token is not null then
    v_sai := v_sai || 'o link do instalador (passa a dizer "link inválido")'::text;
  end if;
  if v_venda is not null then
    v_sai := v_sai || ('a venda no DRE de ' || v_venda_mes || ' (R$ ' || _rm_num(v_venda, 2) || ')');
  end if;
  if v_abertas > 0 then
    v_sai := v_sai || (v_abertas || ' parcela(s) em aberto deixam de contar como atrasadas (R$ '
      || _rm_num(v_abertas_valor, 2) || ')');
  end if;

  if o.whatsapp_grupo_id is not null then
    v_fica := v_fica || ('o grupo do WhatsApp e as ' || v_msgs || ' mensagens — se a cliente escrever, '
      || 'a escada da Isabela continua avisando a equipe');
  end if;
  v_fica := v_fica || 'o histórico de etapas, a ficha financeira e as parcelas'::text;
  if v_entrou > 0 or v_saiu > 0 then
    v_fica := v_fica || ('o dinheiro do extrato ligado à obra: entrou R$ ' || _rm_num(v_entrou, 2)
      || ', saiu R$ ' || _rm_num(v_saiu, 2));
  end if;

  if v_entrou > 0 then
    v_avisos := v_avisos || ('Entrou R$ ' || _rm_num(v_entrou, 2) || ' do extrato nesta obra. Se for '
      || 'devolvido, classifique a saída no extrato nesta mesma obra, para o dinheiro dela fechar.');
  end if;
  if v_abertas > 0 then
    v_avisos := v_avisos || (v_abertas || ' parcela(s) em aberto (R$ ' || _rm_num(v_abertas_valor, 2)
      || ') continuam na ficha: confira no financeiro se ainda serão recebidas.');
  end if;

  if not p_simular then
    update obras set cancelada_em = now(), cancelada_motivo = v_motivo, cancelada_por = v_quem
     where id = p_obra;
    insert into obra_cancelamentos (obra_id, acao, motivo, por)
    values (p_obra, 'cancelada', v_motivo, v_quem);
    perform sincroniza_dre_obra(p_obra);
  end if;

  return json_build_object('ok', true, 'simulado', p_simular,
    'obra', json_build_object('id', o.id, 'cliente', o.cliente, 'contrato', o.contrato,
                              'etapa', coalesce(v_etapa, 'etapa ' || o.etapa_numero),
                              'valor', o.valor_projeto),
    'motivo', v_motivo,
    'sai_de', to_json(v_sai), 'fica', to_json(v_fica), 'avisos', to_json(v_avisos));
end $function$;

create or replace function public.obra_cancelar_desfazer(p_obra uuid, p_motivo text default null, p_simular boolean default true)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  o obras%rowtype;
  v_quem text := nullif(lower(coalesce(auth.jwt() ->> 'email', '')), '');
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_etapa text;
begin
  if not is_admin() then
    return json_build_object('ok', false, 'erro', 'Só o administrador pode desfazer um cancelamento.');
  end if;
  select * into o from obras where id = p_obra;
  if not found then
    return json_build_object('ok', false, 'erro', 'Obra não encontrada.');
  end if;
  if o.cancelada_em is null then
    return json_build_object('ok', false, 'erro', 'Esta obra não está cancelada.');
  end if;
  select e.nome into v_etapa from etapas e
   where e.trilha = coalesce(o.trilha, 'padrao') and e.numero = o.etapa_numero;

  if not p_simular then
    update obras set cancelada_em = null, cancelada_motivo = null, cancelada_por = null
     where id = p_obra;
    insert into obra_cancelamentos (obra_id, acao, motivo, por)
    values (p_obra, 'reaberta', coalesce(v_motivo, 'cancelamento desfeito'), v_quem);
    perform sincroniza_dre_obra(p_obra);
  end if;

  return json_build_object('ok', true, 'simulado', p_simular,
    'obra', json_build_object('id', o.id, 'cliente', o.cliente, 'contrato', o.contrato,
                              'etapa', coalesce(v_etapa, 'etapa ' || o.etapa_numero)),
    'cancelada_em', o.cancelada_em, 'motivo_do_cancelamento', o.cancelada_motivo,
    'volta', 'A obra volta ao quadro na etapa "' || coalesce(v_etapa, o.etapa_numero::text)
      || '", aos números e às listas. Nada é mandado para o cliente.');
end $function$;

-- armadilha 10: os DOIS revokes
revoke execute on function public.obra_cancelar(uuid, text, boolean) from public;
revoke execute on function public.obra_cancelar(uuid, text, boolean) from anon;
grant  execute on function public.obra_cancelar(uuid, text, boolean) to authenticated;
revoke execute on function public.obra_cancelar_desfazer(uuid, text, boolean) from public;
revoke execute on function public.obra_cancelar_desfazer(uuid, text, boolean) from anon;
grant  execute on function public.obra_cancelar_desfazer(uuid, text, boolean) to authenticated;

-- 3 a 5. as funções que já existem ganham a obra cancelada ----------------------
-- Troca de texto exata na definição que está no banco: se o trecho não aparecer
-- o número esperado de vezes, a migração inteira para (nada fica pela metade).
-- create or replace mantém dono e permissões.

create function pg_temp.troca(p_fn regprocedure, p_velho text, p_novo text, p_vezes int default 1)
returns void language plpgsql as $t$
declare d text := pg_get_functiondef(p_fn); n int;
begin
  n := (length(d) - length(replace(d, p_velho, ''))) / length(p_velho);
  if n <> p_vezes then
    raise exception '%: esperava % vez(es) o trecho [%], achei %', p_fn, p_vezes, p_velho, n;
  end if;
  execute replace(d, p_velho, p_novo);
end $t$;

-- DRE: obra cancelada não tem venda
select pg_temp.troca('public.sincroniza_dre_obra(uuid)',
  $o$select coalesce(data_instalacao, data_conclusao), coalesce(trilha,'padrao')$o$,
  $n$-- obra cancelada não tem venda: sem competência, o lançamento da venda sai do DRE
  select case when cancelada_em is null then coalesce(data_instalacao, data_conclusao) end, coalesce(trilha,'padrao')$n$);

-- a trava de campos não cobra obra cancelada (o card fica só de leitura)
select pg_temp.troca('public.trava_campos_obra()',
  $o$if coalesce(new.trilha,'padrao') <> 'padrao' then return new; end if;$o$,
  $n$if coalesce(new.trilha,'padrao') <> 'padrao' then return new; end if;
  -- obra cancelada não cobra campo de venda, nem no ato de cancelar ou de desfazer:
  -- o card fica só de leitura e não há onde completar (23/10, BARBARA 4756)
  if new.cancelada_em is not null then return new; end if;
  if tg_op = 'UPDATE' then
    if old.cancelada_em is not null then return new; end if;
  end if;$n$);

-- linha do tempo: cancelamento e "desfazer" aparecem
select pg_temp.troca('public.linha_do_tempo(uuid)',
  $o$  order by 1;$o$,
  $n$  union all
  select c.em, 'cancelamento',
         case c.acao when 'cancelada' then 'Obra cancelada' else 'Cancelamento desfeito' end,
         nullif(concat_ws(' · ', nullif(c.motivo, ''), nullif(c.por, '')), ''),
         case c.acao when 'cancelada' then '✖️' else '↩️' end
  from obra_cancelamentos c where c.obra_id = p_obra
  order by 1;$n$);

-- alerta de prazo (alerta-prazos, 8h, para a equipe)
select pg_temp.troca('public.obras_para_alerta(integer)',
  $o$where o.etapa_numero < 8$o$,
  $n$where o.etapa_numero < 8
    and o.cancelada_em is null$n$);

-- fila do financeiro
select pg_temp.troca('public.get_fila_financeiro()',
  $o$left join equipe e on e.id = o.vendedor_id$o$,
  $n$left join equipe e on e.id = o.vendedor_id
    where o.cancelada_em is null$n$);

-- o filtro que já esperava o cancelamento e nunca funcionou
select pg_temp.troca('public.get_relatorios_painel()',
  $o$where o.status <> 'Cancelado'$o$,
  $n$where o.cancelada_em is null$n$);
select pg_temp.troca('public.obras_aguardando_ligacao()',
  $o$where o.status <> 'Cancelado' and o.etapa_numero = 7$o$,
  $n$where o.cancelada_em is null and o.etapa_numero = 7$n$);

-- Início
select pg_temp.troca('public.get_inicio()',
  $o$from obras o join travas_tipos t on t.codigo=o.trava),$o$,
  $n$from obras o join travas_tipos t on t.codigo=o.trava where o.cancelada_em is null),$n$);
select pg_temp.troca('public.get_inicio()',
  $o$and o.data_instalacao is not null),$o$,
  $n$and o.data_instalacao is not null and o.cancelada_em is null),$n$);
select pg_temp.troca('public.get_inicio()',
  $o$where ((coalesce(o.trilha,'padrao')='manutencao' and o.etapa_numero between 2 and 3)$o$,
  $n$where o.cancelada_em is null
        and ((coalesce(o.trilha,'padrao')='manutencao' and o.etapa_numero between 2 and 3)$n$);
select pg_temp.troca('public.get_inicio()',
  $o$from obra_parcelas where not recebida and vencimento < current_date)$o$,
  $n$from obra_parcelas where not recebida and vencimento < current_date
        and not exists (select 1 from obras oc where oc.id = obra_parcelas.obra_id and oc.cancelada_em is not null))$n$);
select pg_temp.troca('public.get_inicio()',
  $o$from obras where data_instalacao between current_date and current_date + 7)$o$,
  $n$from obras where data_instalacao between current_date and current_date + 7 and cancelada_em is null)$n$);

-- métricas (metricas.html)
select pg_temp.troca('public.get_metricas(date,date)',
  $o$) from obras),$o$,
  $n$) from obras where cancelada_em is null),$n$, 3);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$from obras where etapa_numero < 8 and data_fechamento is not null$o$,
  $n$from obras where etapa_numero < 8 and cancelada_em is null and data_fechamento is not null$n$);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$where o.data_instalacao between v_ini and v_fim or v_ini = '2000-01-01'::date$o$,
  $n$where o.cancelada_em is null and (o.data_instalacao between v_ini and v_fim or v_ini = '2000-01-01'::date)$n$);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$where o.data_fechamento between v_ini and v_fim or v_ini = '2000-01-01'::date$o$,
  $n$where o.cancelada_em is null and (o.data_fechamento between v_ini and v_fim or v_ini = '2000-01-01'::date)$n$);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$from obras o group by 1) t),$o$,
  $n$from obras o where o.cancelada_em is null group by 1) t),$n$);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$from obras o where o.cidade is not null group by 1) t)$o$,
  $n$from obras o where o.cidade is not null and o.cancelada_em is null group by 1) t)$n$);

select pg_temp.troca('public.get_metricas_origem(date,date)',
  $o$where coalesce(o.data_conclusao,o.data_instalacao,o.data_fechamento) between coalesce(p_ini$o$,
  $n$where o.cancelada_em is null and coalesce(o.data_conclusao,o.data_instalacao,o.data_fechamento) between coalesce(p_ini$n$, 2);

-- financeiro: DRE (faturado e por obra), desempenho, R$/Wp
select pg_temp.troca('public.get_dre_mensal(date,date)',
  $o$where coalesce(o.data_conclusao, o.data_instalacao, o.data_fechamento) between p_ini and p_fim$o$,
  $n$where o.cancelada_em is null and coalesce(o.data_conclusao, o.data_instalacao, o.data_fechamento) between p_ini and p_fim$n$);
select pg_temp.troca('public.get_dre_obras(date,date)',
  $o$where coalesce(o.data_conclusao, o.data_instalacao, o.data_fechamento) between p_ini and p_fim$o$,
  $n$where o.cancelada_em is null and coalesce(o.data_conclusao, o.data_instalacao, o.data_fechamento) between p_ini and p_fim$n$);
select pg_temp.troca('public.get_financeiro_desempenho(date,date)',
  $o$where coalesce(o.data_conclusao,o.data_instalacao,o.data_fechamento) between p_ini and p_fim$o$,
  $n$where o.cancelada_em is null and coalesce(o.data_conclusao,o.data_instalacao,o.data_fechamento) between p_ini and p_fim$n$);
select pg_temp.troca('public.get_kpis_financeiro(date,date)',
  $o$and o.data_fechamento between p_ini and p_fim$o$,
  $n$and o.data_fechamento between p_ini and p_fim
       and o.cancelada_em is null$n$);

-- conferências das 7h30 (financeiro e travas de campo)
select pg_temp.troca('public.conferir_financeiro()',
  $o$and not coalesce(o.cliente_externo,false)$o$,
  $n$and not coalesce(o.cliente_externo,false)
    and o.cancelada_em is null$n$);
select pg_temp.troca('public.conferir_financeiro()',
  $o$join obras o on o.id = d.obra_id;$o$,
  $n$join obras o on o.id = d.obra_id
  where o.cancelada_em is null;$n$);
select pg_temp.troca('public.conferir_financeiro()',
  $o$where coalesce(f.preco_negociado,0)>0 and not coalesce(f.dispensado,false)$o$,
  $n$where coalesce(f.preco_negociado,0)>0 and not coalesce(f.dispensado,false)
      and not exists (select 1 from obras oc where oc.id = f.obra_id and oc.cancelada_em is not null)$n$);
select pg_temp.troca('public.conferir_travas()',
  $o$from obras o where coalesce(o.trilha,'padrao')='padrao' and ($o$,
  $n$from obras o where coalesce(o.trilha,'padrao')='padrao' and o.cancelada_em is null and ($n$);
select pg_temp.troca('public.conferir_travas()',
  $o$where not coalesce(f.dispensado,false) and ($o$,
  $n$where not coalesce(f.dispensado,false) and o.cancelada_em is null and ($n$);

-- agenda, véspera, cobrança das fotos, link do instalador
select pg_temp.troca('public.get_agenda(text)',
  $o$where o.data_instalacao is not null$o$,
  $n$where o.data_instalacao is not null and o.cancelada_em is null$n$);
select pg_temp.troca('public.obras_para_lembrete()',
  $o$where o.data_instalacao = current_date + 1$o$,
  $n$where o.data_instalacao = current_date + 1 and o.cancelada_em is null$n$);
select pg_temp.troca('public.obras_cobranca_fotos()',
  $o$where b.data_instalacao is not null$o$,
  $n$where b.data_instalacao is not null and b.cancelada_em is null$n$);
select pg_temp.troca('public.get_obra_instalador(text,text)',
  $o$select * into v_obra from obras where slug = p_slug and instalador_token = p_token;$o$,
  $n$select * into v_obra from obras where slug = p_slug and instalador_token = p_token and cancelada_em is null;$n$);

-- travas
select pg_temp.troca('public.get_travas()',
  $o$from travas_tipos t join obras o on o.trava = t.codigo$o$,
  $n$from travas_tipos t join obras o on o.trava = t.codigo and o.cancelada_em is null$n$);
select pg_temp.troca('public.get_travas()',
  $o$(select count(*) from obras where trava is not null)$o$,
  $n$(select count(*) from obras where trava is not null and cancelada_em is null)$n$);
select pg_temp.troca('public.get_travas()',
  $o$where current_date - o.trava_em >= t.alerta_dias),$o$,
  $n$where current_date - o.trava_em >= t.alerta_dias and o.cancelada_em is null),$n$);
select pg_temp.troca('public.get_travas()',
  $o$from obras o join travas_tipos t on t.codigo=o.trava) y)$o$,
  $n$from obras o join travas_tipos t on t.codigo=o.trava where o.cancelada_em is null) y)$n$);
