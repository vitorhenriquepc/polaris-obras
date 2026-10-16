-- Régua d180 (6 meses): texto reescrito (Vitor, 15/10: "pode reescrever").
--
-- O texto antigo saiu para a Eloana em 14/10 com duas afirmações erradas
-- chumbadas: "a Sungrow exclui da cobertura..." (o inversor dela é Huawei; 48
-- dos 59 pendentes não são Sungrow) e "Plano de Monitoramento Polaris ... a
-- partir de R$ 289/ano" (esse plano não existe; R$ 289 é o Ativo, sem visita).
-- E os 59 pendentes já têm o Essencial de cortesia: o texto oferecia o que eles
-- já têm, sem dizer.
--
-- O que muda:
--  * nenhuma marca no texto. A frase da garantia é a mesma da proposta de
--    planos do posvenda.html, que já estava em uso ("o manual do seu inversor
--    ... não cobre falhas causadas por falta de manutenção");
--  * o parágrafo do plano é montado pelo regua_texto, com tudo do banco
--    (regra 3.1), num placeholder novo, {plano_frase}:
--      - quem já tem plano COM visita (Completo): "seu plano já inclui essa
--        visita — é só dizer o dia";
--      - quem tem plano SEM visita: diz qual é e, se for cortesia, até quando;
--      - o preço do Completo sai de `planos` pela faixa de módulos da obra
--        (mesma regra da contratos_para_avisar), com o desconto da tabela e o
--        adicional por endereço (config plano_endereco_adicional, vínculos
--        vigentes); acima de 125 módulos, "valor sob consulta"; sem módulos
--        cadastrados, não afirma preço.
--  * o modelo continua com precisa_aprovacao = true (posto em 14/10) até o
--    Vitor decidir se volta a sair sozinho.
--
-- regua_texto: só o bloco do {plano_frase} é novo; o resto é igual.

create or replace function public.regua_texto(p_obra uuid, p_modelo text)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_o record; v_m record; v_t text; v_g record;
  v_c record; v_cp record; v_achou boolean; v_end int; v_adic numeric; v_anual numeric; v_frase text;
begin
  select * into v_o from obras where id = p_obra;
  select * into v_m from regua_modelos where codigo = p_modelo;
  if v_o is null or v_m is null then return null; end if;

  v_t := replace(v_m.texto, '{nome}', public.nome_tratamento(v_o.cliente, v_o.categoria));
  v_t := replace(v_t, '{link_relatorio}',
      'https://obras.polarisenergiasolar.com/relatorio.html?id=' || coalesce(v_o.slug,''));
  v_t := replace(v_t, '{concessionaria}',
      coalesce(nullif(trim(v_o.concessionaria),''), 'concessionária de energia'));

  if v_t like '%{kwh}%' or v_t like '%{economia}%' or v_t like '%{arvores}%' or v_t like '%{desempenho}%' then
    select * into v_g from public.obra_geracao_total(p_obra);
    v_t := replace(v_t, '{kwh}',
             coalesce(replace(to_char(v_g.kwh,'FM999G999G999'), ',', '.'), '—'));
    v_t := replace(v_t, '{economia}',
             coalesce(replace(to_char(v_g.economia,'FM999G999G999'), ',', '.'), '—'));
    v_t := replace(v_t, '{desempenho}', coalesce(v_g.desempenho::text,'—'));
    v_t := replace(v_t, '{arvores}', coalesce(round(coalesce(v_g.kwh,0) * 0.0385 / 22)::text,'—'));
  end if;

  -- {plano_frase}: o plano que o cliente tem hoje e o Completo para o porte dele,
  -- tudo do banco (d180, 15/10). Nunca afirma preço que a tabela não tem.
  if v_t like '%{plano_frase}%' then
    select pc.plano_codigo, pc.fim, coalesce(pc.valor, 0) as valor,
           split_part(coalesce(pl.nome, pc.plano_codigo), ' — ', 1) as nome,
           coalesce(pl.inclui_visita, false) as visita
      into v_c
      from plano_contratos pc left join planos pl on pl.codigo = pc.plano_codigo
     where pc.obra_id = p_obra and pc.status = 'ativo' and (pc.fim is null or pc.fim >= current_date)
     order by pc.inicio desc nulls last limit 1;

    if v_c.plano_codigo is not null and v_c.visita then
      v_frase := 'Seu *plano ' || v_c.nome || '* já inclui essa visita — é só me dizer o melhor dia que a gente agenda.';
    else
      v_frase := case when v_c.plano_codigo is null then ''
                      else 'Hoje você já tem o *plano ' || v_c.nome || '*'
                           || case when v_c.valor = 0 and v_c.fim is not null
                                   then ' de cortesia até *' || to_char(v_c.fim, 'DD/MM/YYYY') || '*' else '' end
                           || ': a gente acompanha a geração e avisa se a usina parar. ' end
                 || 'A revisão presencial faz parte do *plano Completo*';

      select pl.preco_anual, pl.preco_mensal, pl.desconto_servicos into v_cp
        from planos pl
       where pl.ativo and pl.nivel = 3
         and coalesce(v_o.qtd_modulos, 0) between coalesce(pl.mod_min, 0) and coalesce(pl.mod_max, 9999)
       order by pl.mod_min limit 1;
      v_achou := found;
      v_end := greatest(1, coalesce((select count(distinct coalesce(nullif(btrim(coalesce(u.endereco,'')),''), u.cidade))
                                       from obra_usina ou join usinas u on u.id = ou.usina_id
                                      where ou.obra_id = p_obra and u.ativa and ou.saiu_em is null), 1));
      v_adic := coalesce((select valor::numeric from config where chave = 'plano_endereco_adicional'), 0) * (v_end - 1);

      if coalesce(v_o.qtd_modulos, 0) = 0 or not v_achou then
        v_frase := v_frase || ', com a visita técnica anual, a limpeza e o laudo — te mando o valor para o seu sistema.';
      elsif v_cp.preco_anual is null then
        v_frase := v_frase || ': para o seu sistema, com *' || v_o.qtd_modulos || ' módulos*, o valor é sob consulta, '
                   || 'e ele inclui a visita técnica anual, com a limpeza e o laudo.';
      else
        v_anual := v_cp.preco_anual + v_adic;
        v_frase := v_frase || ': para o seu sistema, com *' || v_o.qtd_modulos || ' módulos*, ele sai por *R$ '
                   || public._rm_num(v_anual, case when v_anual = round(v_anual) then 0 else 2 end) || '/ano*'
                   || case when v_end = 1 and v_cp.preco_mensal is not null
                           then ' (ou R$ ' || public._rm_num(v_cp.preco_mensal, 2) || '/mês)'
                           when v_end > 1 then ' (já com ' || (v_end - 1) || ' endereço' || case when v_end > 2 then 's' else '' end
                                               || ' além do primeiro — a visita é em cada um)'
                           else '' end
                   || ' e inclui a visita técnica anual, com a limpeza e o laudo'
                   || case when coalesce(v_cp.desconto_servicos, 0) > 0
                           then ', e *' || public._rm_num(v_cp.desconto_servicos, 0) || '% de desconto* em outros serviços'
                           else '' end || '.';
      end if;
    end if;
    v_t := replace(v_t, '{plano_frase}', v_frase);
  end if;

  return v_t;
end; $function$;

do $x$ begin
  update regua_modelos set texto =
'🔧 *{nome}, seu sistema completou 6 meses!*

É uma boa hora para a primeira revisão preventiva. Nela a gente verifica:

🔍 Limpeza e estado dos módulos
⚡ Conexões elétricas e aperto dos terminais
📊 Geração real × projetada
🛡️ Estrutura, fixações e aterramento

📄 Tudo fica registrado num *laudo técnico com fotos*. O manual do seu inversor traz um ponto que pouca gente lê: a garantia *não cobre falhas causadas por falta de manutenção* — e o laudo é o documento que o fabricante pede quando há acionamento de garantia.

{plano_frase}

Quer agendar a sua revisão ou receber os detalhes do plano? É só responder aqui. 📅

*Equipe Polaris Energia Solar* ☀️'
   where codigo = 'd180_manutencao';
  if not found then raise exception 'modelo d180_manutencao não encontrado'; end if;
end $x$;
