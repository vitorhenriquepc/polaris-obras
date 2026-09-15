-- O contrato de plano passa a poder existir antes do dinheiro entrar.
--
-- Motivo: a Tays Valese Dias do Prado fechou o Completo anual em 15/09/2026,
-- e o combinado com ela e que os 12 meses contem a partir do PRIMEIRO
-- PAGAMENTO, nao da assinatura. Ate aqui `inicio` era NOT NULL, entao nao
-- havia como representar um contrato assinado e ainda nao pago: ou se
-- inventava uma data de inicio, ou o contrato nao existia.
--
-- Os 53 contratos que ja existem sao todos 'ativo', cortesia, R$ 0,00
-- (conferido em 15/09/2026). Nenhum deles e tocado por esta migracao.

alter table plano_contratos alter column inicio drop not null;
alter table plano_contratos add column if not exists primeiro_pagamento_em date;

comment on column plano_contratos.primeiro_pagamento_em is
  'Quando o primeiro pagamento entrou. E esta data que liga o contrato: '
  'inicio e fim sao calculados a partir dela por plano_registrar_pagamento().';

alter table plano_contratos drop constraint if exists plano_contratos_status_ok;
alter table plano_contratos add constraint plano_contratos_status_ok
  check (status in ('aguardando_pagamento','ativo','encerrado','cancelado'));

-- contrato sem data de inicio so pode existir enquanto espera o pagamento
alter table plano_contratos drop constraint if exists plano_contratos_inicio_ok;
alter table plano_contratos add constraint plano_contratos_inicio_ok
  check (inicio is not null or status = 'aguardando_pagamento');


-- Liga o contrato no dia em que o pagamento entrou.
create or replace function public.plano_registrar_pagamento(
  p_contrato uuid, p_data date default current_date)
returns json
language plpgsql security definer set search_path to 'public'
as $function$
declare v record; v_fim date;
begin
  if not is_autorizado() then
    return json_build_object('erro','Sem permissao.');
  end if;

  select * into v from plano_contratos where id = p_contrato;
  if not found then
    return json_build_object('erro','Contrato nao encontrado.');
  end if;

  if v.status <> 'aguardando_pagamento' then
    return json_build_object('erro',
      'Este contrato ja comecou em '||coalesce(to_char(v.inicio,'DD/MM/YYYY'),'?')||'.');
  end if;

  if p_data > current_date then
    return json_build_object('erro','A data do pagamento nao pode ser no futuro.');
  end if;

  v_fim := (p_data + (coalesce(v.meses,12)||' months')::interval)::date;

  update plano_contratos
     set inicio = p_data,
         fim = v_fim,
         primeiro_pagamento_em = p_data,
         status = 'ativo'
   where id = p_contrato;

  return json_build_object('ok',true,'inicio',p_data,'fim',v_fim,
                           'meses',coalesce(v.meses,12));
end;
$function$;

-- Armadilha 10 do CLAUDE.md, com a correcao aprendida aqui: NAO BASTA tirar
-- de PUBLIC. O Supabase tambem concede EXECUTE DIRETO ao anon em toda funcao
-- nova, por `alter default privileges`. Sao duas concessoes diferentes e
-- precisam dos dois revokes.
--
-- Medido depois de aplicar so o revoke de public:
--   proacl = {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,...}
--   has_function_privilege('anon', ...) = TRUE
--
-- Depois dos dois, a ACL fica igual a de calibrar_tarifa, ligar_automacao e
-- regua_toggle -- sem anon nenhum.
revoke execute on function public.plano_registrar_pagamento(uuid, date) from public;
revoke execute on function public.plano_registrar_pagamento(uuid, date) from anon;
grant  execute on function public.plano_registrar_pagamento(uuid, date) to authenticated;
