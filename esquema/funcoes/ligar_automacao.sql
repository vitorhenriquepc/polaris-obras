CREATE OR REPLACE FUNCTION public.ligar_automacao(p_chave text, p_ligar boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if not exists (select 1 from automacoes where chave=p_chave and visivel) then
    return json_build_object('erro','automacao desconhecida');
  end if;
  insert into config(chave, valor) values (p_chave, case when p_ligar then '1' else '0' end)
  on conflict (chave) do update set valor=excluded.valor;
  return json_build_object('ok', true, 'ligada', p_ligar);
end $function$
