-- Obra cancelada na lista de clientes do painel (complemento de
-- 2026-10-23_obra_cancelada.sql). A vista "Clientes" lê get_clientes_acervo, que
-- mostra o status de cada obra do cliente — e o status de uma obra cancelada
-- continua "Em andamento", porque fn_status_auto o tira da etapa. Aqui ele sai
-- como "Cancelada". Só leitura; nada muda no banco além do texto devolvido.

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

select pg_temp.troca('public.get_clientes_acervo()',
  $o$'status', o.status,$o$,
  $n$'status', case when o.cancelada_em is not null then 'Cancelada' else o.status end,$n$);
