-- Entrega do Material: prazo de 1 a 15 para 1 a 20 dias úteis (Vitor, 14/10).
--
-- O prazo de cada etapa mora só em etapas.prazo_texto. Quem lê de lá:
--   - painel.html, buildWA(): a mensagem do grupo quando a obra entra na etapa
--     ("⏱️ Prazo: ...") — a tela carrega as etapas ao abrir, então aba aberta
--     antes da mudança segue com o texto antigo até recarregar (armadilha 31);
--   - cliente.html, pela get_acompanhamento(): o prazo da etapa atual na página
--     do cliente;
--   - get_obra_publica() e o foto-obra (este só usa o prazo da etapa seguinte à
--     instalação, a 7).
-- Nenhum número de dias da etapa 5 está chumbado em código, função ou config
-- (procurado em 14/10). O eletroposto tem o próprio prazo de equipamentos
-- (etapa 3, "Pedido dos Equipamentos", 5 a 15 dias úteis) e não mudou.

do $x$
declare n int;
begin
  update etapas
     set prazo_texto = 'Prazo: 1 a 20 dias úteis'
   where trilha = 'padrao' and numero = 5 and nome = 'Entrega do Material';
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'esperava 1 etapa, achou %', n;
  end if;
end $x$;
