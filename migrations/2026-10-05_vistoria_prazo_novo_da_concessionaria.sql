-- Vistoria: prazo novo dado pela concessionária (Vitor, 05/10).
--
-- LUCIANA CORDEIRO DE ANDRADE (4750): vistoria solicitada em 18/09, prazo dos
-- 5 dias úteis 25/09 — vencido. A CPFL respondeu: "Estamos providenciando a
-- liberação do atendimento até 07/10/2026". A data da SOLICITAÇÃO não muda;
-- quem muda é o prazo. `cpfl_prazo_em` passa a 07/10 direto (o trg_cpfl só
-- recalcula quando muda a data da solicitação, então o valor fica).
--
-- A `cpfl_texto` não sabia dizer isso: com o prazo diferente do avisado, ela
-- montava a "Atualização da vistoria" falando em "data da solicitação
-- corrigida para 18/09" e "5 dias úteis a partir de 21/09 … até 07/10" — conta
-- que não fecha. Agora, quando o prazo não é o dos 5 dias úteis, o texto diz que
-- a concessionária deu um prazo novo, e a função devolve
-- `prazo_da_concessionaria`.
--
-- ⚠️ Se alguém mudar a data da solicitação no card depois disso, o trg_cpfl
-- recalcula o prazo pelos 5 dias úteis e o 07/10 se perde.
--
-- Nada é enviado aqui: a mensagem sai quando a equipe apertar o 📣 no card.

create or replace function public.cpfl_texto(p_obra uuid)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  o record; v_nome text; v_conc text; v_link text; v_corrige boolean; v_conta_de date;
  v_sem text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
  v_prazo text; v_texto text; v_curta boolean; v_da_conc boolean;
