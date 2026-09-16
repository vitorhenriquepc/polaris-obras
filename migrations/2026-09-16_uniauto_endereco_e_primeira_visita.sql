-- 2026-09-16 — UNI AUTO POSTO: um endereço, uma visita
--
-- CONTEXTO
-- Com o contrato do UNI AUTO fechado (completo_especial, cortesia, 6 meses,
-- 16/09/2026 a 16/03/2027) e a plano_contrato_criar ja gerando visitas, faltava
-- resolver o caso dele: as duas usinas tinham o endereco escrito de dois
-- jeitos, e a geracao sairia com DUAS visitas para o mesmo 16/12/2026.
--
--   USINA 1 · 105,40 kWp · instalada 2022 · endereco 'AREA RURAL CLEMENTINA'
--   USINA 2 · 129,60 kWp · instalada 2024 · endereco 'CLEMENTINA'
--
-- A conta de visitas e a de plano_endereco_adicional sao as duas
-- count(distinct endereco): texto divergente cobra R$ 200/ano a mais e manda a
-- equipe a Clementina duas vezes.
--
-- DECISAO DO VITOR (16/09): e o mesmo lugar. Uma visita.
--
-- SIMULADO ANTES (regra 3.2), em begin/rollback: criadas = 1,
-- prevista_para = 2026-12-16, enderecos distintos = 1.
--
-- GRAVADO, e conferido depois num comando separado:
--   as duas usinas com endereco = 'AREA RURAL CLEMENTINA';
--   1 linha em plano_visita, status 'prevista', 16/12/2026, ancorada na USINA 2
--   (129,60 kWp) -- a de maior potencia do endereco, que e o criterio da
--   propria plano_visitas_gerar.
--
-- Esta e a PRIMEIRA visita do sistema: plano_visita estava vazia.

update usinas set endereco = 'AREA RURAL CLEMENTINA'
 where id in ('e9340eca-ff04-4134-9fa5-132e9346e094',   -- USINA 1, 105,40 kWp
              '91c8fb35-f53b-47f0-94e9-5328de2594c2');  -- USINA 2, 129,60 kWp

select plano_visitas_gerar('9bc97b8b-d740-4918-9899-d831b2c68a63');
