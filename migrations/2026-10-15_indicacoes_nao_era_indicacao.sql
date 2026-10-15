-- APLICADA em 15/10 (todas as partes, na ordem do arquivo). A limpeza dos dados
-- (as 17 indicações) NÃO está aqui: foi só simulada e espera o OK do Vitor.
--
-- "Não era indicação" vira status próprio (15/10, plano das abas aprovado pelo Vitor).
--
-- Das 20 indicações registradas desde agosto, todas detectadas pela IA nos
-- grupos, NENHUMA fechou, e as 9 "novas" estavam paradas — mas lendo as
-- conversas, 8 delas não eram indicação: a conta de luz que o cliente ia mandar
-- para a nora (3 cópias), o vídeo do Wi-Fi para o filho, os contatos da
-- atendente da CPFL, e duas vontades genéricas de indicar, sem nome nem
-- telefone. Até aqui o único jeito de tirar uma dessas da frente era "perdida"
-- (o que já tinha sido feito com 8 em 27/08, com motivo "bug"), e perdida
-- entra na taxa de conversão como se fosse venda perdida.
--
-- E o falso alarme tinha um efeito escondido: regua_bloqueio e regua_do_dia
-- tratam "cliente já indicou" pela MENSAGEM classificada como indicação. Quem
-- teve um recado mal classificado nunca mais recebia o pedido de indicação da
-- régua (d90_indica2) — 4324 e 4620 estavam assim.
--
-- 1) indicacoes.descartada_em + status 'descartada' ("não era indicação").
-- 2) indicacao_descartar(id, motivo, reclassificar, simular): marca, guarda o
--    status anterior no motivo (nada se perde — regra 3.6) e, quando é falso
--    alarme, reclassifica a(s) mensagem(ns) daquele texto para 'geral' e ensina
--    a IA do webhook com UM exemplo em classificacoes_exemplo (o mesmo desenho
--    do corrigir_classificacao). Cópia de indicação verdadeira descarta SEM
--    reclassificar: a mensagem continua sendo indicação de verdade.
-- 3) indicacao_status passa a validar o status — aceitava qualquer texto.
-- 4) "Já indicou" vira uma regra só nos três lugares (envio da régua, régua do
--    dia e trajetória do cliente): indicação de verdade (não descartada) OU
--    mensagem classificada como indicação. Sem isso, a limpeza desbloquearia a
--    cliente do 4618 — que indicou a irmã, numa indicação registrada sem
--    mensagem — e ela receberia o pedido de indicação em 26/11.
-- 5) get_indicacoes, get_indicacoes_cliente e indicacoes_resumo deixam as
--    descartadas fora das contas (total, ranking, a pagar, ficha, funil).

alter table public.indicacoes add column if not exists descartada_em timestamptz;
comment on column public.indicacoes.descartada_em is
  'Quando alguém marcou que não era indicação (status descartada). O status anterior fica no motivo_perda.';

-- 3) status validado
create or replace function public.indicacao_status(p_id bigint, p_status text, p_motivo text default null::text,
  p_obra_gerada uuid default null::uuid, p_kwp numeric default null::numeric, p_contrato numeric default null::numeric)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_i record; v_calc json;
