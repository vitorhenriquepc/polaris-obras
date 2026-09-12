-- Cadastro de EQUIPE: funcionários que entram nos grupos dos clientes.
-- Editável pelo painel (adicionar/desativar quando alguém entra ou sai).
create table if not exists equipe (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  papel     text not null check (papel in ('Vendedor','Diretor','Pós-venda','Engenharia','Outro')),
  telefone  text not null,
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);

-- Seed inicial (só se a tabela estiver vazia — idempotente)
insert into equipe (nome, papel, telefone)
select v.nome, v.papel, v.telefone from (values
  ('Jefferson Yamada','Vendedor','55DDD00000000'),
  ('Vitor Carvalho','Diretor','55DDD00000000'),
  ('Luisa Cardoso','Pós-venda','55DDD00000000'),
  ('Ana Claudia','Vendedor','55DDD00000000'),
  ('Livia de Paula','Engenharia','55DDD00000000')
) as v(nome,papel,telefone)
where not exists (select 1 from equipe);

-- Vincular um vendedor a cada obra (pra entrar no grupo + análise de vendas)
alter table obras add column if not exists vendedor_id uuid references equipe(id);

-- Guardar o ID do grupo criado por obra (já existe whatsapp_grupo_id; ok)

-- RLS: só a equipe logada acessa o cadastro
alter table equipe enable row level security;
drop policy if exists equipe_auth on equipe;
create policy equipe_auth on equipe for all to authenticated using (true) with check (true);

select nome, papel, telefone from equipe order by papel, nome;
