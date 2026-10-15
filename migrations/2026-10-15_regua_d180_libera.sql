-- d180_manutencao volta a sair sozinho às 17h (Vitor, 15/10: "pode liberar a de
-- 6 meses para sair sozinha"), agora com o texto novo (2026-10-15_regua_d180_texto_novo.sql):
-- sem marca e com o plano/preço vindos do banco pelo {plano_frase}.
-- Conferido na hora: a regua_fila de 15/10 traz o contato 263 com o texto novo
-- (preço da faixa, sem "Sungrow" nem "289").
do $x$ begin
  update regua_modelos set precisa_aprovacao = false
   where codigo = 'd180_manutencao' and precisa_aprovacao;
end $x$;
