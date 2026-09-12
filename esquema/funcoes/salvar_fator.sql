CREATE OR REPLACE FUNCTION public.salvar_fator(p_usina uuid, p_fator numeric, p_nota text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if p_fator is not null and (p_fator <= 0 or p_fator > 2) then
    return json_build_object('erro','o fator deve ficar entre 0 e 2');
  end if;
  update usinas set fator_local = p_fator,
                    fator_origem = case when p_fator is null then null else 'ajustado à mão' end,
                    fator_em = now(),
                    nota_geracao = coalesce(p_nota, nota_geracao)
   where id = p_usina;
  return json_build_object('ok', true);
end $function$
