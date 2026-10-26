-- "Finalizado" é ter chegado na última etapa da PRÓPRIA trilha (26/10).
--
-- Continuação de 2026-10-26_em_andamento_pela_trilha.sql. O gatilho
-- trg_status_auto (fn_status_auto) escrevia obras.status com o mesmo 8 à mão:
-- etapa >= 8 é 'Finalizado'. A trilha `manutencao` vai de 0 a 4 (a 4 é
-- "Concluída"), então as 5 manutenções concluídas — Fatima Rino (3067), Tays
-- (a obra dela e a da visita), Bassetto (a corretiva) e UNI AUTO POSTO —
-- ficavam 'Em andamento' para sempre. O plano_cadastrar_cliente até grava
-- 'Finalizado' na etapa 4 da manutenção, e o gatilho desfazia.
--
-- Agora a regra é a mesma de obra_ativa(): etapa >= maior etapa da trilha da
-- obra (8 quando a trilha não tem etapas). Padrão e eletroposto não mudam. O
-- gatilho passa a olhar também a troca de trilha.
--
-- Quem lê obras.status, conferido em 26/10 antes de gravar:
--   - conferir_saude_base ("obra finalizada sem usina", conferência das 7h30)
--     passaria a contar a Fatima e a obra da visita da Tays, que não têm usina
--     porque manutenção não ganha usina. O achado é de instalação solar: fica
--     só na trilha padrão (o eletroposto também não tem usina, e daria o mesmo
--     falso alarme quando o 4674 chegar à etapa 8).
--   - vw_obras_paradas (status <> 'Finalizado' and etapa < 8): as 5 saem, que
--     é o certo. Nenhuma função, tela ou edge function lê a view.
--   - painel.html: o selo "Finalizado" no cartão, a ordem da lista
--     (finalizadas por último) e, no acervo do cliente, o texto do status e o
--     link "Relatório do sistema" (para manutenção, abre o laudo).
--   - get_acompanhamento, get_obra_publica, get_cliente_ficha,
--     get_relatorios_painel e get_clientes_acervo só devolvem o valor; nenhuma
--     decide nada por ele (a cliente.html nem lê o campo).
--   - edge functions (as 54 publicadas, lidas uma a uma): só a solarview-usinas
--     escolhe obra por status = 'Finalizado' — ferramenta manual de
--     diagnóstico, fora de todo cron, cuja única gravação (acao 'vincular') é
--     o campo legado obras.solarview_id, que nenhuma obra tem e nenhuma função
--     lê. As 5 manutenções passam a aparecer na lista dela; ela não manda
--     mensagem. A solarview-vincular tem .neq('status','Cancelado'), filtro que
--     nunca filtrou nada (armadilha 40), e só olha etapa >= 7.
-- Nenhuma automação que fala com cliente decide por obras.status: régua,
-- cortesia e NPS olham etapa ou obra_ativa() e já pulam a manutenção.
--
-- Simulado antes de gravar (transação que termina em erro): mudam só as 5
-- obras, de 'Em andamento' para 'Finalizado'; nenhuma outra coluna muda além
-- do atualizado_em delas (o fn_touch_updated); etapas_historico,
-- plano_contratos, regua_contatos, dre_lancamentos e obra_financeiro com as
-- mesmas contagens; conferir_saude_base igual antes e depois (sem a trava da
-- trilha padrão, "obra finalizada sem usina" iria de 3 para 5); e nenhuma obra
-- fora da regra depois. A regra nova testada numa tabela temporária com o
-- mesmo gatilho: padrão 0/7/8, manutenção 0/3/4, 4 → 3, eletroposto 7/8,
-- trilha nula, trilha inexistente e troca de trilha.

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

create or replace function public.fn_status_auto()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- a última etapa é a da trilha da obra (manutenção: 4), como em obra_ativa()
  new.status := case
    when new.etapa_numero >= coalesce((select max(e.numero) from etapas e where e.trilha = new.trilha), 8) then 'Finalizado'
    when new.etapa_numero = 0 then 'Boas-vindas'
    else 'Em andamento'
  end;
  return new;
end;
$function$;

create or replace trigger trg_status_auto
  before insert or update of etapa_numero, status, trilha on public.obras
  for each row execute function public.fn_status_auto();

-- "obra finalizada sem usina" é de instalação solar
select pg_temp.troca('public.conferir_saude_base()',
  $o$from obras o where o.status='Finalizado'$o$,
  $n$from obras o where o.status='Finalizado' and coalesce(o.trilha,'padrao') = 'padrao'$n$);

-- as 5 manutenções concluídas (o gatilho recalcula o status de quem é tocado)
update public.obras set status = 'Finalizado'
 where coalesce(public.obra_ativa(id), false) and status is distinct from 'Finalizado';
