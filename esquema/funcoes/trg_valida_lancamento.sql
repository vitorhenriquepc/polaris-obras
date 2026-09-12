CREATE OR REPLACE FUNCTION public.trg_valida_lancamento()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_nivel int;
begin
  select nivel into v_nivel from dre_plano_contas where codigo = new.conta_codigo;
  if v_nivel is null then
    raise exception 'Conta % não existe no plano de contas', new.conta_codigo;
  end if;
  if v_nivel < 3 then
    raise exception 'Conta % é agrupadora — lance numa conta de último nível', new.conta_codigo;
  end if;
  if new.valor is null or new.valor = 0 then
    raise exception 'Lançamento sem valor';
  end if;
  return new;
end $function$
