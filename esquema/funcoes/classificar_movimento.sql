CREATE OR REPLACE FUNCTION public.classificar_movimento(p_memo text, p_valor numeric)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_m text; v_regra record; v_parte record;
begin
  v_m := upper(translate(coalesce(p_memo,''),
          'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
          'AAAAAEEEEIIIIOOOOOUUUUCAAAAAEEEEIIIIOOOOOUUUUC'));

  select * into v_parte from partes_proprias
   where ativo and position(upper(identificador) in v_m) > 0 limit 1;
  if found then
    return json_build_object('classificacao','transferencia','confianca',10,
      'motivo', v_parte.descricao, 'automatico', true);
  end if;

  -- juros primeiro: "ENCARGOS LIMITE DE CRED" contém ENCARGO mas é custo financeiro
  if v_m ~ 'JUROS|CH\.ESPECIAL|CH ESPECIAL|LIMITE DE CRED|IOF |IOF-|MORA|MULTA' then
    return json_build_object('classificacao','custo_fixo','conta','06.2.02',
      'confianca',9,'motivo','Juros e encargos financeiros','automatico',true);
  end if;
  if v_m ~ 'TARIFA|CESTA|PACOTE DE SERV|ANUIDADE|MANUTENCAO DE CONTA|ENCARGO' then
    return json_build_object('classificacao','custo_fixo','conta','06.2.01',
      'confianca',9,'motivo','Tarifa bancária','automatico',true);
  end if;

  select * into v_regra from extrato_regras
   where position(upper(padrao) in v_m) > 0 order by length(padrao) desc limit 1;
  if found then
    return json_build_object('classificacao', v_regra.classificacao,
      'conta', v_regra.conta_codigo, 'obra', v_regra.obra_fixa,
      'ratear', v_regra.costuma_ratear,
      'confianca', least(9, 5 + v_regra.confirmacoes),
      'motivo','Padrão aprendido',
      'automatico', (v_regra.confirmacoes >= 2
        and (v_regra.valor_medio is null
             or abs(abs(p_valor) - v_regra.valor_medio) <= v_regra.valor_medio * 0.25)));
  end if;

  if p_valor > 300 then
    return json_build_object('classificacao','receber','confianca',3,
      'motivo','Entrada — buscar parcela em aberto','automatico',false);
  end if;
  if p_valor < -300 then
    return json_build_object('classificacao','indefinido','confianca',0,
      'motivo','Saída — obra ou custo fixo?','automatico',false);
  end if;
  return json_build_object('classificacao','indefinido','confianca',0,'automatico',false);
end; $function$