begin
  if not public.pode_agir_posvenda() then return json_build_object('erro','Sem permissão'); end if;
  -- até 15/10 aceitava qualquer texto; "não era indicação" tem caminho próprio
  if p_status is null or p_status not in ('nova','contatada','visita_agendada','visita_feita','proposta','fechada','perdida') then
    return json_build_object('erro', case when p_status = 'descartada'
      then 'Para dizer que não era indicação, use indicacao_descartar' else 'Status inválido' end);
  end if;
  select * into v_i from indicacoes where id = p_id;
  if v_i is null then return json_build_object('erro','Indicação não encontrada'); end if;
  update indicacoes set
    status = p_status,
    contatada_em = case when p_status='contatada' and contatada_em is null then now() else contatada_em end,
    visita_em = case when p_status in ('visita_feita','visita_agendada') and visita_em is null then now() else visita_em end,
    perdida_em = case when p_status='perdida' then now() else perdida_em end,
    motivo_perda = case when p_status='perdida' then p_motivo else motivo_perda end,
    obra_gerada_id = coalesce(p_obra_gerada, obra_gerada_id)
  where id = p_id;
  -- Ao fechar, calcula a recompensa
  if p_status = 'fechada' then
    v_calc := public.calcular_recompensa(coalesce(p_kwp, 0), p_contrato, v_i.indicador_obra_id);
    if (v_calc->>'erro') is null then
      update indicacoes set fechada_em = now(), faixa = v_calc->>'faixa',
        valor_previsto = (v_calc->>'valor_total')::numeric, valor_etapa2 = (v_calc->>'etapa2')::numeric,
        bonus_clube_pct = (v_calc->>'bonus_pct')::numeric
      where id = p_id;
    end if;
    return json_build_object('ok', true, 'calculo', v_calc);
  end if;
  return json_build_object('ok', true);
end; $function$;

-- 2) não era indicação
create or replace function public.indicacao_descartar(p_id bigint, p_motivo text, p_reclassificar boolean default true,
  p_simular boolean default false)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_i record; v_txt text; v_msgs int := 0; v_ex boolean := false;
  v_quem text := coalesce(auth.jwt() ->> 'email', 'equipe');
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.pode_agir_posvenda() then return json_build_object('erro','Sem permissão'); end if;
  if v_motivo is null then return json_build_object('erro','Diga por que não era indicação'); end if;
  select * into v_i from indicacoes where id = p_id;
  if v_i.id is null then return json_build_object('erro','Indicação não encontrada'); end if;
  if v_i.status = 'descartada' then return json_build_object('ok', true, 'ja_estava', true); end if;
  if v_i.status = 'fechada' or v_i.pago_etapa1_em is not null or v_i.pago_etapa2_em is not null then
    return json_build_object('erro','Indicação fechada ou com pagamento não pode ser descartada');
  end if;
  if p_reclassificar and v_i.mensagem_id is not null then
    select texto into v_txt from mensagens_recebidas where id = v_i.mensagem_id;
    if v_txt is not null then
      -- as cópias do mesmo recado também bloqueiam a régua: reclassifica todas
      select count(*) into v_msgs from mensagens_recebidas
       where obra_id = v_i.indicador_obra_id and contexto = 'indicacao' and texto = v_txt;
      v_ex := not exists (select 1 from classificacoes_exemplo where texto = v_txt and contexto = 'geral');
    end if;
  end if;
  if p_simular then
    return json_build_object('ok', true, 'simulado', true, 'id', p_id, 'status_antes', v_i.status,
      'mensagens_reclassificadas', v_msgs, 'exemplo_novo', v_ex);
  end if;
  update indicacoes set
    status = 'descartada', descartada_em = now(),
    -- o status anterior (e o motivo antigo, se havia) fica escrito
    motivo_perda = left(v_motivo || ' (antes: ' || coalesce(v_i.status, '?')
                        || coalesce(' — ' || nullif(v_i.motivo_perda, ''), '') || ')', 300)
  where id = p_id;
  if v_msgs > 0 then
    update mensagens_recebidas set contexto = 'geral'
     where obra_id = v_i.indicador_obra_id and contexto = 'indicacao' and texto = v_txt;
  end if;
  if v_ex then
    insert into classificacoes_exemplo (texto, contexto, corrigido_por) values (v_txt, 'geral', v_quem);
  end if;
  return json_build_object('ok', true, 'mensagens_reclassificadas', v_msgs, 'exemplo_novo', v_ex);
end $function$;

comment on function public.indicacao_descartar(bigint, text, boolean, boolean) is
  'Não era indicação: status descartada, motivo com o status anterior; no falso alarme reclassifica a mensagem para geral e ensina a IA do webhook. Simular primeiro (15/10).';

