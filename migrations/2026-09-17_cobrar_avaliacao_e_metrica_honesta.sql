-- 17/09/2026 — Cobrar a avaliação na mão, e parar de mostrar número falso.
--
-- Quatro coisas, todas saídas do diagnóstico do funil do Google:
--
-- A) get_horarios_resposta perde `lembretes_enviados`. Aquele KPI lia
--    `sum(nps.lembretes_google)`, e quem grava esse campo é só o
--    `registrar_nps_manual`, que põe 1 já no insert — 44 dos 51 eram o backfill
--    que a equipe digitou entre 08/08 e 02/09. O caminho real (nps-google-fila)
--    nunca incrementa. Era número com cara de autoridade e sem lastro (§3.1).
--    No lugar entram `automaticos` e `manuais`: quantas respostas vieram pela
--    esteira (origem 'cliente' ou 'whatsapp') e quantas a equipe digitou. Essa
--    é a divisão que importa hoje — 10 contra 44.
--
-- B) nps_cobranca_google(obra) monta o texto da segunda cobrança. O convite
--    automático sai UMA vez, minutos depois da resposta, e acabou; daí em
--    diante era no grupo, na mão, sem nada na tela. Agora tem botão na ficha,
--    e é a pessoa que clica — a aprovação humana da regra 3.5 é o clique.
--    O link do Google sai da `config.google_review_url` e o da pesquisa sai da
--    `relatorio_base_url`: nenhum dos dois chumbado na tela.
--
--    registrar_lembrete_google() volta a ter chamador (era código morto) e
--    ganha a trava de is_autorizado(), porque agora quem chama é a tela.
--
-- D) nps_para_lembrete_google() é APAGADA. Ninguém chamava desde que a fila
--    virou `nps.google_agendado_para`, e ela ficava na documentação parecendo
--    viva. Some junto a chave `lembrete_google_max`, que só ela lia — mesma
--    decisão da `solarview_ativo` em 12/09. A `lembrete_google_dias` FICA: é o
--    corte de dias do aviso das 8h desde hoje de manhã.

-- ---------------------------------------------------------------- A
create or replace function public.get_horarios_resposta()
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then return null; end if;
  return json_build_object(
    'por_hora', (select coalesce(json_agg(t order by t.hora), '[]'::json) from (
      select extract(hour from n.criado_em at time zone 'America/Sao_Paulo')::int as hora,
             count(*) as respostas
      from nps n group by 1) t),
    'por_dia_semana', (select coalesce(json_agg(t order by t.dia), '[]'::json) from (
      select extract(dow from n.criado_em at time zone 'America/Sao_Paulo')::int as dia,
             count(*) as respostas
      from nps n group by 1) t),
    'tempo_resposta_horas', (select round(avg(extract(epoch from (n.criado_em - o.nps_enviado_em))/3600)::numeric, 1)
      from nps n join obras o on o.id = n.obra_id where o.nps_enviado_em is not null),
    'google', (select json_build_object(
      'promotores', count(*) filter (where nota >= 9),
      'avaliaram', count(*) filter (where avaliou_google_em is not null),
      'pendentes', count(*) filter (where nota >= 9 and avaliou_google_em is null),
      -- quem veio pela esteira e quem a equipe digitou. Substitui o
      -- 'lembretes_enviados', que contava insert manual como se fosse lembrete.
      'automaticos', count(*) filter (where origem in ('cliente','whatsapp')),
      'manuais', count(*) filter (where origem not in ('cliente','whatsapp') or origem is null)
    ) from nps)
  );
end; $function$;

