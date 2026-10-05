-- Vistoria da concessionária: versão curta quando o relatório acabou de sair
-- (Vitor, 05/10: "muita mensagem nessa etapa").
--
-- O caso: MURILO ALEIXO CORREA (4804), 05/10. Às 16:03 o instalador mandou o
-- relatório e o `foto-obra` postou "Instalação concluída", as fotos e o
-- "Relatório oficial" (que já diz "assim que solicitarmos a vistoria, avisamos
-- aqui"). Às 16:05 a Lívia preencheu a data da vistoria e saiu a mensagem longa:
-- "Boa notícia… Sua instalação foi concluída…", o "não precisa fazer nada", o
-- link de acompanhamento e a assinatura — tudo o que o cliente tinha lido dois
-- minutos antes.
--
-- Juntar as duas numa só não dá: quando o relatório sai a vistoria ainda não
-- foi pedida, e segurar a mensagem do relatório esperando alguém preencher a
-- data é pior. Então, se `relatorio_enviado_em` é das últimas 48 horas, a
-- vistoria sai em três parágrafos: prazo, acesso ao padrão, e o que vem
-- depois. Vistoria pedida dias depois do relatório continua com o texto
-- completo (o cliente precisa do contexto), e a "Atualização da vistoria" não
-- muda. A função devolve `curta` para a tela saber qual versão vai.
--
-- `create or replace` mantém a ACL (authenticated + service_role, sem anon).

create or replace function public.cpfl_texto(p_obra uuid)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  o record; v_nome text; v_conc text; v_link text; v_corrige boolean; v_conta_de date;
  v_sem text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
  v_prazo text; v_texto text; v_curta boolean;
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

  if v_corrige then
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
    'curta', v_curta,
    'texto', v_texto);
end; $function$;
