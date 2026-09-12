-- SEGURANÇA: lista de e-mails autorizados a acessar o painel.
-- Mesmo que alguém crie conta com a chave anon, sem estar nesta lista NÃO acessa nada.
create table if not exists usuarios_autorizados (
  email     text primary key,
  nome      text,
  criado_em timestamptz not null default now()
);

insert into usuarios_autorizados (email, nome) values
  ('pessoa@exemplo.com','Luisa Cardoso')
on conflict (email) do nothing;

-- Função que diz se o usuário logado está autorizado
create or replace function is_autorizado() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from usuarios_autorizados
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  );
$$;

-- Trava todas as tabelas de dados pela lista de autorizados
drop policy if exists obras_auth on obras;
create policy obras_auth on obras for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

drop policy if exists hist_auth on etapas_historico;
create policy hist_auth on etapas_historico for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

drop policy if exists fotos_auth on fotos;
create policy fotos_auth on fotos for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

drop policy if exists equipe_auth on equipe;
create policy equipe_auth on equipe for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

drop policy if exists etapas_write on etapas;
create policy etapas_write on etapas for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

-- A própria lista só é gerenciada por quem já está autorizado
alter table usuarios_autorizados enable row level security;
drop policy if exists ua_auth on usuarios_autorizados;
create policy ua_auth on usuarios_autorizados for all to authenticated
  using (is_autorizado()) with check (is_autorizado());

select email, nome from usuarios_autorizados;
