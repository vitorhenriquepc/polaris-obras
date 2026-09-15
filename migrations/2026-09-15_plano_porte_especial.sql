-- Uma faixa de Completo para sistema acima de 45 modulos.
--
-- A tabela `planos` parava em completo45 (31 a 45 modulos, R$ 1.290/ano).
-- Quem passa disso nao casava com faixa nenhuma, e o efeito era silencioso
-- em dois lugares:
--
--   1. get_painel_planos mostrava "Sem porte definido" e somava ZERO ao
--      potencial da carteira. Hoje isso acontece com 2 clientes reais:
--      GILBERTO JOSE SIQUEROLI (75 modulos) e VALDECIR RICOBONI (50).
--   2. planoCompletoPara() no posvenda.html caia no ultimo item da lista,
--      entao a proposta enviada a esses dois anunciava o preco do
--      completo45 -- um numero que nao vale para o sistema deles.
--
-- A faixa nasce SEM preco de tabela de proposito. Nao existe preco definido
-- para esse porte, e a regra 3.1 do CLAUDE.md e clara: a IA nao inventa
-- numero. Enquanto preco_anual/preco_mensal forem nulos, a tela mostra
-- "sob consulta" e o valor real vive no contrato.
--
-- Quando o Vitor definir a tabela desse porte:
--   update planos set preco_anual = <x>, preco_mensal = <y>
--    where codigo = 'completo_especial';

insert into planos (codigo, nome, icone, nivel, mod_min, mod_max,
                    preco_anual, preco_mensal, cortesia_1ano, inclui_visita,
                    desconto_servicos, ordem, ativo)
values ('completo_especial', 'Completo — acima de 45 módulos', '🥇', 3,
        46, null, null, null, false, true, 20.00, 7, true)
on conflict (codigo) do nothing;
