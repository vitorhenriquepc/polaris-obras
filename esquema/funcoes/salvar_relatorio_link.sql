CREATE OR REPLACE FUNCTION public.salvar_relatorio_link(p_obra uuid, p_titulo text, p_url text, p_origem text DEFAULT 'auvo'::text, p_data date DEFAULT NULL::date)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if coalesce(trim(p_titulo),'')='' then return json_build_object('erro','informe um titulo'); end if;
  if p_url is not null and p_url !~* '^https?://' then return json_build_object('erro','o link precisa comecar com http'); end if;
  insert into obra_relatorios (obra_id, titulo, url, origem, data_referencia, criado_por)
  values (p_obra, trim(p_titulo), nullif(trim(p_url),''), coalesce(p_origem,'auvo'), p_data, auth.email())
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
end $function$