revoke execute on function public.indicacao_descartar(bigint, text, boolean, boolean) from public;
revoke execute on function public.indicacao_descartar(bigint, text, boolean, boolean) from anon;
grant  execute on function public.indicacao_descartar(bigint, text, boolean, boolean) to authenticated;
grant  execute on function public.indicacao_descartar(bigint, text, boolean, boolean) to service_role;

-- 4) "já indicou": uma regra só
create or replace function public.regua_bloqueio(p_obra uuid, p_modelo text)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_o record; v_m record; v_meses int;
begin
  select * into v_o from obras where id = p_obra;
  select * into v_m from regua_modelos where codigo = p_modelo;
  if v_o is null or v_m is null then return 'registro inexistente'; end if;

  if v_o.whatsapp_grupo_id is null then return 'sem grupo de WhatsApp'; end if;
  if v_o.optout_em is not null then return 'cliente pediu para sair'; end if;

  if v_m.condicao = 'com_optin' and (v_o.optin_em is null) then
    return 'sem autorização para marketing';
  end if;

  if v_m.condicao = 'sem_indicacao' then
    if v_o.optin_em is null then return 'sem autorização para marketing'; end if;
    -- indicação de verdade (mesmo registrada sem mensagem) ou recado classificado
    -- como indicação; "não era indicação" (descartada) não conta
    if exists (select 1 from mensagens_recebidas m
               where m.obra_id = p_obra and m.contexto = 'indicacao')
       or exists (select 1 from indicacoes i
               where i.indicador_obra_id = p_obra and coalesce(i.status, '') <> 'descartada') then
      return 'cliente já indicou';
    end if;
  end if;

  if v_m.condicao = 'requer_geracao' or v_m.codigo = 'd365_aniversario' then
    select t.meses into v_meses from public.obra_geracao_total(p_obra) t;
    if coalesce(v_meses,0) = 0 then return 'geração não registrada'; end if;
  end if;

  return null;
end; $function$;

