-- 02/10/2026 — Autoleitura pode avisar mais de um WhatsApp pessoal.
--
-- Pedido do Vitor (02/10): no UNI AUTO POSTO (Júnior Bassetto) quem lê o
-- relógio da fazenda é o CASEIRO — o telefone da obra (18 99704-1415) já era o
-- dele — e o Júnior quer receber também, no WhatsApp pessoal (18 99791-0910).
-- O grupo continua recebendo. A régua NÃO muda: segue só no grupo.
--
-- unidade_consumidora.telefones_extra: números que também recebem o lembrete
-- daquele relógio. autoleitura_fila_svc devolve em `telefone` o da obra + os
-- extras, separados por vírgula e sem repetir; a edge function autoleitura-aviso
-- (v3) manda para cada um. Com um número só, o comportamento é o de antes.
-- Assinatura da função mantida: mudar o tipo de retorno pediria drop.
--
-- Conferido: simulação com a leitura de 09/10 trazida para hoje (rollback) →
-- grupo + 18997041415 + 18997910910; nenhum outro cliente mudou; edge function
-- com token errado → 403.

alter table unidade_consumidora add column if not exists telefones_extra text[];
comment on column unidade_consumidora.telefones_extra is 'Números que TAMBÉM recebem o lembrete de autoleitura deste relógio, além do telefone da obra (que é quem lê). Ex.: UNI AUTO POSTO — a obra tem o caseiro da fazenda, aqui vai o WhatsApp do dono (Júnior). Só autoleitura; a régua continua só no grupo.';

create or replace function public.autoleitura_fila_svc(p_tipo text)
 returns table(leitura_id uuid, obra_id uuid, cliente text, grupo text, telefone text, texto text)
 language sql stable security definer set search_path to 'public'
as $function$
  with base as (
    select l.id, l.data_prevista, l.avisado_vespera_em, l.avisado_dia_em,
           o.id as obra_id, o.cliente, o.whatsapp_grupo_id, o.optout_em,
           -- o telefone da obra primeiro, depois os extras do relógio (02/10:
           -- caseiro + dono na fazenda do UNI AUTO POSTO); vírgula separa, e a
           -- autoleitura-aviso manda para cada um
           nullif(array_to_string(array(
             select distinct on (f) f from (
               select 0 as ord, nullif(regexp_replace(coalesce(o.telefone,''),'\D','','g'),'') as f
               union all
               select 1, nullif(regexp_replace(x,'\D','','g'),'') from unnest(coalesce(u.telefones_extra,'{}')) x
             ) t where f is not null order by f, ord), ','), '') as fone,
           public.dia_util_ate(l.data_prevista - 1) as avisar_vespera,
           case when extract(dow from l.data_prevista) between 1 and 5
                then l.data_prevista end as avisar_dia
      from uc_leitura_prevista l
      join unidade_consumidora u on u.id = l.uc_id
      join obras o on o.id = u.obra_id
     where l.responsavel = 'cliente' and u.autoleitura and u.ativa
  )
  select b.id, b.obra_id, b.cliente,
         -- link de convite salvo no lugar do id nao serve para enviar
         case when b.whatsapp_grupo_id like 'http%' then null
              else b.whatsapp_grupo_id end,
         b.fone,
         public.autoleitura_texto(b.id, p_tipo)
  from base b
  where b.optout_em is null
    and ( (b.whatsapp_grupo_id is not null and b.whatsapp_grupo_id not like 'http%')
          or b.fone is not null )
    and (
      (p_tipo = 'vespera' and b.avisar_vespera = current_date and b.avisado_vespera_em is null)
      or
      (p_tipo = 'dia' and b.avisar_dia = current_date and b.avisado_dia_em is null)
    );
$function$;

-- dado (02/10): o Júnior no relógio da fazenda; apelido no nome que o Vitor aprovou
update unidade_consumidora set telefones_extra = '{18997910910}', apelido = 'Usina 2 — fazenda'
 where id = '0ad04b0f-f4d0-494b-93f8-6ca23a80f26c';
