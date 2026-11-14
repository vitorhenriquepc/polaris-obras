-- 14/11, a pedido do Vitor ("pode juntar os cartões da 4956"). Já aplicado;
-- este arquivo é o registro. Rodar de novo não muda nada: a conferência do
-- começo recusa, porque os cartões já não estão como estavam.
--
-- A obra #4956 (ANTONIO CARLOS BREGALANTE) estava em dois cartões com o mesmo
-- contrato, o mesmo valor e o mesmo grupo de WhatsApp:
--   * e16c4b80… (criado em 14/10, slug antonio-carlos-bregalante): as 22
--     mensagens do grupo, as 2 esperas da Isabela, o histórico de etapas e o
--     endereço certo. Foi para a Execução em 12/11, e a mensagem da etapa saiu
--     com o link deste slug;
--   * 66d90bda… (criado em 10/11, slug antonio-carlos-bregalante-2): a data de
--     instalação 16/11, a CJP Solar, o link do checklist que a CJP recebeu em
--     10/11 e a venda no DRE. O endereço dizia "Zacarias, area rural"; o cliente
--     corrigiu no grupo no mesmo dia: "Castilho, Área Rural".
--
-- Fica o de 14/10: o link que o cliente recebeu por último é dele, e as
-- mensagens não precisam mudar de cartão. O link do instalador exige o slug e o
-- token juntos (get_obra_instalador), então o link de 10/11 não tinha como
-- continuar valendo. O duplicado ganha um token novo para ninguém mandar foto
-- para ele, e a CJP recebe o link novo pelo 📣 do card.
--
-- O DRE segue o gatilho de sempre (trg_dre_from_obra → sincroniza_dre_obra): o
-- duplicado perde a data e o lançamento da venda; o que fica ganha a data e o
-- lançamento. Simulado antes (DO terminando em raise): uma venda só, R$ 23.551,45
-- em 16/11, e o link novo abre o cartão que fica.
--
-- Ficaram com os valores do cartão de 14/10 até o Vitor confirmar: inversor
-- (3,5 kW × 6 kW), telhado (metálico × cerâmico) e fechamento (13/10 × 14/10).
-- O duplicado fica marcado "DUPLICADO, apagar" para ser excluído no card (o MCP
-- não apaga: armadilha 34).

do $juntar$
declare
  a uuid := 'e16c4b80-c5e7-4a0c-9c5c-aa7273c6bf9f';  -- cartão de 14/10: fica
  b uuid := '66d90bda-6d3d-4c53-bcf6-5aeac4597ef0';  -- cartão de 10/11: duplicado
  vb record; va record;
begin
  select * into vb from obras where id = b for update;
  select * into va from obras where id = a for update;
  if vb.data_instalacao is distinct from date '2026-11-16' or vb.relatorio_enviado_em is not null or va.data_instalacao is not null then
    raise exception 'Os cartões mudaram desde o levantamento; nada feito.';
  end if;

  update obras set data_instalacao = null, instalador_id = null,
         instalador_token = substr(md5(random()::text || clock_timestamp()::text), 1, 16),
         cliente = 'DUPLICADO, apagar: ' || cliente
   where id = b;

  update obras set data_instalacao = vb.data_instalacao, instalador_id = vb.instalador_id,
         concessionaria = coalesce(concessionaria, vb.concessionaria),
         endereco = 'Castilho, Área Rural'
   where id = a;

  insert into obra_nota (obra_id, tipo, texto, aconteceu_em, criado_por) values (a, 'observacao',
    'Cartão duplicado (criado em 10/11, slug antonio-carlos-bregalante-2) juntado a este em 14/11, a pedido do Vitor. '
    || 'Vieram de lá a data de instalação 16/11 e a CJP Solar. Endereço: o duplicado dizia "Zacarias, area rural"; '
    || 'o cliente corrigiu no grupo em 10/11 ("Castilho, Área Rural"). Ficaram os valores deste cartão até o Vitor '
    || 'confirmar: inversor (aqui 1x GOODWE 3,5kW + 5KW BATERIA; no duplicado 1x GOODWE 6kW + 5kW de Bateria), '
    || 'telhado (aqui Metálico; no duplicado Cerâmico) e fechamento (aqui 13/10; no duplicado 14/10). '
    || 'O link do checklist que a CJP recebeu em 10/11 era do duplicado e deixou de valer.',
    date '2026-11-14', 'claude, a pedido do Vitor (14/11)');
end $juntar$;

-- Conferido depois, em outro comando: o cartão que fica com 16/11, CJP Solar,
-- CPFL, "Castilho, Área Rural" e 120 km; o duplicado sem data, sem equipe e com
-- outro token; um lançamento de venda só (16/11, R$ 23.551,45); nenhuma entrada
-- nova no histórico de etapas; uma anotação.
