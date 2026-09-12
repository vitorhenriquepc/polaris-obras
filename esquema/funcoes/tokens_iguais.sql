CREATE OR REPLACE FUNCTION public.tokens_iguais(a text, b text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  with pa as (select distinct unnest(string_to_array(regexp_replace(lower(translate(coalesce(a,''),
        'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc')),'[^a-z0-9 ]',' ','g'),' ')) w),
       pb as (select distinct unnest(string_to_array(regexp_replace(lower(translate(coalesce(b,''),
        'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc')),'[^a-z0-9 ]',' ','g'),' ')) w)
  select count(*)::int from pa join pb using (w) where length(w) > 2;
$function$
