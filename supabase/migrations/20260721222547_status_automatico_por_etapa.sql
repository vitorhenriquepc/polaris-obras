-- Status agora é derivado automaticamente da etapa
create or replace function public.fn_status_auto()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  new.status := case
    when new.etapa_numero >= 8 then 'Finalizado'
    when new.etapa_numero = 0 then 'Boas-vindas'
    else 'Em andamento'
  end;
  return new;
end;
$$;

drop trigger if exists trg_status_auto on public.obras;
create trigger trg_status_auto
  before insert or update of etapa_numero, status on public.obras
  for each row execute function public.fn_status_auto();

-- Corrigir os status existentes de uma vez
update public.obras set status = case
  when etapa_numero >= 8 then 'Finalizado'
  when etapa_numero = 0 then 'Boas-vindas'
  else 'Em andamento'
end;
