-- A Ana lancava duas vezes. Agora a ficha le o extrato.
--
-- O QUE ESTAVA ACONTECENDO
-- -----------------------
-- Ela classifica o movimento no extrato (e isso JA vincula a obra: dos 60
-- custos de obra, 55 estao ligados; dos 18 recebimentos, 18). Depois abria a
-- ficha da obra e digitava o mesmo valor de novo, porque nada trazia o numero
-- de volta -- NENHUMA funcao do banco lia `extrato_rateio` por obra.
--
-- As contas do DRE batem quase 1:1 com os campos da ficha, o que fecha o
-- circulo: 03.1.01 -> valor_kit, 03.2.01 -> instalacao, 03.2.03 -> art...
--
-- Medido, nao deduzido:
--     6 campos digitados DUAS VEZES (valor bate ao centavo)
--    39 campos so no extrato (a ficha estava zerada -- ela nem sempre
--       conseguia fazer a segunda digitacao, e a margem saia errada)
--     5 campos DIVERGENTES entre as duas fontes
--
-- POR QUE NAO CORRIGI EM LOTE
-- ---------------------------
-- O Vitor autorizou "corrige a ficha pelo extrato". Nao fiz, e o motivo e
-- concreto: **o extrato so cobre 03/08/2026 a 08/09/2026**. De 27 obras com
-- custo lancado, **14 fecharam ANTES de 03/08** -- o custo delas foi pago fora
-- da janela e o extrato nao tem.
--
-- O caso que prova: Jose Antonio (4674), estrutura de carport. A ficha diz
-- R$ 9.386,01 e o extrato R$ 268,65. A obra fechou em 28/07. Sobrescrever
-- apagaria R$ 9.117,36 de custo real e inflaria a margem dessa obra.
--
-- Entao a ficha continua digitavel, o extrato entra como sugestao de um
-- clique, e quem decide e a pessoa -- que e quem sabe o que foi pago em julho.
-- Isso se resolve sozinho quando o extrato anterior a agosto for importado
-- (ja e pendencia no CLAUDE.md).

-- 1. O mapa conta -> campo mora no plano de contas, nao no codigo da tela.
--    Conta nova ganha o campo dela sem mexer em tela nenhuma.
alter table dre_plano_contas add column if not exists campo_ficha text;

comment on column dre_plano_contas.campo_ficha is
  'Campo de obra_financeiro que esta conta alimenta. Null = conta sem espelho na ficha (entra em "outros").';

update dre_plano_contas set campo_ficha = m.campo
from (values
  ('03.1.01','valor_kit'), ('03.1.02','material_ca'), ('03.1.03','material_eletrico'),
  ('03.1.04','cabo'),      ('03.1.05','estrutura_carport'), ('03.1.06','carregador'),
  ('03.1.07','pecas'),     ('03.2.01','instalacao'), ('03.2.02','deslocamento'),
  ('03.2.03','art'),       ('03.2.04','seguro'),     ('03.2.05','frete'),
  ('03.2.07','custo_operacional'), ('03.2.08','provisao_posvenda'),
  ('03.2.09','obra_civil'), ('04.1.01','comissao_valor')
) as m(cod, campo)
where dre_plano_contas.codigo = m.cod;

-- 03.2.06 (Manutencao e Retrabalho) e 03.2.10 (Servicos Avulsos) ficam de fora
-- de proposito: nao tem campo equivalente na ficha e entram como "outros".

-- 2. O realizado de uma obra, campo a campo, direto do extrato.
--    `cobre_periodo` e false quando a obra fechou antes do primeiro movimento
--    importado -- e a tela usa isso para dizer "parcial" em vez de fingir que
--    o numero esta completo.
create or replace function public.obra_custos_realizados(p_obra uuid)
returns json language sql stable security definer set search_path to 'public' as $function$
  with linhas as (
    select r.conta_codigo, c.nome as conta_nome, c.campo_ficha, sum(r.valor) as valor
      from extrato_rateio r
      join extrato_movimentos m on m.id = r.movimento_id
      left join dre_plano_contas c on c.codigo = r.conta_codigo
     where r.obra_id = p_obra
       and m.classificacao = 'custo_obra'
     group by r.conta_codigo, c.nome, c.campo_ficha
  ),
  janela as (select min(data_mov) as desde, max(data_mov) as ate from extrato_movimentos)
  select json_build_object(
    'por_campo', coalesce((select json_object_agg(campo_ficha, valor)
                             from linhas where campo_ficha is not null), '{}'::json),
    'linhas', coalesce((select json_agg(json_build_object(
                            'conta', conta_codigo, 'nome', conta_nome,
                            'campo', campo_ficha, 'valor', valor) order by conta_codigo)
                          from linhas), '[]'::json),
    'outros', coalesce((select sum(valor) from linhas where campo_ficha is null), 0),
    'total',  coalesce((select sum(valor) from linhas), 0),
    'extrato_desde', (select desde from janela),
    'extrato_ate',   (select ate   from janela),
    'cobre_periodo', coalesce(
       (select o.data_fechamento >= (select desde from janela)
          from obras o where o.id = p_obra), true)
  );
$function$;

-- Armadilha 10: dois revokes. Conferido pela ACL depois, nao pelo comando ter
-- passado: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke execute on function public.obra_custos_realizados(uuid) from public;
revoke execute on function public.obra_custos_realizados(uuid) from anon;
grant  execute on function public.obra_custos_realizados(uuid) to authenticated;

-- 3. Na tela (financeiro.html), a ficha passou a mostrar embaixo de cada campo
--    de custo o que o extrato tem, com um botao "usar" -- um clique em vez de
--    digitar. Mais um "Puxar do extrato" que preenche tudo de uma vez, mas so
--    mexe sozinho no que esta VAZIO: campo ja preenchido e divergente pergunta
--    antes, e em obra fora da janela o aviso aparece dentro da pergunta.
--
--    Campo com dinheiro no extrato que a trilha daquela obra nao mostra
--    aparece no cabecalho ("R$ 268,65 em Estrutura de Carport — sem campo nesta
--    ficha, mas conta no total"), para o valor nao sumir da vista.
