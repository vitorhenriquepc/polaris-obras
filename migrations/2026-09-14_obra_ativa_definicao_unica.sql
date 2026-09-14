-- APLICADA em 14/09/2026, em duas migrações:
--   `obra_ativa_definicao_unica` e `fecha_helpers_obra_ativa_ao_anon`
--
-- Pedido do Vitor: além de corrigir o NPS, "corrigir os outros para não
-- acontecer de novo".

-- ============================================================
-- 1. A varredura: nenhuma outra automação dispara cedo
-- ============================================================
-- Conferi chamando cada uma e olhando a etapa de quem elas devolvem:
--
--   obras_para_iptu ........... 6 na fila, nenhuma antes da ativação
--   obras_para_optin .......... 0
--   aniversariantes_hoje ...... 0
--   gerar_regua ............... recusa: "Obra ainda não está ativa"
--   obras_para_cobrar_aceite .. 15, todas já na etapa 8 — pede o termo que
--                               falta assinar, então pré-ativação seria
--                               correto de qualquer forma
--
-- Ou seja: o furo era só no NPS (e no Google, que vinha atrás dele).

-- ============================================================
-- 2. A causa raiz, e o conserto dela
-- ============================================================
-- Cada automação escrevia a PRÓPRIA definição de "está ativa". Uma delas
-- escreveu errado — `aceite_em`, o termo assinado na vistoria — e ninguém
-- percebeu, porque não havia um lugar só para conferir.
--
-- Agora existe um jeito único de perguntar:
--
--   obra_ativa(obra)     → chegou na última etapa da PRÓPRIA trilha?
--                          padrao/eletroposto = 8, manutencao = 4
--   obra_ativa_em(obra)  → desde quando. coalesce(data_conclusao, entrada na
--                          última etapa via etapas_historico), porque
--                          data_conclusao vem nula em obra de verdade
--
-- ⚠️ Toda automação que fala com o CLIENTE deve passar por obra_ativa().
--
-- As demais continuam com `etapa >= 8` escrito à mão. Não reescrevi: elas não
-- disparam cedo, e mexer em quatorze funções que mandam mensagem para cliente
-- traz mais risco do que resolve. O que elas têm é o ponto cego oposto — a
-- trilha `manutencao` nunca chega na etapa 8, então nunca entra nelas. Isso é
-- decisão de produto, não bug: vale decidir se manutenção deve receber régua,
-- aniversário e IPTU.

create or replace function public.obra_ativa(p_obra uuid)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public'
as $$
  select o.etapa_numero >= coalesce((select max(e.numero) from etapas e where e.trilha = o.trilha), 8)
  from obras o where o.id = p_obra;
$$;

create or replace function public.obra_ativa_em(p_obra uuid)
 returns date
 language sql
 stable
 security definer
 set search_path to 'public'
as $$
  select coalesce(o.data_conclusao,
           (select max(h.entrou_em)::date from etapas_historico h
             where h.obra_id = o.id
               and h.etapa_numero >= coalesce((select max(e.numero) from etapas e where e.trilha = o.trilha), 8)))
  from obras o where o.id = p_obra;
$$;

-- ============================================================
-- 3. Permissão — e um erro meu no meio do caminho
-- ============================================================
-- Na primeira tentativa eu escrevi `revoke execute ... from anon` e fui
-- conferir: o anon CONTINUAVA executando. O Supabase concede EXECUTE a PUBLIC
-- por padrão, e PUBLIC inclui o anon — revogar de `anon` não tira uma
-- concessão que é de `public`. O revoke passa sem erro e não faz nada.
--
-- O jeito certo é tirar de public e devolver só para quem precisa. Estes
-- helpers nem precisam da tela: quem os chama são funções security definer,
-- que rodam como dono e não dependem do grant do chamador.
--
-- CONFERIDO: anon=false, authenticated=true, service_role=true.

revoke execute on function public.obra_ativa(uuid)    from public;
revoke execute on function public.obra_ativa_em(uuid) from public;

grant execute on function public.obra_ativa(uuid)     to authenticated, service_role;
grant execute on function public.obra_ativa_em(uuid)  to authenticated, service_role;

-- ============================================================
-- 4. As duas automações corrigidas passam a ler a definição única
-- ============================================================

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
    and public.obra_ativa(o.id)
    and public.obra_ativa_em(o.id) <= current_date - 1
  limit 20;
$function$;

create or replace function public.nps_para_lembrete_google()
 returns table(obra_id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text, brinde text, voucher text, lembretes smallint)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id,
         n.brinde, n.voucher, n.lembretes_google
  from nps n
  join obras o on o.id = n.obra_id
  where n.nota >= 9
    and public.obra_ativa(o.id)
    and n.avaliou_google_em is null
    and o.whatsapp_grupo_id is not null
    and n.lembretes_google < (select valor::int from config where chave = 'lembrete_google_max')
    and coalesce(n.lembrete_google_em, n.criado_em)
        <= now() - ((select valor::int from config where chave = 'lembrete_google_dias') || ' days')::interval
  limit 20;
$function$;

-- CONFERIDO depois de aplicar:
--   fila do NPS ....... 0
--   fila do Google .... 1 (só o Bassetto, manutenção concluída de verdade)
--   obra_ativa() ...... false para a SANDRA (4739) e para a VALDETE (4791)
