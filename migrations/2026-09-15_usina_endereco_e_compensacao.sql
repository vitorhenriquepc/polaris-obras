-- Dois campos que o plano Completo vende e a usina nao sabia guardar.
--
-- 1. ENDERECO
-- O Completo inclui "uma visita tecnica anual em CADA ENDERECO". A tabela
-- `usinas` so tinha `cidade` -- nao havia onde escrever para onde o tecnico
-- vai. Com duas usinas em cidades diferentes (Aracatuba e Birigui, no caso
-- da Tays) isso deixa de ser detalhe.
--
-- 2. COMPENSACAO CRUZADA
-- O rancho da Tays manda os creditos todos para o acougue. Se a economia for
-- calculada por usina isolada os dois numeros saem errados: o rancho gera
-- 40,95 kWp e nao abate nada no proprio relogio, e o acougue abate muito
-- mais do que a propria usina explica.
--
-- Isso e exatamente o tipo de numero que chega ao cliente pela regua, e a
-- regra 3.1 do CLAUDE.md nao admite chute. O campo registra o arranjo em vez
-- de deixa-lo na memoria de quem lembra.

alter table usinas add column if not exists endereco text;
alter table usinas add column if not exists compensa_em uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'usinas_compensa_em_fkey') then
    alter table usinas add constraint usinas_compensa_em_fkey
      foreign key (compensa_em) references usinas(id) on delete set null;
  end if;
end $$;

-- uma usina nao pode compensar nela mesma
alter table usinas drop constraint if exists usinas_compensa_em_ok;
alter table usinas add constraint usinas_compensa_em_ok
  check (compensa_em is null or compensa_em <> id);

comment on column usinas.endereco is
  'Endereco da usina. O plano Completo vende uma visita anual por endereco.';
comment on column usinas.compensa_em is
  'Usina que recebe os creditos desta. Nulo = compensa no proprio relogio.';
