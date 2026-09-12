-- Views passam a respeitar o RLS de quem consulta (corrige o lint nível ERRO).
-- Como anon não tem acesso a 'obras', estas views ficam restritas à equipe logada.
alter view public.vw_duracao_etapa set (security_invoker = on);
alter view public.vw_obras_paradas set (security_invoker = on);

-- Fixa o search_path das funções (boa prática de segurança).
alter function public.fn_touch_updated() set search_path = public;
alter function public.fn_log_etapa() set search_path = public;

-- Funções de trigger não devem ser chamáveis via API (o trigger continua funcionando).
revoke execute on function public.fn_touch_updated() from anon, authenticated, public;
revoke execute on function public.fn_log_etapa()   from anon, authenticated, public;
