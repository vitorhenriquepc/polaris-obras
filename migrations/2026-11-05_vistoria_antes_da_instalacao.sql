-- 05/11: vistoria da concessionária pedida ANTES da instalação.
--
-- O Vitor passou a pedir a vistoria da CPFL antes de a obra começar, para os 5
-- dias úteis da concessionária correrem junto com a instalação. Preencher a data
-- no card levava a obra da Execução para a Vistoria (trg_cpfl) e mandava o texto
-- de sempre da cpfl_texto, que abre com "Sua instalação foi concluída". Em 05/11,
-- das 10:44 às 10:48, quatro clientes leram isso com a instalação marcada para
-- dali a 4 a 6 dias (a cópia de cada uma voltou do grupo):
--
--   DOLORES (4914)  instalação 09/11 · Gledson (4903) 09/11
--   Renan (4889)    10/11            · Marcelo (4966) 11/11
--
-- O Vitor explicou à Dolores por áudio às 10:45. Decisão dele (05/11, "pode fazer
-- a vistoria assim e volta a Dolores pra execução"):
--
--   1) texto próprio quando a instalação ainda vai acontecer (abaixo);
--   2) a obra fica na Execução até o relatório do instalador, que é quem a leva
--      para a Vistoria. Isso é o gatilho, e ele vai em arquivo à parte
--      (2026-11-05_vistoria_antes_da_instalacao_etapa.sql), junto do painel,
--      depois das 18h: o painel de agora só avisa a vistoria com a obra na 7, e a
--      obra que ficasse na 6 não teria aviso nenhum;
--   3) o foto-obra lembra o prazo na mensagem do relatório (edge function v17);
--   4) a vistoria segue na agenda do escritório, no dia do prazo, também com a
--      obra ainda na Execução.
--
-- "Instalação por fazer" (instalacao_pendente): o relatório do instalador não
-- saiu e o último dia marcado (a instalação, ou o término se for depois) é hoje
-- ou depois, no dia de Brasília. Sem data de instalação não dá para saber -- a
-- TANAKA (4745) ficou na 6 sem data com a instalação feita --, e fica o texto de
-- sempre; o painel pergunta antes (arquivo da etapa).
--
-- Até as 18h, com o gatilho antigo: quem preencher a data da vistoria antes da
-- instalação leva a obra para a 7, como hoje, mas o cliente já lê o texto novo.
-- Rodar de novo não muda nada.