-- ---------------------------------------------------------------- B
create or replace function public.nps_cobranca_google(p_obra uuid)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v record; v_link text; v_base text; v_primeiro text; v_txt text; v_nome_brinde text;
begin
  if not public.pode_ver_posvenda(p_obra) then
    return json_build_object('erro','Sem permissão para este cliente.');
  end if;

  select o.cliente, o.whatsapp_grupo_id, o.slug, o.nps_token,
         n.nota, n.brinde, n.entregue_em, n.avaliou_google_em,
         coalesce(n.lembretes_google,0) as lembretes
    into v
  from obras o left join nps n on n.obra_id = o.id
  where o.id = p_obra;

  if not found then return json_build_object('erro','Obra não encontrada.'); end if;
  if v.nota is null then
    return json_build_object('erro','Este cliente ainda não respondeu a pesquisa.'); end if;
  if v.nota < 9 then
    return json_build_object('erro','A nota foi ' || v.nota || '. Convite para o Google só sai para 9 ou 10.'); end if;
  if v.avaliou_google_em is not null then
    return json_build_object('erro','Este cliente já avaliou no Google.'); end if;
  if coalesce(v.whatsapp_grupo_id,'') = '' then
    return json_build_object('erro','Esta obra não tem grupo no WhatsApp.'); end if;

  select valor into v_link from config where chave = 'google_review_url';
  if coalesce(v_link,'') = '' then
    return json_build_object('erro','Falta a chave google_review_url na config.'); end if;

  -- o endereço da pesquisa sai da mesma base do relatório público
  select replace(valor, 'relatorio.html', 'nps.html') into v_base
    from config where chave = 'relatorio_base_url';

  v_primeiro := split_part(btrim(v.cliente), ' ', 1);
  v_nome_brinde := case v.brinde when 'copo' then 'copo térmico personalizado'
                                 when 'fone' then 'fone Bluetooth' else null end;

  v_txt := '💚 *' || v_primeiro || ', posso te pedir 30 segundos?*' || E'\n\n'
        || 'Sua avaliação no Google ajuda outras famílias daqui a encontrarem energia '
        || 'solar de confiança — vale mais do que qualquer anúncio nosso. 🙏' || E'\n\n'
        || '⭐ ' || v_link || E'\n\n';

  if v_nome_brinde is not null and v.entregue_em is null then
    v_txt := v_txt || '🎁 Seu *' || v_nome_brinde || '* já está separado aqui, é só passar para retirar.' || E'\n\n';
  elsif v_nome_brinde is null and coalesce(v_base,'') <> '' then
    v_txt := v_txt || '🎁 Depois de avaliar, é só escolher seu brinde: *fone Bluetooth* ou '
          || '*copo térmico personalizado*.' || E'\n👉 ' || v_base || '?id=' || v.slug
          || '&t=' || v.nps_token || E'\n\n';
  end if;

  v_txt := v_txt || '*Equipe Polaris Energia Solar* ☀️';

  return json_build_object(
    'ok', true,
    'cliente', v.cliente,
    'grupo_id', v.whatsapp_grupo_id,
    'nota', v.nota,
    'cobrancas', v.lembretes,
    'texto', v_txt
  );
end; $function$;

revoke execute on function public.nps_cobranca_google(uuid) from public;
revoke execute on function public.nps_cobranca_google(uuid) from anon;
grant  execute on function public.nps_cobranca_google(uuid) to authenticated;

-- registrar_lembrete_google volta a ter chamador (a tela), então ganha trava
create or replace function public.registrar_lembrete_google(p_obra uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_autorizado() then return json_build_object('erro','Não autorizado'); end if;
  update nps
  set lembretes_google = coalesce(lembretes_google, 0) + 1,
      lembrete_google_em = now()
  where obra_id = p_obra;
  return json_build_object('ok', found);
end; $function$;

revoke execute on function public.registrar_lembrete_google(uuid) from public;
revoke execute on function public.registrar_lembrete_google(uuid) from anon;
grant  execute on function public.registrar_lembrete_google(uuid) to authenticated;

-- ---------------------------------------------------------------- D
drop function if exists public.nps_para_lembrete_google();
delete from config where chave = 'lembrete_google_max';
