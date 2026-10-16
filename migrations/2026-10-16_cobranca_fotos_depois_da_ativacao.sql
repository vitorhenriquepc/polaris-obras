-- APLICADA em 16/10. Caso que pediu: TANAKA CENTRO DE ABASTECIMENTO (4745).
--
-- O Vitor perguntou por que o instalador da TANAKA nunca foi cobrado do
-- relatório nem recebeu o link. Eram duas portas fechadas ao mesmo tempo:
--
--   1. A obra nunca teve DATA DE INSTALAÇÃO. É a data marcada no card que manda
--      à equipe o "Nova obra agendada" com o link do checklist (avisarInstalador),
--      e esta função só olha obra com data. A TANAKA ficou na etapa 6 de 05/10 a
--      16/10 sem data — a obra foi feita em 08–09/10, pelo grupo — e a cobrança
--      das 8h nunca a viu. (O painel agora pede a data: ver painel.html.)
--
--   2. Em 16/10 08:35 ela foi da 6 direto para a 8 (Sistema Ativo!). A cobrança
--      só valia nas etapas 6–7 (2–3 na manutenção): ativou, parou de cobrar para
--      sempre, com 0 de 11 fotos.
--
-- Esta migração fecha a segunda porta: a cobrança continua por N dias depois da
-- ativação (config.cobranca_fotos_dias_pos_ativacao, 30). O resto não muda —
-- precisa de data, de grupo da equipe, no máximo 2 avisos, um por dia, e só
-- enquanto faltar foto obrigatória. O texto (edge function cobranca-fotos) já
-- servia: "Faltam fotos no relatório … Instalada em DD/MM — há N dias".
--
-- Simulado antes de gravar: hoje a lista continua vazia (das 14 obras ativadas
-- nos últimos 45 dias, todas as da CJP têm 11/11 fotos, menos a TANAKA, que não
-- tem data; a 3067 é de equipe sem grupo). Com a data da TANAKA preenchida, ela
-- entra (0/11) na rodada seguinte das 8h (seg–sáb).

create or replace function public.obras_cobranca_fotos()
 returns table(id uuid, cliente text, contrato text, slug text, data_instalacao date, instalador text, instalador_grupo text, instalador_token text, obrig bigint, feitos bigint, assinado boolean, faltantes text, cobranca_qtd smallint, dias_atraso integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with base as (
    select o.*,
      (select count(*) from checklist_itens ci
        left join obra_itens_relatorio ov on ov.item_id=ci.id and ov.obra_id=o.id
        where checklist_exige(ci.obrigatorio, ci.obrig_tipos, o.tipo_manutencao)
          and coalesce(ci.trilha,'padrao')=coalesce(o.trilha,'padrao')
          and not coalesce(ov.oculto,false)) as n_obrig,
      (select count(distinct f.item_id) from fotos f
        join checklist_itens ci on ci.id=f.item_id
        left join obra_itens_relatorio ov on ov.item_id=ci.id and ov.obra_id=o.id
        where f.obra_id=o.id
          and checklist_exige(ci.obrigatorio, ci.obrig_tipos, o.tipo_manutencao)
          and coalesce(ci.trilha,'padrao')=coalesce(o.trilha,'padrao')
          and not coalesce(ov.oculto,false)) as n_feitos,
      (select string_agg('• '||coalesce(ov.titulo,ci.titulo), chr(10) order by ci.ordem)
        from checklist_itens ci
        left join obra_itens_relatorio ov on ov.item_id=ci.id and ov.obra_id=o.id
        where checklist_exige(ci.obrigatorio, ci.obrig_tipos, o.tipo_manutencao)
          and coalesce(ci.trilha,'padrao')=coalesce(o.trilha,'padrao')
          and not coalesce(ov.oculto,false)
          and not exists (select 1 from fotos f where f.obra_id=o.id and f.item_id=ci.id)) as falta
    from obras o
  )
  select b.id, b.cliente, b.contrato, b.slug,
         coalesce(b.data_fim, b.data_instalacao),
         e.nome, e.whatsapp_grupo_id, b.instalador_token,
         b.n_obrig, b.n_feitos, (b.aceite_em is not null), b.falta,
         b.cobranca_fotos_qtd,
         (current_date - coalesce(b.data_fim, b.data_instalacao))
  from base b
  join equipe e on e.id = b.instalador_id
  where b.data_instalacao is not null
    and coalesce(b.data_fim, b.data_instalacao) < current_date
    and ((coalesce(b.trilha,'padrao')='manutencao' and b.etapa_numero between 2 and 3)
      or (coalesce(b.trilha,'padrao')<>'manutencao' and b.etapa_numero between 6 and 7)
      -- 16/10 (TANAKA 4745): a obra pode ser ATIVADA antes do relatório. Até aqui
      -- a cobrança parava na última etapa e o instalador nunca mais era cobrado.
      -- Continua por N dias depois da ativação (config, padrão 30).
      or (public.obra_ativa(b.id)
          and public.obra_ativa_em(b.id) >= current_date
              - coalesce((select nullif(c.valor,'')::int from config c where c.chave = 'cobranca_fotos_dias_pos_ativacao'), 30)))
    and e.whatsapp_grupo_id is not null
    and b.cobranca_fotos_qtd < 2
    and (b.cobranca_fotos_em is null or b.cobranca_fotos_em < current_date)
    and b.n_feitos < b.n_obrig
  order by coalesce(b.data_fim, b.data_instalacao)
  limit 20;
$function$;

insert into config (chave, valor) values ('cobranca_fotos_dias_pos_ativacao', '30')
on conflict (chave) do nothing;
