-- d180_manutencao passa a exigir aprovação (14/10, achado da autoanálise).
--
-- O primeiro d180 da história saiu em 14/10 às 17:00 para a ELOANA (contato 31)
-- sem passar pela Lívia (precisa_aprovacao = false, condicao 'sempre'), com
-- duas afirmações erradas chumbadas no texto do modelo:
--   - "a Sungrow exclui expressamente da cobertura..." — o inversor dela é Huawei
--     (dos 59 que faltam, 48 não são Sungrow);
--   - "Plano de Monitoramento Polaris ... a partir de R$ 289/ano" — esse plano não
--     existe; R$ 289 é o 'Ativo', que não tem visita/revisão. O mais barato com
--     revisão é o Completo (R$ 690, e R$ 790 para os 20 módulos dela).
-- E os 59 pendentes já têm contrato ativo (cortesia): a oferta é de algo que eles
-- já têm. Regras 3.1 (número do banco) e 3.5 (aprovação humana).
--
-- O que muda: a regua_fila só solta modelo com precisa_aprovacao = true quando o
-- contato está 'aprovada'. Os 59 pendentes ficam parados — nada é apagado (3.6) —
-- e NÃO aparecem no card de aprovação (get_regua_aprovacoes só lista
-- status_aprovacao = 'aguardando'), porque o texto ainda está errado.
-- Para desfazer: update regua_modelos set precisa_aprovacao = false
--                 where codigo = 'd180_manutencao';
do $x$ begin
  update regua_modelos set precisa_aprovacao = true
   where codigo = 'd180_manutencao' and not coalesce(precisa_aprovacao, false);
end $x$;
