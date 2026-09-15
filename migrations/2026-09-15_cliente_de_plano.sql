-- Cliente de plano: quem paga o acompanhamento sem ter comprado a usina.
--
-- O caso que motivou: Tays Valese Dias do Prado, duas usinas instaladas pela
-- Eco Solar (acougue em Aracatuba, rancho em Birigui), plano Completo anual.
--
-- O banco ja sabia representar isso e ninguem tinha usado: obras.cliente_externo,
-- obras.sistema_origem e a trilha 'manutencao' existem desde sempre com ZERO
-- linhas. O painel.html ja desenha o selo "Cliente de outra empresa".
--
-- A obra dela nao e venda: valor_projeto fica nulo e ela nao entra em
-- conversao, margem nem funil. A obra existe porque plano_contratos.obra_id
-- e regua_contatos.obra_id sao NOT NULL -- a obra e a espinha do sistema.

-- ---------------------------------------------------------------------------
-- 1. Cliente de plano nao recebe NPS nem convite do Google.
--
-- Este e o ponto perigoso. obras_para_nps() e nps_para_lembrete_google()
-- filtram so por obra_ativa() + grupo de WhatsApp. Uma obra de trilha
-- 'manutencao' na etapa 4 ("Concluida") E a ultima etapa da propria trilha,
-- entao obra_ativa() devolve TRUE -- e a Tays receberia uma pesquisa
-- perguntando como foi a instalacao que a Eco Solar fez.
--
-- E a mesma classe de vazamento corrigida em 14/09, quando tres obras
-- receberam NPS na etapa 7 e uma entrou na fila do Google com a usina
-- desligada. A trava agora e explicita.
-- ---------------------------------------------------------------------------

create or replace function public.obras_para_nps()
returns table(id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text)
language sql security definer set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id
  from obras o
  where o.nps_enviado_em is null
    and o.whatsapp_grupo_id is not null
    and not coalesce(o.cliente_externo, false)
    and public.obra_ativa(o.id)
    and public.obra_ativa_em(o.id) <= current_date - 1
  limit 20;
$function$;

create or replace function public.nps_para_lembrete_google()
returns table(obra_id uuid, cliente text, slug text, nps_token text,
              whatsapp_grupo_id text, brinde text, voucher text, lembretes smallint)
language sql security definer set search_path to 'public'
as $function$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id,
         n.brinde, n.voucher, n.lembretes_google
  from nps n
  join obras o on o.id = n.obra_id
  where n.nota >= 9
    and not coalesce(o.cliente_externo, false)
    and public.obra_ativa(o.id)
    and n.avaliou_google_em is null
    and o.whatsapp_grupo_id is not null
    and n.lembretes_google < (select valor::int from config where chave = 'lembrete_google_max')
    and coalesce(n.lembrete_google_em, n.criado_em)
        <= now() - ((select valor::int from config where chave = 'lembrete_google_dias') || ' days')::interval
  limit 20;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Cliente de plano aparece na aba Planos.
--
-- get_planos_envio() cortava por `etapa_numero >= 8 and trilha <> 'manutencao'`,
-- entao um cliente de plano nunca apareceria no seletor -- a trilha
-- 'manutencao' vai so ate a etapa 4.
--
-- O corte por numero cru vira obra_ativa(), que e a definicao unica desde
-- 14/09 (secao 6 do CLAUDE.md). Para padrao e eletroposto o resultado e
-- identico ao de antes: as duas trilhas terminam na etapa 8.
-- ---------------------------------------------------------------------------

create or replace function public.get_planos_envio()
returns json
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'planos', (select coalesce(json_agg(json_build_object(
        'codigo',codigo,'nome',nome,'icone',icone,'nivel',nivel,
        'mod_min',mod_min,'mod_max',mod_max,
        'mensal',preco_mensal,'anual',preco_anual,
        'visita',inclui_visita,'desconto',desconto_servicos
      ) order by nivel, coalesce(mod_min,0)),'[]'::json)
      from planos where ativo),
    'clientes', (select coalesce(json_agg(json_build_object(
        'id',o.id,'cliente',o.cliente,'modulos',o.qtd_modulos,
        'kwp',o.potencia_kwp,'grupo',o.whatsapp_grupo_id,'telefone',o.telefone,
        'externo',coalesce(o.cliente_externo,false),
        'origem',o.sistema_origem,
        'plano_atual',(select coalesce(p.nome,c.plano_codigo) from plano_contratos c
                        left join planos p on p.codigo=c.plano_codigo
                        where c.obra_id=o.id and c.status in ('ativo','aguardando_pagamento')
                        order by c.criado_em desc limit 1),
        'vence_em',(select c.fim from plano_contratos c
                     where c.obra_id=o.id and c.status='ativo' order by c.fim desc limit 1)
      ) order by o.cliente),'[]'::json)
      from obras o
      where (
              (coalesce(o.trilha,'padrao') <> 'manutencao' and public.obra_ativa(o.id))
              or coalesce(o.cliente_externo,false)
            ))
  ) into v;
  return v;
end;
$function$;
