create or replace function public.get_nps(p_slug text, p_token text)
returns json language plpgsql security definer set search_path to 'public' as $$
declare v record; v_nps record;
begin
  select * into v from obras where slug = p_slug and nps_token = p_token;
  if not found then return null; end if;
  select * into v_nps from nps where obra_id = v.id;
  return json_build_object(
    'cliente', v.cliente, 'contrato', v.contrato, 'potencia_kwp', v.potencia_kwp,
    'slug', v.slug,
    'ja_respondeu', v_nps.nota is not null,
    'nota_atual', v_nps.nota,
    'brinde', v_nps.brinde,
    'voucher', v_nps.voucher,
    'brinde_em', v_nps.brinde_em,
    'entregue_em', v_nps.entregue_em
  );
end; $$;
grant execute on function public.get_nps(text, text) to anon, authenticated;
