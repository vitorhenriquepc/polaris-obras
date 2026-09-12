CREATE OR REPLACE FUNCTION public.mascara_credencial()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare t text;
begin
  t := coalesce(new.transcricao, new.texto);
  if t is null then return new; end if;

  -- texto curto, com e-mail e uma linha que parece senha logo depois
  if length(t) < 220
     and t ~* '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
     and t ~ E'@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\s*\\n\\s*\\S{6,}'
     and t !~* '(https?://|apps\.apple|play\.google)'
  then
    insert into mensagem_mascarada (id, obra_id, motivo, tamanho_original)
    values (new.id, new.obra_id, 'possível credencial detectada na entrada', length(t))
    on conflict (id) do nothing;
    new.texto := '[credencial removida por segurança — mensagem com login e senha]';
    new.transcricao := null;
  end if;
  return new;
end $function$
