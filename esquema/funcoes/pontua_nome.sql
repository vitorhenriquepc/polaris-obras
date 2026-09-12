CREATE OR REPLACE FUNCTION public.pontua_nome(a text, b text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  with pa as (select unnest(string_to_array(regexp_replace(lower(translate(coalesce(a,''),
        'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc')),'[^a-z0-9 ]',' ','g'),' ')) w),
       pb as (select unnest(string_to_array(regexp_replace(lower(translate(coalesce(b,''),
        'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc')),'[^a-z0-9 ]',' ','g'),' ')) w),
       fa as (select distinct w from pa where length(w)>2),
       fb as (select distinct w from pb where length(w)>2)
  select case when (select count(*) from fa)=0 or (select count(*) from fb)=0 then 0
    else (select count(*)::numeric from fa join fb using (w))
         / least((select count(*) from fa),(select count(*) from fb)) end;
$function$
