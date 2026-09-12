-- Guarda a data para a qual o lembrete D-1 já foi enviado
alter table public.obras add column if not exists instalacao_lembrete_em date;

-- Obras que instalam amanhã e ainda não receberam o lembrete daquela data
create or replace function public.obras_para_lembrete()
returns table (id uuid, cliente text, slug text, data_instalacao date, whatsapp_grupo_id text,
               endereco text, instalador text)
language sql security definer set search_path to 'public' as $$
  select o.id, o.cliente, o.slug, o.data_instalacao, o.whatsapp_grupo_id, o.endereco,
         (select e.nome from equipe e where e.id = o.instalador_id) as instalador
  from obras o
  where o.data_instalacao = current_date + 1
    and o.whatsapp_grupo_id is not null
    and (o.instalacao_lembrete_em is null or o.instalacao_lembrete_em <> o.data_instalacao)
  limit 30;
$$;
revoke execute on function public.obras_para_lembrete() from public, anon, authenticated;
