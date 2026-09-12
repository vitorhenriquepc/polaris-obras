-- Números que SEMPRE entram nos grupos de clientes (além de cliente + vendedor)
insert into public.config (chave, valor) values
  ('grupo_fixos', '55DDD00000000,55DDD00000000')
on conflict (chave) do update set valor = excluded.valor;