begin
  if not is_autorizado() then return null; end if;
  select cliente, slug, cpfl_solicitado_em, cpfl_prazo_em, cpfl_avisado_em, cpfl_avisado_prazo,
         whatsapp_grupo_id, concessionaria, etapa_numero, coalesce(trilha, 'padrao') as trilha,
         relatorio_enviado_em
    into o from obras where id = p_obra;
  if not found then
    return json_build_object('erro', 'Obra não encontrada');
  end if;
  if o.trilha <> 'padrao' then
    return json_build_object('erro', 'A vistoria da concessionária só tem aviso automático em obra de instalação');
  end if;
  if o.cpfl_solicitado_em is null then
    return json_build_object('erro', 'Preencha a data em que a vistoria foi solicitada');
  end if;
  -- sem grupo o texto ainda serve (o "enviar no WhatsApp" do card manda para o
  -- celular do cliente); quem recusa mandar no grupo é a tela, pelo `grupo` nulo

  v_conc  := coalesce(nullif(trim(o.concessionaria), ''), 'concessionária de energia');
  v_nome  := split_part(trim(o.cliente), ' ', 1);
  v_nome  := upper(substr(v_nome, 1, 1)) || lower(substr(v_nome, 2));
  v_link  := coalesce((select valor from config where chave = 'cliente_base_url'),
                      'https://obras.polarisenergiasolar.com/cliente.html') || '?id=' || o.slug;
  -- o primeiro dos 5 dias úteis: o dia útil seguinte à solicitação
  v_conta_de := soma_dias_uteis(o.cpfl_solicitado_em, 1);
  v_prazo := to_char(o.cpfl_prazo_em, 'DD/MM') || ' (' || v_sem[extract(dow from o.cpfl_prazo_em)::int + 1] || ')';
  v_corrige := o.cpfl_avisado_prazo is not null and o.cpfl_avisado_prazo is distinct from o.cpfl_prazo_em;
  -- o "Relatório oficial" do foto-obra acabou de dizer que a instalação
  -- terminou e trouxe o link de acompanhamento: não repetir (Vitor, 05/10)
  v_curta := not v_corrige and o.relatorio_enviado_em > now() - interval '48 hours';
  -- prazo que não sai da conta dos 5 dias úteis: foi a concessionária que deu
  -- um prazo novo (LUCIANA 4750, 05/10: "liberação do atendimento até 07/10").
  -- Aí o texto não pode falar em "data da solicitação corrigida" nem em
  -- "5 dias úteis a partir de", porque a conta não fecha.
  v_da_conc := o.cpfl_prazo_em is distinct from soma_dias_uteis(o.cpfl_solicitado_em, 5);

  if v_da_conc then
    v_texto := case when o.cpfl_avisado_em is not null or o.cpfl_avisado_prazo is not null
                    then '📅 *Atualização da vistoria*' else '📅 *Vistoria da ' || v_conc || '*' end
      || chr(10) || chr(10)
      || 'Olá, ' || v_nome || '! A ' || v_conc || ' nos informou um novo prazo: '
      || 'a inspeção e a troca do medidor devem acontecer até *' || v_prazo || '*.' || chr(10) || chr(10)
      || 'Só precisa ter alguém no local para dar acesso ao padrão. '
      || 'Assim que o medidor for trocado, seu sistema é ligado e começa a gerar. 💚' || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  elsif v_corrige then
    v_texto := '📅 *Atualização da vistoria*' || chr(10) || chr(10)
      || 'Olá, ' || v_nome || '! A data da solicitação da vistoria da ' || v_conc || ' foi corrigida para *'
      || to_char(o.cpfl_solicitado_em, 'DD/MM') || '*.' || chr(10) || chr(10)
      || 'Os *5 dias úteis* contam a partir de ' || to_char(v_conta_de, 'DD/MM')
      || ', então a inspeção e a troca do medidor devem acontecer até *' || v_prazo || '*.' || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  elsif v_curta then
    v_texto := '📅 *Vistoria da ' || v_conc || ' solicitada, ' || v_nome || '!*' || chr(10) || chr(10)
      || 'A troca do medidor deve acontecer até *' || v_prazo || '* — são 5 dias úteis, contando de '
      || to_char(v_conta_de, 'DD/MM') || '.' || chr(10) || chr(10)
      || 'Só precisa ter alguém no local para dar acesso ao padrão. '
      || 'Depois disso o sistema é ligado e começa a gerar. 💚';
  else
    v_texto := 'Boa notícia, ' || v_nome || '! ☀️' || chr(10) || chr(10)
      || 'Sua instalação foi concluída e já solicitamos a *vistoria da ' || v_conc || '*.' || chr(10) || chr(10)
      || 'A concessionária tem até *5 dias úteis* para fazer a inspeção e a troca do medidor. '
      || 'Contando a partir de ' || to_char(v_conta_de, 'DD/MM') || ', isso deve acontecer até *' || v_prazo || '*.'
      || chr(10) || chr(10)
      || 'Não precisa fazer nada. Só é importante que alguém esteja no local para dar acesso ao padrão, '
      || 'e que o portão esteja destrancado se o medidor ficar dentro.' || chr(10) || chr(10)
      || 'Assim que o medidor for trocado, seu sistema é ligado e começa a gerar. Qualquer dúvida, é só chamar aqui. 💚'
      || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
  end if;

  return json_build_object(
    'ok', true, 'cliente', o.cliente, 'solicitado', o.cpfl_solicitado_em, 'conta_de', v_conta_de,
    'prazo', o.cpfl_prazo_em, 'etapa', o.etapa_numero, 'grupo', o.whatsapp_grupo_id,
    'ja_avisado', o.cpfl_avisado_em,
    -- a data mudou mas o prazo que o cliente leu continua o mesmo: nada a dizer
    'mesmo_prazo', coalesce(o.cpfl_avisado_em is null and o.cpfl_avisado_prazo = o.cpfl_prazo_em, false),
    'correcao', v_corrige,
    'curta', v_curta and not v_da_conc,
    'prazo_da_concessionaria', v_da_conc,
    'texto', v_texto);
end; $function$;

-- o prazo novo da Luciana (só o prazo; a data da solicitação fica 18/09)
do $x$ begin
  update obras set cpfl_prazo_em = '2026-10-07'
   where id = '5cbb3c39-faef-46b5-8e84-69457f6b4d87' and cpfl_solicitado_em = '2026-09-18';
end $x$;
