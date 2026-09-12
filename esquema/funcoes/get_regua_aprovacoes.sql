CREATE OR REPLACE FUNCTION public.get_regua_aprovacoes()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(json_build_object(
    'id', c.id, 'modelo', c.modelo, 'nome_modelo', m.nome,
    'cliente', o.cliente, 'contrato', o.contrato, 'obra_id', o.id, 'usina_id', c.usina_id,
    'texto', coalesce(c.texto_custom, regua_texto(c.obra_id, c.modelo)),
    'motivo', c.bloqueio_motivo,
    'programada', c.data_programada,
    'bloqueio', case when o.whatsapp_grupo_id is null then 'esta obra não tem grupo no WhatsApp'
                     when o.optout_em is not null then 'este cliente pediu para sair'
                     else null end
  ) order by c.criado_em),'[]'::json) into v
  from regua_contatos c
  join regua_modelos m on m.codigo=c.modelo
  join obras o on o.id=c.obra_id
  where c.status='pendente' and c.status_aprovacao='aguardando';
  return v;
end $function$
