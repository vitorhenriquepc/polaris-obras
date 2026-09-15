-- A proposta passa a contar os enderecos do cliente.
--
-- O Completo vende "uma visita tecnica anual em CADA endereco", e visita e o
-- que custa mao de obra. Ate aqui a proposta so olhava o numero de modulos,
-- entao um cliente com duas propriedades recebia o preco de quem tem uma.
--
-- COMO SE CONTA UM ENDERECO
-- `count(distinct coalesce(endereco, cidade))` entre as usinas ativas do
-- cliente. Medido em 15/09/2026:
--
--   GILBERTO      4 usinas -> 1 local  (todas em Aracatuba)
--   ATA ACADEMIA  3 usinas -> 1 local  (todas em Aracatuba)
--   TAYS          2 usinas -> 2 locais (Aracatuba e Birigui)
--
-- Varias usinas no mesmo lugar NAO viram cobranca extra, que era o risco.
-- Quando `endereco` esta vazio a conta cai para a cidade, entao ela SUBESTIMA
-- em vez de superestimar -- a ATA provavelmente tem dois enderecos (a academia
-- e a casa do dono), mas os dois estao sem endereco preenchido e na mesma
-- cidade. Errar para menos e o lado seguro: nunca cobra a mais de ninguem, e
-- se corrige sozinho quando alguem preencher o endereco.

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

    -- quanto custa por ano cada endereco alem do primeiro
    'endereco_adicional', (select valor::numeric from config
                            where chave='plano_endereco_adicional'),

    'clientes', (select coalesce(json_agg(json_build_object(
        'id',o.id,'cliente',o.cliente,'modulos',o.qtd_modulos,
        'kwp',o.potencia_kwp,'grupo',o.whatsapp_grupo_id,'telefone',o.telefone,
        'externo',coalesce(o.cliente_externo,false),
        'origem',o.sistema_origem,
        'enderecos', greatest(1, coalesce((
            select count(distinct coalesce(u.endereco, u.cidade))
            from usinas u where u.cliente_id = o.cliente_id and u.ativa), 1)),
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
