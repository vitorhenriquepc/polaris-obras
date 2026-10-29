-- 29/10: a agenda mostra a obra em todos os dias, da instalação ao término
--
-- ROSANE ALVES DA SILVA SABINO (4716): o Vitor marcou a instalação para 04/11 e
-- o término previsto para 05/11, e a agenda (instalador.html?agenda=...) mostrou
-- só o dia 04. O término estava gravado (obras.data_fim, o "Término previsto" do
-- card), mas a get_agenda não o devolvia, e a página só comparava o dia com a
-- data de instalação. Em 29/10, 29 obras têm término e 5 passam de um dia; 4
-- delas estão na janela da agenda (4301, 4686, 4519 e 4716).
--
-- Aqui: a get_agenda devolve o data_fim, e a janela de 30 dias para trás conta
-- pelo fim da obra. Quem desenha cada dia é o instalador.html. Campo a mais no
-- json não quebra a página antiga — ela só não o lê. O create or replace mantém
-- o EXECUTE do anon: a agenda é página sem login (armadilha 26).
--
-- Simulado antes de gravar, numa transação que terminou em erro: os dois trechos
-- aparecem uma vez cada, a agenda geral continua com as mesmas 19 obras e a
-- ROSANE passa a vir com data_fim 2026-11-05.

create function pg_temp.troca(p_fn regprocedure, p_velho text, p_novo text, p_vezes int default 1)
returns void language plpgsql as $t$
declare d text := pg_get_functiondef(p_fn); n int;
begin
  n := (length(d) - length(replace(d, p_velho, ''))) / length(p_velho);
  if n <> p_vezes then
    raise exception '%: esperava % vez(es) o trecho [%], achei %', p_fn, p_vezes, p_velho, n;
  end if;
  execute replace(d, p_velho, p_novo);
end $t$;

select pg_temp.troca('public.get_agenda(text)',
  $o$'data_instalacao', o.data_instalacao,$o$,
  $n$'data_instalacao', o.data_instalacao, 'data_fim', o.data_fim,$n$);

select pg_temp.troca('public.get_agenda(text)',
  $o$and o.data_instalacao >= current_date - interval '30 days'$o$,
  $n$and greatest(o.data_instalacao, o.data_fim) >= current_date - interval '30 days'$n$);
