-- DEFEITO MEU, corrigido no mesmo dia.
--
-- As funcoes de cadastro que escrevi hoje criavam a usina em `usinas` e
-- paravam ai. Faltava a linha em `obra_usina` -- a tabela de ligacao que eu
-- nao sabia que existia quando escrevi.
--
-- POR QUE IMPORTA
-- `usinas.cliente_id` NAO e o caminho que o sistema usa. Vinte e quatro
-- funcoes leem `obra_usina`, entre elas obra_geracao_total, get_geracao,
-- get_posvenda_lista, usina_estado, pendencias_posvenda e linha_do_tempo.
-- Usina sem essa linha nasce meio conectada: aparece no cartao do cliente
-- (que eu fiz ler por cliente_id) e some de todo o resto.
--
-- COMO APARECEU
-- 57 linhas em obra_usina para 59 usinas. As duas que faltavam eram as da
-- Tays, criadas por mim horas antes.
--
-- A TABELA, QUE VALE CONHECER
--   papel    'propria' | 'expansao' | 'herdada'
--   medicao  'inversor_proprio' | 'compartilhado' (com kwp_parte)
--   principal  uma so por obra, garantido por indice unico parcial
--   entrou_em / saiu_em  vigencia
--
-- `papel = 'herdada'` JA EXISTIA e ja estava em uso: as duas usinas antigas
-- da ATA ACADEMIA estao marcadas assim desde sempre. O campo que o Vitor
-- pediu ("marcar que a usina e herdada") nao precisava ser criado -- precisa
-- ser MOSTRADO, que e outra coisa. Mesmo caso do planoBox.

-- 1. conserta as duas da Tays
insert into obra_usina (obra_id, usina_id, papel, medicao, principal, entrou_em)
select o.id, u.id, 'herdada', 'inversor_proprio',
       (u.apelido like 'Açougue%'), u.data_instalacao
from obras o join usinas u on u.cliente_id = o.cliente_id
where o.slug = 'tays-valese-prado'
on conflict (obra_id, usina_id) do nothing;

-- 2. as duas funcoes passam a criar o vinculo.
--    O corpo corrigido esta nos arquivos originais:
--      2026-09-15_cadastro_de_cliente_de_plano.sql
--      2026-09-15_adicionar_usina_a_cliente.sql
--    Aplicado em producao por edicao cirurgica com pg_get_functiondef +
--    replace, conferindo que a ancora aparecia exatamente uma vez.

-- 3. confere que nao sobrou nenhuma solta
do $$
declare n int;
begin
  select count(*) into n from usinas u
    left join obra_usina ou on ou.usina_id = u.id where ou.id is null;
  if n > 0 then
    raise exception 'ainda ha % usina(s) sem vinculo com obra', n;
  end if;
end $$;
