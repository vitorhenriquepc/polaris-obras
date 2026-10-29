-- 29/10: a mesma mensagem não sai duas vezes para o mesmo grupo
--
-- JULIANO BARAVIERA (4924), 29/10: o cliente recebeu duas vezes o aviso da
-- vistoria ("Boa notícia, Juliano!"), às 11:02:25 e às 11:06:36. A primeira
-- saiu ao salvar a data da vistoria no card, como devia. A segunda saiu pelo
-- 📣 "Avisar no grupo": em obra na etapa 7 ele chamava avisarCpfl(id, forcar),
-- e o forcar pulava a conferência de "o cliente já leu esta data". A única
-- barreira era a pergunta "Reenviar o aviso da vistoria no grupo do cliente?".
-- O registro dos pedidos mostra a sequência: nenhum salvamento entre os dois,
-- e às 11:06:30–32 cpfl_texto, notificar-grupo, cpfl_marcar_avisado e a
-- releitura do quadro, que é exatamente o que o 📣 faz.
--
-- Não foi o único. TANAKA (4745), 20/10: o pacote inteiro do relatório
-- (abertura, fotos e "Relatório oficial") saiu duas vezes, 23 s de diferença,
-- pelo "enviar novamente" do instalador (foto-obra com force, que pula a trava
-- do relatorio_enviado_em). Desde 15/10, quando o que sai pelo número da
-- Isabela passou a ser gravado, são esses dois os textos repetidos num grupo.
--
-- Aqui: o notificar-grupo, por onde sai o que a equipe manda ao grupo pelas
-- telas (painel, pós-venda, relatório), reserva o envio antes de mandar. O
-- mesmo texto para o mesmo grupo nas últimas 24 h é recusado, com a hora do
-- primeiro. A reserva é atômica (trava por grupo + texto até o fim da
-- transação): dois cliques, duas abas ou duas pessoas ao mesmo tempo não passam
-- os dois. Envio que a Z-API recusou não segura o próximo; reserva que ficou
-- sem resposta (a função morreu no meio) segura só 10 minutos.
-- Guarda o md5 do texto e o começo dele (60 caracteres), para conferência.
-- O painel e o foto-obra mudam junto (ver o PR).

create table if not exists public.envios_grupo (
  id bigserial primary key,
  grupo_id text not null,
  texto_md5 text not null,
  previa text,
  reservado_em timestamptz not null default now(),
  ok boolean,
  concluido_em timestamptz
);
create index if not exists envios_grupo_busca on public.envios_grupo (grupo_id, texto_md5, reservado_em desc);
alter table public.envios_grupo enable row level security;
revoke all on public.envios_grupo from anon, authenticated;
comment on table public.envios_grupo is
  'Trava do notificar-grupo contra o mesmo texto para o mesmo grupo em 24 h (JULIANO 4924, 29/10). ok: null = saindo, true = a Z-API aceitou, false = falhou (não segura o próximo). Sem policy: só o service_role lê e grava.';

create or replace function public.envio_grupo_reservar(p_grupo text, p_texto text)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_md5 text := md5(coalesce(p_texto, ''));
  v_ant record;
  v_id bigint;
begin
  if coalesce(trim(p_grupo), '') = '' or coalesce(p_texto, '') = '' then
    return json_build_object('erro', 'grupo e texto são obrigatórios');
  end if;
  -- um pedido por vez para este grupo + texto: o segundo espera o primeiro
  -- terminar e então já enxerga a reserva dele
  perform pg_advisory_xact_lock(hashtext(p_grupo), hashtext(v_md5));
  select id, reservado_em, ok into v_ant
    from envios_grupo
   where grupo_id = p_grupo and texto_md5 = v_md5
     and ((ok and reservado_em > now() - interval '24 hours')
          or (ok is null and reservado_em > now() - interval '10 minutes'))
   order by reservado_em desc
   limit 1;
  if found then
    return json_build_object(
      'ja_enviado', v_ant.reservado_em,
      'enviando', v_ant.ok is null,
      'quando', to_char(v_ant.reservado_em at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI'));
  end if;
  insert into envios_grupo (grupo_id, texto_md5, previa)
  values (p_grupo, v_md5, left(p_texto, 60))
  returning id into v_id;
  return json_build_object('id', v_id);
end $function$;

create or replace function public.envio_grupo_concluir(p_id bigint, p_ok boolean)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update envios_grupo set ok = p_ok, concluido_em = now() where id = p_id;
$function$;

-- armadilha 10: os dois revokes; só o service_role (o notificar-grupo) chama
revoke execute on function public.envio_grupo_reservar(text, text) from public;
revoke execute on function public.envio_grupo_reservar(text, text) from anon;
revoke execute on function public.envio_grupo_reservar(text, text) from authenticated;
grant  execute on function public.envio_grupo_reservar(text, text) to service_role;
revoke execute on function public.envio_grupo_concluir(bigint, boolean) from public;
revoke execute on function public.envio_grupo_concluir(bigint, boolean) from anon;
revoke execute on function public.envio_grupo_concluir(bigint, boolean) from authenticated;
grant  execute on function public.envio_grupo_concluir(bigint, boolean) to service_role;
