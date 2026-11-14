CREATE OR REPLACE FUNCTION public.salvar_causa(p_usina uuid, p_causa text, p_nota text DEFAULT NULL::text, p_avisado boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old record;
  v_cv record;
  v_nova text := nullif(btrim(coalesce(p_causa, '')), '');
  v_mesma boolean;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  select * into v_old from usinas where id = p_usina for update;
  if not found then return json_build_object('erro','usina não encontrada'); end if;
  select * into v_cv from usina_causa_vigente(p_usina);

  -- a mesma causa, na mesma queda: só ajusta a nota e o "avisado", mantém a data
  v_mesma := v_old.causa is not null and v_old.causa = v_nova and coalesce(v_cv.vigente, false);

  -- a anotação que sai de cena (trocada, apagada, ou de uma queda que já acabou)
  -- vai para o histórico antes de mexer (regra 3.6)
  if v_old.causa is not null and not v_mesma then
    insert into usina_causa_hist (usina_id, causa, nota, anotada_em, anotada_por, avisado_em,
                                  resolvida_em, resolvida_como, trocada_em, trocada_por)
    values (p_usina, v_old.causa, v_old.causa_nota, v_old.causa_em, v_old.causa_por,
            v_old.cliente_avisado_em, v_cv.resolvida_em, v_cv.resolvida_como,
            now(), coalesce(auth.email(), 'equipe'));
  end if;

  update usinas
     set causa = v_nova,
         causa_nota = p_nota,
         causa_em = case when v_nova is null then null
                         when v_mesma then v_old.causa_em
                         else now() end,
         causa_por = case when v_mesma then v_old.causa_por
                          else coalesce(auth.email(),'equipe') end,
         -- o aviso de uma queda que já acabou não vale para esta
         cliente_avisado_em = case
           when p_avisado is true then
             case when coalesce(v_cv.avisado_vigente, false) then coalesce(v_old.cliente_avisado_em, now()) else now() end
           when p_avisado is false then null
           else case when coalesce(v_cv.avisado_vigente, false) then v_old.cliente_avisado_em end
         end
   where id = p_usina;
  return json_build_object('ok', true, 'anterior_guardada', v_old.causa is not null and not v_mesma);
end $function$
