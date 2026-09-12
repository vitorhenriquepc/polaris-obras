-- Funções internas não devem ser chamáveis via API REST
revoke execute on function public.check_signup_autorizado() from anon, authenticated, public;
revoke execute on function public.rls_auto_enable() from anon, authenticated, public;
-- is_admin/is_autorizado só fazem sentido logado
revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_autorizado() from anon;
-- email_autorizado permanece pública de propósito (checagem pré-cadastro na tela de login)
-- get_obra_publica permanece pública de propósito (tracker do cliente)
