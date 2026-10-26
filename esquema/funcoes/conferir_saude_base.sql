CREATE OR REPLACE FUNCTION public.conferir_saude_base()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  select coalesce(json_agg(json_build_object('achado', achado, 'qtd', qtd)),'[]'::json) into v
  from (
    -- 23/09: as páginas que o cliente e o instalador abrem sem login dependem
    -- destas funções. Sem EXECUTE para o anon o link devolve 401 — e quem testa
    -- logado no escritório vê funcionando. Ficou assim de ~26/08 a 23/09.
    select 'pagina publica sem acesso (link do cliente ou instalador quebrado)' as achado, count(*) as qtd
      from unnest(array['get_acompanhamento(text)','get_relatorio_publico(text)',
        'get_nps(text,text)','salvar_nps(text,text,smallint,text)','salvar_brinde(text,text,text)',
        'declarar_avaliacao_google(text,text)','get_obra_instalador(text,text)','get_agenda(text)']) f
      where not coalesce(has_function_privilege('anon', to_regprocedure('public.'||f), 'execute'), false)
    union all
    select 'usina sem monitoramento', count(*) from usinas u where u.ativa
      and not exists (select 1 from usina_monitoramento m where m.usina_id=u.id and m.ativo)
    union all
    select 'usina sem obra', count(*) from usinas u where u.ativa
      and not exists (select 1 from obra_usina x where x.usina_id=u.id)
    union all
    select 'obra finalizada sem usina', count(*) from obras o where o.status='Finalizado' and coalesce(o.trilha,'padrao') = 'padrao'
      and not exists (select 1 from obra_usina x where x.obra_id=o.id)
    union all
    select 'monitoramento duplicado', count(*) from (
      select id_externo from usina_monitoramento where ativo group by 1 having count(*)>1) z
    union all
    select 'previsao incompleta', count(*) from (
      select usina_id from usina_previsao group by 1 having count(*) <> 12) y
    union all
    select 'clima atrasado (mais de 3 dias)',
      case when (select max(dia) from clima_dia) < current_date - 3 then 1 else 0 end
    union all
    select 'geracao diaria atrasada (mais de 2 dias)',
      case when (select max(dia) from usina_dia) < current_date - 2 then 1 else 0 end
    -- NOVAS, do pente fino
    union all
    select 'mensagem aprovada e nao enviada ha mais de 3 dias', count(*) from regua_contatos
      where status='pendente' and status_aprovacao='aprovada' and data_programada < current_date - 3
    union all
    select 'esperando aprovacao ha mais de 7 dias', count(*) from regua_contatos
      where status='pendente' and status_aprovacao='aguardando' and data_programada < current_date - 7
    union all
    select 'aprovada com limite vencido (nunca vai sair)', count(*) from regua_contatos
      where status='pendente' and status_aprovacao='aprovada' and data_limite < current_date
    union all
    select 'modelo escrito por IA sem exigir aprovacao', count(*) from regua_modelos
      where gerado_por_ia and not coalesce(precisa_aprovacao,false)
    union all
    select 'item de modelo IA sem texto proprio', count(*) from regua_contatos c
      join regua_modelos m on m.codigo=c.modelo
      where m.texto='{texto_custom}' and coalesce(c.texto_custom,'')='' and c.status='pendente'
    union all
    select 'item na fila para quem pediu para sair', count(*) from regua_fila(200) f
      join obras o on o.id=f.obra_id where o.optout_em is not null
    union all
    select 'valor do projeto divergente do financeiro', count(*) from obras o
      join obra_financeiro f on f.obra_id=o.id
      where coalesce(o.valor_projeto,0)>0 and coalesce(f.preco_negociado,0)>0
        and abs(o.valor_projeto - f.preco_negociado) > 1
    union all
    select 'arquivo de relatorio sem registro', count(*) from storage.objects s
      where s.bucket_id='relatorios-obras'
        and not exists (select 1 from obra_relatorios r where r.arquivo_path = s.name)
        and s.created_at < now() - interval '24 hours'
  ) t where qtd > 0;
  return v;
end $function$
