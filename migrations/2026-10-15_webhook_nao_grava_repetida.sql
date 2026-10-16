-- APLICADA em 15/10. Testada com mensagem real de teste: a original entrou, a
-- repetida voltou "repetida", a edição entrou (as 2 linhas de teste ficaram na
-- obra 4147: o delete pelo MCP fica esperando confirmação — armadilha 32).
--
-- O mesmo recado gravado duas ou três vezes (15/10, achado da análise das abas).
--
-- A Z-API entrega de novo a mesma mensagem — mesmo messageId, mesmo texto —
-- segundos depois (mediana de 16 s entre as cópias; o webhook demora porque
-- classifica com a IA antes de responder). O webhook gravava todas: 89
-- identificadores repetidos em 30 dias. Foi assim que "vou mandar pra minha
-- nora" (11/09) virou TRÊS indicações, e "tenho maior satisfação indicar"
-- (21/09), duas — o gatilho msg_indicacao_auto cria uma indicação por linha.
--
-- O que NÃO é repetição e continua como estava: a EDIÇÃO (mesmo messageId,
-- texto novo — "Bom di" → "Bom diaaa") entra como linha nova, e os eventos sem
-- conteúdo ([senderPhoto], [notification]) também. Atualizar o texto na edição
-- exigiria o trg_mascara_credencial rodar no UPDATE, e não era o problema.
--
-- webhook_ja_visto(id, texto): trava atômica por (messageId, md5 do texto).
-- Devolve false na primeira vez e true nas seguintes — duas cópias chegando
-- juntas não passam as duas. webhook_esquecer solta a trava quando a gravação
-- falha, para a Z-API poder entregar de novo. Só o service_role chama.

create table if not exists public.webhook_vistos (
  zapi_message_id text not null,
  texto_md5 text not null,
  visto_em timestamptz not null default now(),
  primary key (zapi_message_id, texto_md5)
);
alter table public.webhook_vistos enable row level security;
comment on table public.webhook_vistos is
  'Trava do webhook-whatsapp-v2 contra a mesma mensagem (messageId + texto) entregue de novo pela Z-API. Sem policy: só o service_role lê e grava.';

create or replace function public.webhook_ja_visto(p_id text, p_texto text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_n int;
begin
  if coalesce(p_id, '') = '' then return false; end if;
  insert into webhook_vistos (zapi_message_id, texto_md5)
  values (p_id, md5(coalesce(p_texto, '')))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n = 0;
end $function$;

create or replace function public.webhook_esquecer(p_id text, p_texto text)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  delete from webhook_vistos where zapi_message_id = p_id and texto_md5 = md5(coalesce(p_texto, ''));
$function$;

revoke execute on function public.webhook_ja_visto(text, text) from public;
revoke execute on function public.webhook_ja_visto(text, text) from anon;
revoke execute on function public.webhook_ja_visto(text, text) from authenticated;
grant  execute on function public.webhook_ja_visto(text, text) to service_role;
revoke execute on function public.webhook_esquecer(text, text) from public;
revoke execute on function public.webhook_esquecer(text, text) from anon;
revoke execute on function public.webhook_esquecer(text, text) from authenticated;
grant  execute on function public.webhook_esquecer(text, text) to service_role;