do $x$
declare d text; n int;
begin
  -- regua_do_dia: a mesma regra do regua_bloqueio
  d := pg_get_functiondef('public.regua_do_dia()'::regprocedure);
  n := (length(d) - length(replace(d, 'when m.condicao = ''sem_indicacao'' and exists (', ''))) / length('when m.condicao = ''sem_indicacao'' and exists (');
  if n <> 1 then raise exception 'regua_do_dia: marcador 1 apareceu % vezes', n; end if;
  n := (length(d) - length(replace(d, 'where mr.obra_id = o.id and mr.contexto = ''indicacao'') then ''cliente já indicou''', ''))) / length('where mr.obra_id = o.id and mr.contexto = ''indicacao'') then ''cliente já indicou''');
  if n <> 1 then raise exception 'regua_do_dia: marcador 2 apareceu % vezes', n; end if;
  d := replace(d, 'when m.condicao = ''sem_indicacao'' and exists (', 'when m.condicao = ''sem_indicacao'' and (exists (');
  d := replace(d, 'where mr.obra_id = o.id and mr.contexto = ''indicacao'') then ''cliente já indicou''',
    'where mr.obra_id = o.id and mr.contexto = ''indicacao'')' || E'\n'
    || '                or exists (select 1 from indicacoes ii' || E'\n'
    || '                where ii.indicador_obra_id = o.id and coalesce(ii.status, '''') <> ''descartada'')) then ''cliente já indicou''');
  execute d;

  -- get_trajetoria_posvenda: o "já indicou" da tela segue a mesma regra do envio
  d := pg_get_functiondef('public.get_trajetoria_posvenda()'::regprocedure);
  n := (length(d) - length(replace(d, '(select count(*) from indicacoes i where i.indicador_obra_id = o.id) as qtd_indicacoes', ''))) / length('(select count(*) from indicacoes i where i.indicador_obra_id = o.id) as qtd_indicacoes');
  if n <> 1 then raise exception 'get_trajetoria_posvenda: marcador apareceu % vezes', n; end if;
  d := replace(d, '(select count(*) from indicacoes i where i.indicador_obra_id = o.id) as qtd_indicacoes',
    '((select count(*) from indicacoes i where i.indicador_obra_id = o.id and coalesce(i.status, '''') <> ''descartada'')' || E'\n'
    || '       + (select count(*) from mensagens_recebidas mr where mr.obra_id = o.id and mr.contexto = ''indicacao'')) as qtd_indicacoes');
  execute d;
end $x$;

-- 5) descartadas fora das contas
create or replace function public.get_indicacoes()
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_nivel text; v_eq uuid;
begin
  v_nivel := public.meu_nivel();
  if v_nivel = 'nenhum' then return null; end if;
  v_eq := public.minha_equipe_id();

  return json_build_object(
    'pode_agir', public.pode_agir_posvenda(),
    'resumo', (select json_build_object(
      'novas', count(*) filter (where i.status='nova'),
      'em_andamento', count(*) filter (where i.status in ('contatada','visita_agendada','visita_feita','proposta')),
      'fechadas', count(*) filter (where i.status='fechada'),
      'perdidas', count(*) filter (where i.status='perdida'),
      'descartadas', count(*) filter (where i.status='descartada'),
      'total', count(*) filter (where coalesce(i.status,'') <> 'descartada'),
      'conversao', case when count(*) filter (where i.status in ('fechada','perdida')) > 0
        then round(100.0 * count(*) filter (where i.status='fechada')
             / count(*) filter (where i.status in ('fechada','perdida')), 0) end,
      'a_pagar', coalesce(sum(
        case when i.status='fechada' and i.pago_etapa2_em is null
             then coalesce(i.valor_etapa2,0) else 0 end) +
        sum(case when i.visita_em is not null and i.pago_etapa1_em is null and i.status not in ('perdida','descartada')
             then coalesce(i.valor_etapa1,0) else 0 end), 0),
      'pago_total', coalesce(sum(
        case when i.pago_etapa1_em is not null then coalesce(i.valor_etapa1,0) else 0 end +
        case when i.pago_etapa2_em is not null then coalesce(i.valor_etapa2,0) else 0 end), 0)
    ) from indicacoes i join obras o on o.id=i.indicador_obra_id
      where v_nivel<>'vendedor' or o.vendedor_id=v_eq),

    'lista', (select coalesce(json_agg(t order by t.criado_em desc), '[]'::json) from (
      select i.id, i.codigo, i.nome_indicado, i.telefone_indicado, i.observacao,
             i.status, i.origem, i.criado_em, i.fechada_em, i.motivo_perda, i.descartada_em,
             i.valor_previsto, i.valor_etapa1, i.valor_etapa2, i.bonus_clube_pct,
             i.pago_etapa1_em, i.pago_etapa2_em, i.visita_em, i.faixa,
             o.id as indicador_id, o.cliente as indicador, o.contrato as indicador_contrato,
             o.cidade, (select e.nome from equipe e where e.id=i.vendedor_id) as vendedor
      from indicacoes i
      join obras o on o.id = i.indicador_obra_id
      where v_nivel<>'vendedor' or o.vendedor_id=v_eq
      order by i.criado_em desc
      limit 100
    ) t),

    'ranking', (select coalesce(json_agg(t order by t.conversoes desc, t.total desc), '[]'::json) from (
      select o.id, o.cliente, o.cidade,
             count(*) as total,
             count(*) filter (where i.status='fechada') as conversoes,
             coalesce(sum(case when i.status='fechada' then i.valor_previsto end),0) as ganhou,
             (select cn.nome from clube_niveis cn
               where cn.conversoes_min <= count(*) filter (where i.status='fechada')
               order by cn.ordem desc limit 1) as nivel,
             (select cn.icone from clube_niveis cn
               where cn.conversoes_min <= count(*) filter (where i.status='fechada')
               order by cn.ordem desc limit 1) as icone
      from indicacoes i join obras o on o.id=i.indicador_obra_id
      where (v_nivel<>'vendedor' or o.vendedor_id=v_eq) and coalesce(i.status,'') <> 'descartada'
      group by o.id, o.cliente, o.cidade
      limit 20
    ) t),

    'faixas', (select coalesce(json_agg(json_build_object(
        'codigo', f.codigo, 'nome', f.nome, 'valor_fixo', f.valor_fixo,
        'percentual', f.percentual, 'minimo', f.valor_minimo
      ) order by f.ordem), '[]'::json) from indicacao_faixas f),

    'clube', (select coalesce(json_agg(json_build_object(
        'nome', c.nome, 'icone', c.icone, 'min', c.conversoes_min,
        'bonus', c.bonus_pct, 'beneficio', c.beneficio
      ) order by c.ordem), '[]'::json) from clube_niveis c)
  );
end; $function$;

create or replace function public.get_indicacoes_cliente(p_obra uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if not public.pode_ver_posvenda(p_obra) then return null; end if;
  return json_build_object(
    'clube', public.nivel_clube(p_obra),
    'lista', (select coalesce(json_agg(json_build_object(
        'id', i.id, 'codigo', i.codigo, 'nome', i.nome_indicado,
        'telefone', i.telefone_indicado, 'status', i.status,
        'valor', i.valor_previsto, 'criado_em', i.criado_em,
        'pago1', i.pago_etapa1_em is not null, 'pago2', i.pago_etapa2_em is not null
      ) order by i.criado_em desc), '[]'::json)
      from indicacoes i where i.indicador_obra_id = p_obra and coalesce(i.status,'') <> 'descartada')
  );
end; $function$;

create or replace function public.indicacoes_resumo(p_obra uuid default null::uuid)
 returns table(registradas integer, com_telefone integer, contatadas integer, fechadas integer, a_pagar integer, valor_a_pagar numeric)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select count(*)::int,
         count(*) filter (where length(regexp_replace(coalesce(telefone_indicado,''),'\D','','g')) >= 10)::int,
         count(*) filter (where contatada_em is not null)::int,
         count(*) filter (where fechada_em is not null)::int,
         count(*) filter (where fechada_em is not null and pago_etapa1_em is null)::int,
         coalesce(sum(coalesce(valor_etapa1,0) + coalesce(valor_etapa2,0))
                  filter (where fechada_em is not null and pago_etapa1_em is null), 0)
  from indicacoes
  where (p_obra is null or indicador_obra_id = p_obra) and coalesce(status,'') <> 'descartada';
$function$;

-- 6) Achado na revisão: indicacao_status e gerar_codigo_indicacao estavam com
--    EXECUTE para PUBLIC/anon (armadilha 10). Nenhuma página sem login usa as
--    duas — conferido em cliente, relatorio, nps e instalador.html.
revoke execute on function public.indicacao_status(bigint, text, text, uuid, numeric, numeric) from public;
revoke execute on function public.indicacao_status(bigint, text, text, uuid, numeric, numeric) from anon;
grant  execute on function public.indicacao_status(bigint, text, text, uuid, numeric, numeric) to authenticated;
grant  execute on function public.indicacao_status(bigint, text, text, uuid, numeric, numeric) to service_role;
revoke execute on function public.gerar_codigo_indicacao() from public;
revoke execute on function public.gerar_codigo_indicacao() from anon;
grant  execute on function public.gerar_codigo_indicacao() to authenticated;
grant  execute on function public.gerar_codigo_indicacao() to service_role;

-- 7) Achado na simulação: o gatilho trava_indicacao só deixa indicação SEM
--    telefone ficar como nova ou perdida — e recusou o primeiro descarte. "Não
--    era indicação" é justamente o caso sem telefone: entra na lista do que pode.
create or replace function public.trava_indicacao()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare tem_fone boolean;
begin
  tem_fone := coalesce(length(regexp_replace(coalesce(new.telefone_indicado,''),'\D','','g')), 0) >= 10;

  -- sem telefone, a indicacao nao sai de "nova": nome solto e intencao, nao indicacao
  if not tem_fone and (new.contatada_em is not null or new.visita_em is not null
                       or new.fechada_em is not null)
     and coalesce(new.status,'nova') <> 'descartada' then
    raise exception 'Indicação sem telefone não avança: registre o número de % antes',
      coalesce(nullif(btrim(new.nome_indicado),''),'quem foi indicado') using errcode='P0001';
  end if;
  -- "não era indicação" (descartada, 15/10) é justamente o caso sem telefone
  if not tem_fone and coalesce(new.status,'nova') not in ('nova','perdida','descartada') then
    raise exception 'Indicação sem telefone só pode ficar como nova ou perdida' using errcode='P0001';
  end if;

  -- brinde/premio so quando fecha
  if (new.pago_etapa1_em is not null or new.pago_etapa2_em is not null)
     and new.fechada_em is null then
    raise exception 'Só dá para pagar indicação depois que o indicado fecha' using errcode='P0001';
  end if;

  -- fechou sem estar contatada? registra o contato junto, para o funil nao mentir
  if new.fechada_em is not null and new.contatada_em is null then
    new.contatada_em := new.fechada_em;
  end if;

  return new;
end $function$;

-- 8) Achado na revisão: indicação que a IA detecta nunca vem com telefone (20
--    de 20 vieram sem — as 3 com número eram o falso alarme do condomínio), e o
--    trava_indicacao não deixa indicação sem telefone avançar. Ou seja: nem a
--    indicação de verdade da irmã (4618) conseguia andar no funil, e não havia
--    tela nem função para pôr o número. indicacao_telefone resolve isso.
create or replace function public.indicacao_telefone(p_id bigint, p_telefone text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_d text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'); v_i record;
begin
  if not public.pode_agir_posvenda() then return json_build_object('erro','Sem permissão'); end if;
  -- aceita com ou sem o 55; guarda sem, como os telefones de cliente
  if length(v_d) in (12, 13) and left(v_d, 2) = '55' then v_d := substr(v_d, 3); end if;
  if length(v_d) not in (10, 11) then
    return json_build_object('erro','Telefone com DDD: 18 99999-9999');
  end if;
  select * into v_i from indicacoes where id = p_id;
  if v_i.id is null then return json_build_object('erro','Indicação não encontrada'); end if;
  if v_i.status in ('descartada','fechada') then
    return json_build_object('erro','Esta indicação já está ' || case when v_i.status = 'fechada' then 'fechada' else 'marcada como não era indicação' end);
  end if;
  update indicacoes set telefone_indicado = v_d where id = p_id;
  return json_build_object('ok', true, 'telefone', v_d);
end $function$;

revoke execute on function public.indicacao_telefone(bigint, text) from public;
revoke execute on function public.indicacao_telefone(bigint, text) from anon;
grant  execute on function public.indicacao_telefone(bigint, text) to authenticated;
grant  execute on function public.indicacao_telefone(bigint, text) to service_role;

-- 9) A aba Hoje mostra o recado que originou a indicação (quem decide se era
--    indicação precisa ler o que o cliente escreveu): get_indicacoes devolve
--    `mensagem`. Mesmo jeito de emendar das outras: marcador que tem de
--    aparecer uma vez só, senão nada muda.
do $x$
declare d text; n int; m text := 'i.status, i.origem, i.criado_em, i.fechada_em, i.motivo_perda, i.descartada_em,';
begin
  d := pg_get_functiondef('public.get_indicacoes()'::regprocedure);
  n := (length(d) - length(replace(d, m, ''))) / length(m);
  if n <> 1 then raise exception 'get_indicacoes: marcador apareceu % vezes', n; end if;
  d := replace(d, m, m || E'\n' || '             (select left(mr.texto, 300) from mensagens_recebidas mr where mr.id = i.mensagem_id) as mensagem,');
  execute d;
end $x$;
