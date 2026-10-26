-- "Em andamento" é não ter chegado na última etapa da PRÓPRIA trilha (26/10).
--
-- O Vitor recebeu no alerta de prazos das 8h:
--   "• Fatima Rino e Antonio Monteiro #3067 — 37 dias / ✅ Concluída"
-- e perguntou o que aconteceu, porque a limpeza já estava feita. É uma
-- manutenção preventiva: a trilha `manutencao` vai de 0 a 4, e a 4 é
-- "Concluída" — ela está lá desde 17/09. O alerta (obras_para_alerta) chamava
-- de "em andamento" toda obra com `etapa_numero < 8`, número que só vale para a
-- trilha padrão e o eletroposto. 4 < 8: a manutenção concluída entrava como
-- obra em andamento há 37 dias (desde 17/10, quando fez 30 dias do fechamento).
-- É a regra do §6 do CLAUDE.md que não tinha chegado aqui: quem diz se a obra
-- terminou é obra_ativa(), não um 8 escrito à mão.
--
-- O mesmo 8 inflava as métricas (metricas.html): as 5 manutenções concluídas
-- (Fatima, Tays ×2, Bassetto, UNI AUTO POSTO) contavam como "em andamento",
-- com 337,3 kWp em "kWp em andamento"; e a Fatima entraria em "atrasadas" a
-- partir de 16/11. O tempo médio por etapa (tempo_etapas) também usa < 8, mas
-- mede outra coisa e fica como está.
--
-- A tela (painel e TV) tinha o mesmo 8 e foi corrigida no mesmo PR.

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

-- alerta de prazos (alerta-prazos, 8h, para a equipe)
select pg_temp.troca('public.obras_para_alerta(integer)',
  $o$where o.etapa_numero < 8$o$,
  $n$where not coalesce(public.obra_ativa(o.id), false)$n$);

-- métricas: carteira em andamento (obras e kWp) e atrasadas
select pg_temp.troca('public.get_metricas(date,date)',
  $o$filter (where etapa_numero < 8)$o$,
  $n$filter (where not coalesce(public.obra_ativa(obras.id), false))$n$, 2);
select pg_temp.troca('public.get_metricas(date,date)',
  $o$where etapa_numero < 8 and cancelada_em is null$o$,
  $n$where not coalesce(public.obra_ativa(obras.id), false) and cancelada_em is null$n$);
