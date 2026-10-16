-- RINALDO DE CASTRO (4519): data_instalacao gravada por engano como 0001-01-01
-- em 13/10 10:25 (Vitor: "coloquei errado, pode deixar ela com 0").
-- Volta a ficar sem data. O trg_sync_dre_obra apaga a receita de R$ 42.000 que
-- tinha ido para o ano 1 no DRE; ela volta quando a data real for preenchida.
-- Nenhuma mensagem sai por aqui (é o banco, não o card).
do $x$ begin
  update obras set data_instalacao = null where contrato = '4519' and data_instalacao = '0001-01-01';
end $x$;
