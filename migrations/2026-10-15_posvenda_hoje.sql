-- APLICADA em 15/10. Sem login as duas devolvem nulo; ACL sem anon.
--
-- A aba "Hoje" do Pós-venda e o selo no Painel (15/10, plano das abas aprovado
-- pelo Vitor).
--
-- Medido em 08–15/10: só o Vitor abriu o posvenda.html (12 vezes, quase sempre
-- para aprovar na Régua); a Lívia, nenhuma — ela trabalha no painel.html. A
-- tela passa a abrir no que precisa de alguém, e o Painel ganha um selo
-- "Pós-venda · N" para levar quem está lá.
--
-- posvenda_selo(): o número do selo — mensagens da IA esperando aprovação (o
--   mesmo filtro do get_regua_aprovacoes), clientes esperando resposta (a
--   escada da Isabela) e indicações novas. Leve, para o Painel chamar de tempos
--   em tempos.
-- posvenda_hoje(): o selo + a mesma lista que a Lívia recebe às 8h
--   (pendencias_posvenda, que é só do service_role e não confere quem chama —
--   por isso a porta é esta, com is_autorizado()).

create or replace function public.posvenda_selo()
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_ap int; v_es int; v_in int;
begin
  if not is_autorizado() then return null; end if;
  select count(*) into v_ap
    from regua_contatos c join regua_modelos m on m.codigo = c.modelo join obras o on o.id = c.obra_id
   where c.status = 'pendente' and c.status_aprovacao = 'aguardando';
  select count(*) into v_es from atendimento_espera where fechado_em is null;
  select count(*) into v_in from indicacoes where status = 'nova';
  return json_build_object('aprovar', v_ap, 'esperando', v_es, 'indicacoes', v_in, 'total', v_ap + v_es + v_in);
end $function$;

create or replace function public.posvenda_hoje()
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not is_autorizado() then return null; end if;
  return json_build_object('selo', public.posvenda_selo(), 'pendencias', public.pendencias_posvenda());
end $function$;

comment on function public.posvenda_selo() is
  'O número do selo "Pós-venda · N" do Painel: aprovações da IA + clientes esperando resposta + indicações novas (15/10).';
comment on function public.posvenda_hoje() is
  'A aba Hoje do posvenda.html: o selo + a mesma lista do aviso das 8h (pendencias_posvenda), atrás de is_autorizado() (15/10).';

revoke execute on function public.posvenda_selo() from public;
revoke execute on function public.posvenda_selo() from anon;
grant  execute on function public.posvenda_selo() to authenticated;
grant  execute on function public.posvenda_selo() to service_role;
revoke execute on function public.posvenda_hoje() from public;
revoke execute on function public.posvenda_hoje() from anon;
grant  execute on function public.posvenda_hoje() to authenticated;
grant  execute on function public.posvenda_hoje() to service_role;
