CREATE OR REPLACE FUNCTION public.get_aprovacoes(p_situacao text DEFAULT 'aguardando'::text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(json_build_object(
     'id', a.id, 'tipo', a.tipo, 'texto', a.texto, 'motivo', a.motivo,
     'situacao', a.situacao, 'criada_em', a.criada_em,
     'decidida_em', a.decidida_em, 'decidida_por', a.decidida_por,
     'enviada_em', a.enviada_em, 'erro', a.erro,
     'cliente', c.nome, 'contrato', o.contrato, 'usina', u.apelido,
     'usina_id', a.usina_id, 'obra_id', a.obra_id,
     'tem_grupo', (o.whatsapp_grupo_id is not null),
     'saiu', (o.optout_em is not null)
   ) order by a.criada_em desc),'[]'::json) into v
  from mensagem_aprovacao a
  left join obras o on o.id=a.obra_id
  left join clientes c on c.id=o.cliente_id
  left join usinas u on u.id=a.usina_id
  where (p_situacao='todas' or a.situacao=p_situacao);
  return v;
end $function$
