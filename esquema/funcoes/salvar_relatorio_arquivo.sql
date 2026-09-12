CREATE OR REPLACE FUNCTION public.salvar_relatorio_arquivo(p_obra uuid, p_titulo text, p_path text, p_url text, p_tamanho bigint DEFAULT NULL::bigint, p_data date DEFAULT NULL::date)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if coalesce(trim(p_titulo),'')='' then return json_build_object('erro','informe um nome'); end if;
  if coalesce(trim(p_path),'')='' then return json_build_object('erro','arquivo nao enviado'); end if;
  insert into obra_relatorios (obra_id, titulo, url, arquivo_path, tamanho_bytes,
                               origem, data_referencia, criado_por)
  values (p_obra, trim(p_titulo), p_url, p_path, p_tamanho, 'arquivo', p_data,
          coalesce(auth.email(),'equipe'))
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
end $function$