create or replace function public.instalacao_pendente(p_relatorio_em timestamptz, p_inicio date, p_fim date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  -- a instalação ainda vai acontecer, ou está acontecendo: o relatório do
  -- instalador não saiu e o último dia marcado é hoje ou depois (Brasília).
  -- Sem data de instalação, false: não dá para dizer (TANAKA 4745).
  select p_relatorio_em is null and p_inicio is not null
     and greatest(p_inicio, p_fim) >= (now() at time zone 'America/Sao_Paulo')::date;
$function$;

comment on function public.instalacao_pendente(timestamptz, date, date) is
  'A instalação ainda vai acontecer (05/11, vistoria pedida antes da instalação): relatório do instalador não enviado e a data de instalação, ou o término se for depois, é hoje ou depois no dia de Brasília. Sem data, false. Usada pela cpfl_texto e pelo trg_cpfl.';

revoke execute on function public.instalacao_pendente(timestamptz, date, date) from public;
revoke execute on function public.instalacao_pendente(timestamptz, date, date) from anon;
grant  execute on function public.instalacao_pendente(timestamptz, date, date) to authenticated, service_role;

create or replace function public.cpfl_texto(p_obra uuid)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  o record; v_nome text; v_conc text; v_link text; v_corrige boolean; v_conta_de date;
  v_sem text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
  v_prazo text; v_texto text; v_curta boolean; v_da_conc boolean;
  v_antes boolean; v_fim date; v_inst text;
begin
  if not is_autorizado() then return null; end if;
  select cliente, slug, cpfl_solicitado_em, cpfl_prazo_em, cpfl_avisado_em, cpfl_avisado_prazo,
         whatsapp_grupo_id, concessionaria, etapa_numero, coalesce(trilha, 'padrao') as trilha,
         relatorio_enviado_em, data_instalacao, data_fim
    into o from obras where id = p_obra;
  if not found then
    return json_build_object('erro', 'Obra não encontrada');
  end if;
  if o.trilha <> 'padrao' then
    return json_build_object('erro', 'A vistoria da concessionária só tem aviso automático em obra de instalação');
  end if;
  if o.cpfl_solicitado_em is null then
    return json_build_object('erro', 'Preencha a data em que a vistoria foi solicitada');
  end if;
  -- sem grupo o texto ainda serve (o "enviar no WhatsApp" do card manda para o
  -- celular do cliente); quem recusa mandar no grupo é a tela, pelo `grupo` nulo

  v_conc  := coalesce(nullif(trim(o.concessionaria), ''), 'concessionária de energia');
  v_nome  := split_part(trim(o.cliente), ' ', 1);
  v_nome  := upper(substr(v_nome, 1, 1)) || lower(substr(v_nome, 2));
  v_link  := coalesce((select valor from config where chave = 'cliente_base_url'),
                      'https://obras.polarisenergiasolar.com/cliente.html') || '?id=' || o.slug;
  -- o primeiro dos 5 dias úteis: o dia útil seguinte à solicitação
  v_conta_de := soma_dias_uteis(o.cpfl_solicitado_em, 1);
  v_prazo := to_char(o.cpfl_prazo_em, 'DD/MM') || ' (' || v_sem[extract(dow from o.cpfl_prazo_em)::int + 1] || ')';
  v_corrige := o.cpfl_avisado_prazo is not null and o.cpfl_avisado_prazo is distinct from o.cpfl_prazo_em;
  -- o "Relatório oficial" do foto-obra acabou de dizer que a instalação
  -- terminou e trouxe o link de acompanhamento: não repetir (Vitor, 05/10)
  v_curta := not v_corrige and o.relatorio_enviado_em > now() - interval '48 hours';
  -- prazo que não sai da conta dos 5 dias úteis: foi a concessionária que deu
  -- um prazo novo (LUCIANA 4750, 05/10: "liberação do atendimento até 07/10").
  -- Aí o texto não pode falar em "data da solicitação corrigida" nem em
  -- "5 dias úteis a partir de", porque a conta não fecha.
  v_da_conc := o.cpfl_prazo_em is distinct from soma_dias_uteis(o.cpfl_solicitado_em, 5);
  -- vistoria pedida ANTES da instalação (Vitor, 05/11): o texto de sempre abre
  -- com "Sua instalação foi concluída", e quatro clientes leram isso em 05/11
  -- com a instalação marcada para 09 a 11/11 (DOLORES 4914 e mais três)
  v_antes := public.instalacao_pendente(o.relatorio_enviado_em, o.data_instalacao, o.data_fim);
  v_fim := greatest(o.data_instalacao, o.data_fim);
  if v_antes then
    v_inst := to_char(o.data_instalacao, 'DD/MM') || ' (' || v_sem[extract(dow from o.data_instalacao)::int + 1] || ')'
      || case when v_fim > o.data_instalacao
              then ' a ' || to_char(v_fim, 'DD/MM') || ' (' || v_sem[extract(dow from v_fim)::int + 1] || ')'
              else '' end;
  end if;

  if v_da_conc then
    v_texto := case when o.cpfl_avisado_em is not null or o.cpfl_avisado_prazo is not null
                    then '📅 *Atualização da vistoria*' else '📅 *Vistoria da ' || v_conc || '*' end
      || chr(10) || chr(10)
      || 'Olá, ' || v_nome || '! A ' || v_conc || ' nos informou um novo prazo: '
      || 'a inspeção e a troca do medidor devem acontecer até *' || v_prazo || '*.' || chr(10) || chr(10)
      || 'Só precisa ter alguém no local para dar acesso ao padrão. '
      || case when v_antes then 'Com a instalação pronta e o medidor trocado, seu sistema é ligado e começa a gerar. 💚'
              else 'Assim que o medidor for trocado, seu sistema é ligado e começa a gerar. 💚' end
      || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  elsif v_corrige then
    v_texto := '📅 *Atualização da vistoria*' || chr(10) || chr(10)
      || 'Olá, ' || v_nome || '! A data da solicitação da vistoria da ' || v_conc || ' foi corrigida para *'
      || to_char(o.cpfl_solicitado_em, 'DD/MM') || '*.' || chr(10) || chr(10)
      || 'Os *5 dias úteis* contam a partir de ' || to_char(v_conta_de, 'DD/MM')
      || ', então a inspeção e a troca do medidor devem acontecer até *' || v_prazo || '*.' || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  elsif v_curta then
    v_texto := '📅 *Vistoria da ' || v_conc || ' solicitada, ' || v_nome || '!*' || chr(10) || chr(10)
      || 'A troca do medidor deve acontecer até *' || v_prazo || '* — são 5 dias úteis, contando de '
      || to_char(v_conta_de, 'DD/MM') || '.' || chr(10) || chr(10)
      || 'Só precisa ter alguém no local para dar acesso ao padrão. '
      || 'Depois disso o sistema é ligado e começa a gerar. 💚';
  elsif v_antes then
    -- o texto que o Vitor aprovou em 05/11
    v_texto := '📋 *' || v_nome || ', já pedimos a vistoria da ' || v_conc || '!*' || chr(10) || chr(10)
      || 'Para ganhar tempo, fizemos o pedido antes da instalação, e assim o prazo da ' || v_conc
      || ' corre junto com a obra.' || chr(10) || chr(10)
      || '🔧 Instalação: *' || v_inst || '*' || chr(10)
      || '🔌 Vistoria e troca do medidor: até *' || v_prazo || '*' || chr(10)
      || '_(a ' || v_conc || ' tem até 5 dias úteis, contando a partir de ' || to_char(v_conta_de, 'DD/MM') || ')_'
      || chr(10) || chr(10)
      || 'Não precisa fazer nada. Só é importante que alguém esteja no local para dar acesso ao padrão, '
      || 'e que o portão esteja destrancado se o medidor ficar dentro.' || chr(10) || chr(10)
      || 'Com a instalação pronta e o medidor trocado, seu sistema é ligado e começa a gerar. Qualquer dúvida, é só chamar aqui. 💚'
      || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  else
    v_texto := 'Boa notícia, ' || v_nome || '! ☀️' || chr(10) || chr(10)
      || 'Sua instalação foi concluída e já solicitamos a *vistoria da ' || v_conc || '*.' || chr(10) || chr(10)
      || 'A concessionária tem até *5 dias úteis* para fazer a inspeção e a troca do medidor. '
      || 'Contando a partir de ' || to_char(v_conta_de, 'DD/MM') || ', isso deve acontecer até *' || v_prazo || '*.'
      || chr(10) || chr(10)
      || 'Não precisa fazer nada. Só é importante que alguém esteja no local para dar acesso ao padrão, '
      || 'e que o portão esteja destrancado se o medidor ficar dentro.' || chr(10) || chr(10)
      || 'Assim que o medidor for trocado, seu sistema é ligado e começa a gerar. Qualquer dúvida, é só chamar aqui. 💚'
      || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  end if;

  return json_build_object(
    'ok', true, 'cliente', o.cliente, 'solicitado', o.cpfl_solicitado_em, 'conta_de', v_conta_de,
    'prazo', o.cpfl_prazo_em, 'etapa', o.etapa_numero, 'grupo', o.whatsapp_grupo_id,
    'ja_avisado', o.cpfl_avisado_em,
    -- a data mudou mas o prazo que o cliente leu continua o mesmo: nada a dizer
    'mesmo_prazo', coalesce(o.cpfl_avisado_em is null and o.cpfl_avisado_prazo = o.cpfl_prazo_em, false),
    'correcao', v_corrige,
    'curta', v_curta and not v_da_conc,
    'prazo_da_concessionaria', v_da_conc,
    -- vistoria pedida antes da instalação (05/11): a tela diz isso a quem manda,
    -- e pergunta antes quando o prazo da concessionária vence antes de a
    -- instalação acabar
    'instalacao_pendente', v_antes,
    'instalacao', o.data_instalacao,
    'instalacao_ate', v_fim,
    'prazo_antes_da_instalacao', coalesce(v_antes and o.cpfl_prazo_em < v_fim, false),
    'texto', v_texto);
end; $function$;

-- a agenda do escritório: a vistoria aberta aparece no dia do prazo também com a
-- obra ainda na Execução (pedida antes da instalação). Antes era só a etapa 7.
create or replace function public.get_agenda(p_token text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_geral boolean := false;
  v_inst_id uuid := null;
  v_inst_nome text := null;
begin
  select exists(select 1 from config where chave = 'agenda_token' and valor = p_token)
    into v_geral;

  if not v_geral then
    select e.id, e.nome into v_inst_id, v_inst_nome
    from equipe e
    where e.agenda_token = p_token and coalesce(e.ativo, true)
    limit 1;
    if v_inst_id is null then
      return null;
    end if;
  end if;

  return json_build_object(
    'escopo', case when v_geral then 'geral' else 'instalador' end,
    'titulo', case when v_geral then 'Agenda geral' else coalesce(v_inst_nome, 'Agenda') end,
    'obras', (
      select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contrato', o.contrato, 'potencia_kwp', o.potencia_kwp,
        'data_instalacao', o.data_instalacao, 'data_fim', o.data_fim, 'slug', o.slug, 'token', o.instalador_token,
        'etapa_numero', o.etapa_numero, 'trilha', o.trilha,
        'instalador', (select e2.nome from equipe e2 where e2.id = o.instalador_id),
        'tipo_telhado', o.tipo_telhado, 'endereco', o.endereco,
        'qtd_modulos', o.qtd_modulos, 'inversor_descricao', o.inversor_descricao,
        'tem_estrutura', o.tem_estrutura, 'tem_cabo', o.tem_cabo
      ) order by o.data_instalacao), '[]'::json)
      from obras o
      where o.data_instalacao is not null and o.cancelada_em is null
        and greatest(o.data_instalacao, o.data_fim) >= current_date - interval '30 days'
        and (v_geral or o.instalador_id = v_inst_id)
    ),
    -- a vistoria da concessionária, no dia do prazo: só na agenda do escritório
    -- (Vitor, 29/10). Aberta = obra da trilha padrão na etapa 7, com prazo, ou
    -- ainda antes dela com a vistoria já pedida (antes da instalação, 05/11).
    'vistorias', (
      select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contrato', o.contrato,
        'concessionaria', coalesce(nullif(o.concessionaria, ''), 'CPFL'),
        'cpfl_solicitado_em', o.cpfl_solicitado_em, 'cpfl_prazo_em', o.cpfl_prazo_em,
        'antes_da_instalacao', o.etapa_numero < 7,
        'data_instalacao', o.data_instalacao, 'data_fim', o.data_fim
      ) order by o.cpfl_prazo_em, o.cliente), '[]'::json)
      from obras o
      where v_geral and o.cancelada_em is null
        and coalesce(o.trilha, 'padrao') = 'padrao'
        and (o.etapa_numero = 7 or (o.etapa_numero < 7 and o.cpfl_solicitado_em is not null))
        and o.cpfl_prazo_em is not null
        and o.cpfl_prazo_em >= current_date - interval '30 days'
    )
  );
end; $function$;

-- As quatro obras de 05/11 voltam para a Execução (o Vitor pediu a da Dolores; as
-- outras três estão no mesmo caso). Nada sai para o cliente: quem manda mensagem
-- de etapa é o painel, não o banco. Só volta se a instalação ainda está por fazer.
do $do$
declare n int;
begin
  -- quem moveu aparece na linha do tempo: o fn_log_etapa lê o e-mail do JWT, e
  -- uma migração não tem JWT -- sairia "sistema", que é a assinatura do foto-obra
  perform set_config('request.jwt.claims',
    json_build_object('email', 'claude, a pedido do Vitor (05/11)')::text, true);
  update public.obras set etapa_numero = 6
   where contrato in ('4914', '4903', '4889', '4966')
     and etapa_numero = 7 and coalesce(trilha, 'padrao') = 'padrao' and cancelada_em is null
     and public.instalacao_pendente(relatorio_enviado_em, data_instalacao, data_fim);
  get diagnostics n = row_count;
  raise notice 'obras de volta para a Execução: %', n;
  perform set_config('request.jwt.claims', '', true);
end $do$;
