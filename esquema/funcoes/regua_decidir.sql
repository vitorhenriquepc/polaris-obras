CREATE OR REPLACE FUNCTION public.regua_decidir(p_id bigint, p_acao text, p_texto text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  select c.*, m.precisa_aprovacao into v
  from regua_contatos c join regua_modelos m on m.codigo=c.modelo where c.id=p_id;
  if v is null then return json_build_object('erro','item nao encontrado'); end if;
  if v.status <> 'pendente' then return json_build_object('erro','este item ja foi '||v.status); end if;

  if p_acao='aprovar' then
    update regua_contatos
       set texto_custom = coalesce(nullif(trim(p_texto),''), texto_custom),
           status_aprovacao='aprovada', aprovada_em=now(), aprovada_por=coalesce(auth.email(),'equipe')
     where id=p_id;
  elsif p_acao='recusar' then
    update regua_contatos
       set status='pulado', bloqueio_motivo='recusada na revisão',
           status_aprovacao='recusada', aprovada_em=now(), aprovada_por=coalesce(auth.email(),'equipe')
     where id=p_id;
  elsif p_acao='editar' then
    if coalesce(trim(p_texto),'')='' then return json_build_object('erro','texto vazio'); end if;
    update regua_contatos set texto_custom=trim(p_texto) where id=p_id;
  else
    return json_build_object('erro','acao invalida');
  end if;
  return json_build_object('ok',true);
end $function$
