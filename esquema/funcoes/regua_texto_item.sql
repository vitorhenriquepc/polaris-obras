CREATE OR REPLACE FUNCTION public.regua_texto_item(p_item bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  select rc.*, rm.texto as modelo_texto, rm.gerado_por_ia
    into v
  from regua_contatos rc join regua_modelos rm on rm.codigo = rc.modelo
  where rc.id = p_item;
  if v is null then return null; end if;
  -- mensagem escrita pela IA: usa o texto do proprio item
  if coalesce(v.texto_custom,'') <> '' then return v.texto_custom; end if;
  return regua_texto(v.obra_id, v.modelo);
end $function$
