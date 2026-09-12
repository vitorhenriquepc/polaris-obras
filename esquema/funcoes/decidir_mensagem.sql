CREATE OR REPLACE FUNCTION public.decidir_mensagem(p_id uuid, p_acao text, p_texto text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sit text;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  select situacao into v_sit from mensagem_aprovacao where id=p_id;
  if v_sit is null then return json_build_object('erro','mensagem nao encontrada'); end if;
  if v_sit <> 'aguardando' then
    return json_build_object('erro','esta mensagem ja foi '||v_sit);
  end if;

  if p_acao = 'aprovar' then
    update mensagem_aprovacao
       set texto = coalesce(nullif(trim(p_texto),''), texto),
           situacao='aprovada', decidida_em=now(), decidida_por=coalesce(auth.email(),'equipe')
     where id=p_id;
  elsif p_acao = 'recusar' then
    update mensagem_aprovacao
       set situacao='recusada', decidida_em=now(), decidida_por=coalesce(auth.email(),'equipe')
     where id=p_id;
  elsif p_acao = 'editar' then
    if coalesce(trim(p_texto),'')='' then return json_build_object('erro','texto vazio'); end if;
    update mensagem_aprovacao set texto=trim(p_texto) where id=p_id;
  else
    return json_build_object('erro','acao invalida');
  end if;
  return json_build_object('ok', true);
end $function$
