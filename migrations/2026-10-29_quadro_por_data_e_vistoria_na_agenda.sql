-- 29/10: o quadro na ordem da data e a vistoria na agenda do escritório
-- (propostas 1, 2 e 3 da página "Agenda e prioridade das obras"; Vitor, 29/10:
-- "pode fazer a 1, 2 e 3, vistoria só no escritório").
--
-- 1) quadro_tempos(): desde quando cada obra está na etapa de agora e quanto
--    tempo 85% das obras levam para sair de cada coluna. O painel usa os dois
--    para o "N dias aqui" do cartão e para o cartão parado (vermelho).
--    "Desde quando" é a última entrada na etapa (fn_log_etapa só grava quando a
--    etapa muda). O tempo de cada coluna sai do etapas_historico dos últimos
--    `quadro_parado_janela_dias` (180), só da passagem que avançou, e fica de
--    fora:
--      - a entrada cadastrada depois, com a data e sem a hora (meia-noite UTC,
--        todas do 'sistema', de 17/03 a 03/06): em 22/07 a Lívia pôs em dia o
--        quadro, e 3 das 12 medições do Contrato Fechado eram essas obras saindo
--        da 1 para a 8 depois de 50 a 65 dias. Com elas o limite era 50 dias;
--        sem elas, 5;
--      - a passagem de menos de 1 hora: cartão arrastado por cima da coluna.
--    Coluna com menos de `quadro_parado_min_obras` (8) passagens medidas não
--    ganha limite (hoje a Boas-vindas, com 5, e toda a manutenção).
--    Medido em 29/10, trilha padrão: Contrato Fechado 4,8 dias · Documentação
--    7,4 · Aprovação 11,8 · Compra 6,4 · Entrega 23,7 · Execução 11,0 ·
--    Vistoria 8,1.
--
-- 2) get_agenda: a agenda geral (o link do escritório, config.agenda_token)
--    devolve também as vistorias abertas -- obra da trilha padrão na etapa 7
--    com prazo da concessionária --, para aparecerem no dia do prazo, em
--    laranja. A agenda de cada equipe continua só com as obras dela: a lista
--    sai vazia. A assinatura não muda: a página é pública (instalador.html,
--    sem login), e a conferir_saude_base acusa se o anon perder o acesso
--    (armadilha 26).

insert into public.config (chave, valor) values
  ('quadro_parado_pct', '85'),
  ('quadro_parado_janela_dias', '180'),
  ('quadro_parado_min_obras', '8'),
  ('quadro_execucao_folga_dias', '1')
on conflict (chave) do nothing;

create or replace function public.quadro_tempos()
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_pct numeric := coalesce((select nullif(valor, '')::numeric from config where chave = 'quadro_parado_pct'), 85);
  v_janela int := coalesce((select nullif(valor, '')::int from config where chave = 'quadro_parado_janela_dias'), 180);
  v_min int := coalesce((select nullif(valor, '')::int from config where chave = 'quadro_parado_min_obras'), 8);
  v_folga int := coalesce((select nullif(valor, '')::int from config where chave = 'quadro_execucao_folga_dias'), 1);
  v json;
begin
  if not is_autorizado() then return null; end if;
  with h as (
    select eh.obra_id, eh.etapa_numero, eh.entrou_em, eh.id,
           lag(eh.etapa_numero) over (partition by eh.obra_id order by eh.entrou_em, eh.id) as ant
      from etapas_historico eh
  ), entradas as (   -- cada vez que a obra entrou numa etapa
    select h.obra_id, h.etapa_numero, h.entrou_em, h.id,
           lead(h.entrou_em) over (partition by h.obra_id order by h.entrou_em, h.id) as saiu_em,
           lead(h.etapa_numero) over (partition by h.obra_id order by h.entrou_em, h.id) as prox
      from h where h.ant is distinct from h.etapa_numero
  ), atual as (
    select distinct on (e.obra_id) e.obra_id, e.etapa_numero, e.entrou_em
      from entradas e order by e.obra_id, e.entrou_em desc, e.id desc
  ), estadias as (
    select coalesce(o.trilha, 'padrao') as trilha, e.etapa_numero,
           extract(epoch from e.saiu_em - e.entrou_em) / 86400.0 as dias
      from entradas e join obras o on o.id = e.obra_id
     where e.saiu_em is not null and e.prox > e.etapa_numero
       and o.cancelada_em is null
       and e.saiu_em > now() - make_interval(days => v_janela)
       and e.saiu_em - e.entrou_em >= interval '1 hour'
       and date_trunc('day', e.entrou_em at time zone 'UTC') <> (e.entrou_em at time zone 'UTC')
  ), lim as (
    select s.trilha, s.etapa_numero, count(*) as n,
           round((percentile_cont(least(greatest(v_pct, 1), 99) / 100.0) within group (order by s.dias))::numeric, 1) as dias
      from estadias s group by 1, 2
  )
  select json_build_object(
    'pct', v_pct, 'janela_dias', v_janela, 'folga_execucao', v_folga,
    'desde', (select coalesce(json_agg(json_build_object('obra_id', a.obra_id, 'etapa', a.etapa_numero, 'entrou_em', a.entrou_em)), '[]'::json)
                from atual a join obras o on o.id = a.obra_id and o.etapa_numero = a.etapa_numero
               where o.cancelada_em is null),
    'limites', (select coalesce(json_agg(json_build_object('trilha', l.trilha, 'etapa', l.etapa_numero, 'dias', l.dias, 'n', l.n)
                                order by l.trilha, l.etapa_numero), '[]'::json)
                  from lim l where l.n >= v_min))
    into v;
  return v;
end $function$;

comment on function public.quadro_tempos() is
  'O quadro na ordem da data (29/10): desde quando cada obra está na etapa de agora (a última entrada no etapas_historico) e, por trilha e etapa, o tempo em que quadro_parado_pct (85%) das obras saíram da coluna nos últimos quadro_parado_janela_dias (180), sem as entradas cadastradas depois (meia-noite UTC) e sem passagem de menos de 1 hora. Coluna com menos de quadro_parado_min_obras passagens não tem limite. Só leitura, atrás de is_autorizado().';

-- armadilha 10: os dois revokes
revoke execute on function public.quadro_tempos() from public;
revoke execute on function public.quadro_tempos() from anon;
grant  execute on function public.quadro_tempos() to authenticated;
grant  execute on function public.quadro_tempos() to service_role;

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
    -- (Vitor, 29/10). Aberta = obra da trilha padrão na etapa 7, com prazo.
    'vistorias', (
      select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contrato', o.contrato,
        'concessionaria', coalesce(nullif(o.concessionaria, ''), 'CPFL'),
        'cpfl_solicitado_em', o.cpfl_solicitado_em, 'cpfl_prazo_em', o.cpfl_prazo_em
      ) order by o.cpfl_prazo_em, o.cliente), '[]'::json)
      from obras o
      where v_geral and o.cancelada_em is null
        and coalesce(o.trilha, 'padrao') = 'padrao' and o.etapa_numero = 7
        and o.cpfl_prazo_em is not null
        and o.cpfl_prazo_em >= current_date - interval '30 days'
    )
  );
end; $function$;
