CREATE OR REPLACE FUNCTION public.auto_lida()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.lida_em is null and new.da_equipe is not true
     and mensagem_sem_acao(coalesce(new.transcricao, new.texto), new.tipo, new.contexto) then
    new.lida_em := now();
    new.respondida_por := coalesce(new.respondida_por, 'automático');
  end if;
  return new;
end $function$
