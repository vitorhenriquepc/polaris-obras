-- =====================================================================
-- 2026-09-23 — O link de acompanhamento do cliente voltou a abrir
--
-- JÁ APLICADO no projeto dakubhcgohiwzyqiegqf, em duas migrações:
-- 'link_do_cliente_volta_a_abrir' e 'conferencia_vigia_paginas_publicas'.
-- =====================================================================

-- O relato: o Vitor abriu no celular o link que a TANAKA (4745) recebeu na
-- mensagem de "Entrega do Material" e a página não carregou.
--
-- A causa: `cliente.html` é pública (o cliente não tem login) e só chama
-- `get_acompanhamento(slug)`. O anon — o papel de quem não fez login — não
-- tinha EXECUTE nela. Toda abertura voltava **401**, e a página dizia
-- "🔒 Obra não encontrada", que é a mesma frase de link errado.
--
-- Desde quando, pelos logs do gateway (papel de quem chamou + status):
--   25/08  14 aberturas anônimas, todas 200
--   01/09  anônimo 401 ×6
--   13/09, 19/09, 23/09  anônimo 401 em todas
-- Nenhuma migração registrada revoga essa função pelo nome — o revoke foi
-- feito fora do histórico, entre 26/08 e 01/09. Não dá para dizer por quem.
--
-- ⚠️ Por que ninguém percebeu em quatro semanas: os únicos 200 desse período
-- vêm de `role = authenticated`, do computador do escritório em Araçatuba.
-- Quem testava o link logado via funcionando; o cliente, não. E a varredura
-- de 12/09 (2026-09-12_revoga_anon_funcoes_expostas.sql) listou as funções
-- que o anon **alcança** — a que ele deveria alcançar e não alcançava não
-- aparece numa lista dessas.
--
-- O que ela devolve é o mesmo tipo de dado que `get_relatorio_publico` já
-- serve pelo mesmo slug: nome, contrato, potência, etapa, datas, equipamento
-- e até 6 fotos. É pública de propósito.

grant execute on function public.get_acompanhamento(text) to anon;

-- Conferido depois, em comando separado (armadilha 2):
--   proacl = {postgres=X,authenticated=X,service_role=X,anon=X}
--   curl anônimo no /rest/v1/rpc/get_acompanhamento → 200 com a TANAKA
--   slug inexistente → 200 com null (a página diz "não encontrada")
--   como anon, os 76 slugs de `obras` devolvem obra: 76 de 76
--   Chromium com perfil de iPhone, sem login, na página publicada: abre


-- ---------------------------------------------------------------------
-- A rede: a conferência das 7h30 passa a acusar página pública sem acesso
-- ---------------------------------------------------------------------
-- `conferir_saude_base()` ganha o achado
-- 'pagina publica sem acesso (link do cliente ou instalador quebrado)':
-- conta, das funções que as páginas sem login chamam, quantas o anon NÃO
-- consegue executar. Função apagada ou com assinatura trocada também conta
-- (`to_regprocedure` devolve nulo e o `coalesce` vira false).
--
--   cliente.html     get_acompanhamento
--   relatorio.html   get_relatorio_publico
--   nps.html         get_nps, salvar_nps, salvar_brinde, declarar_avaliacao_google
--   instalador.html  get_obra_instalador, get_agenda
--
-- As outras RPCs do relatorio.html (get_avaliacoes, avaliar_item,
-- get_secoes_relatorio) são sem anon **de propósito**: só rodam depois de
-- `auth.getSession()`, para a equipe.

do $do$
declare d text; velho text; novo text;
begin
  d := pg_get_functiondef('public.conferir_saude_base()'::regprocedure);
  velho := $v$  from (
    select 'usina sem monitoramento' as achado, count(*) as qtd$v$;
  novo := $n$  from (
    -- 23/09: as páginas que o cliente e o instalador abrem sem login dependem
    -- destas funções. Sem EXECUTE para o anon o link devolve 401 — e quem testa
    -- logado no escritório vê funcionando. Ficou assim de ~26/08 a 23/09.
    select 'pagina publica sem acesso (link do cliente ou instalador quebrado)' as achado, count(*) as qtd
      from unnest(array['get_acompanhamento(text)','get_relatorio_publico(text)',
        'get_nps(text,text)','salvar_nps(text,text,smallint,text)','salvar_brinde(text,text,text)',
        'declarar_avaliacao_google(text,text)','get_obra_instalador(text,text)','get_agenda(text)']) f
      where not coalesce(has_function_privilege('anon', to_regprocedure('public.'||f), 'execute'), false)
    union all
    select 'usina sem monitoramento', count(*)$n$;
  if position(velho in d) = 0 then raise exception 'trecho de ancoragem nao encontrado'; end if;
  execute replace(d, velho, novo);
end $do$;

-- Conferido:
--   hoje o achado não aparece (as 8 funções estão abertas ao anon)
--   num begin/rollback, tirando o anon da get_acompanhamento, ele aparece
--   com qtd 1 — e depois do rollback o anon continua com EXECUTE
