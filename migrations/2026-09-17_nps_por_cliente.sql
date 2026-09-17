-- 17/09/2026 — Duas decisões do Vitor sobre o funil da avaliação.
--
-- 1) "NPS é por cliente" — aqui, na obras_para_nps().
-- 2) "o promotor pode liberar" — na edge function nps-resposta, versionada em
--    supabase/functions/nps-resposta/index.ts. Não é SQL, mas anda junto:
--    `pedeGoogle` deixou de exigir elogio limpo e agora é só `nota >= 9`.
--    A ressalva continua acionando a equipe — as duas coisas viraram
--    independentes, que era o que faltava. Conferido em modo simular, sem
--    gravar nem enviar: nota 10 com ressalva devolve
--    `pede_google: true, avisa_equipe: true`; nota 6 devolve `false/true`;
--    elogio limpo devolve `true/false`.
--
-- Sobre a 1: `nps` continua UNIQUE por `obra_id`. O que muda é quem é
-- PERGUNTADO. Cliente que já respondeu numa obra não recebe a pesquisa de novo
-- por causa de uma segunda obra.
--
-- A trava só vale quando `cliente_id` existe. **4 das 75 obras não têm** — a
-- tela grava `cliente` (texto) e o `cliente_id` vem depois, por outro processo
-- (§4). Sem ele a regra cai no comportamento antigo, por obra, e esse é o lado
-- seguro: nunca cala um NPS legítimo, só o comprovadamente repetido.
--
-- Medido antes de aplicar: **1 obra** muda de comportamento — o eletroposto do
-- Jose Antonio Bassetto (4674, etapa 1), cujo cliente já respondeu 10 na obra
-- de manutenção em 10/09. Nenhuma outra obra da base bate na trava, e a fila do
-- NPS hoje está vazia.
--
-- ⚠️ Consequência a saber: cliente que comprar um SEGUNDO sistema daqui a dois
-- anos também não será perguntado. Se um dia isso incomodar, o lugar de mexer
-- é este `not exists` — uma janela de meses resolveria.

create or replace function public.obras_para_nps()
returns table(id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text)
language sql
security definer
set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id
  from obras o
  where o.nps_enviado_em is null
    and o.whatsapp_grupo_id is not null
    and not coalesce(o.cliente_externo, false)
    and public.obra_ativa(o.id)
    and public.obra_ativa_em(o.id) <= current_date - 1
    -- NPS é por CLIENTE: quem já respondeu numa obra não é perguntado de novo
    and not exists (
      select 1
      from obras o2
      join nps n2 on n2.obra_id = o2.id
      where o.cliente_id is not null
        and o2.cliente_id = o.cliente_id
        and o2.id <> o.id)
  limit 20;
$function$;
