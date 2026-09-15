-- A tabela do Completo passa de 45 para 125 modulos, e o endereco extra
-- vira preco em vez de negociacao.
--
-- DE ONDE SAEM OS NUMEROS (nenhum foi estimado -- regra 3.1)
--
-- A propria tabela tem uma regra, medida em 15/09/2026:
--
--   faixa         topo   anual    mensal   R$/modulo   anual / (mensal x 12)
--   completo12      12     690     64,90       --            88,6%
--   completo20      20     790     74,90     12,50           87,9%
--   completo30      30     990     94,90     20,00           86,9%
--   completo45      45   1.290    119,90     20,00           89,7%
--
-- As duas ultimas faixas sobem exatamente R$ 20,00 por modulo/ano, e o preco
-- e sempre o do TOPO da faixa. As faixas novas seguem as duas regras:
--
--   anual  = 1.290 + 20 x (topo - 45)
--   mensal = anual / 10,716   (a razao media anual/mensal da tabela)
--
-- CONFERENCIA CONTRA UM CONTRATO REAL
-- O Completo anual fechado com a Tays Valese (120 modulos, 2 enderecos) foi
-- R$ 2.990 / R$ 279 ao mes. Pela regra acima:
--   2.990 / (279 x 12) = 89,3%   -> dentro da faixa 87-90% da tabela
--   2.990 / 10,716     = 279,02  -> o mensal dela, a dois centavos
--   1.290 + 20 x (120-45) = 2.790 -> R$ 200 abaixo do que ela pagou
-- Os R$ 200 sao o segundo endereco: o Completo vende uma visita tecnica anual
-- em CADA endereco, e visita e o que custa mao de obra.
--
-- Pela faixa nova (101-125, preco do topo) o mesmo perfil seria cotado a
-- 2.890 + 200 = R$ 3.090, ou seja R$ 100 acima do que foi fechado com ela.
-- Isso e consequencia de cobrar pelo topo da faixa, que e como a tabela ja
-- funcionava antes de mim. O contrato dela guarda o valor proprio e nao muda.

insert into planos (codigo, nome, icone, nivel, mod_min, mod_max,
                    preco_anual, preco_mensal, cortesia_1ano, inclui_visita,
                    desconto_servicos, ordem, ativo)
values
  ('completo60',  'Completo — 46 a 60 módulos',   '🥇', 3,  46,  60, 1590.00, 149.90, false, true, 20.00,  7, true),
  ('completo80',  'Completo — 61 a 80 módulos',   '🥇', 3,  61,  80, 1990.00, 189.90, false, true, 20.00,  8, true),
  ('completo100', 'Completo — 81 a 100 módulos',  '🥇', 3,  81, 100, 2390.00, 224.90, false, true, 20.00,  9, true),
  ('completo125', 'Completo — 101 a 125 módulos', '🥇', 3, 101, 125, 2890.00, 269.90, false, true, 20.00, 10, true)
on conflict (codigo) do nothing;

-- A `completo_especial` deixa de ser "tudo acima de 45" e vira a rede de
-- seguranca acima de 125, sem preco de tabela. Assim nenhum sistema cai numa
-- faixa que nao e a dele, e nenhum cai fora de faixa nenhuma.
--
-- Continua com ativo = false ate o PR #11 entrar: ela e a unica sem preco, e
-- com o JS antigo do main um plano sem preco vira "R$ 0,00" na proposta.
update planos
   set mod_min = 126, mod_max = null, ordem = 11,
       nome = 'Completo — acima de 125 módulos'
 where codigo = 'completo_especial';

-- O adicional por endereco e parametro, nao numero no codigo (secao 7).
insert into config (chave, valor)
values ('plano_endereco_adicional', '200')
on conflict (chave) do nothing;
