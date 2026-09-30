-- 30/09/2026 — Vistoria da concessionária: uma mensagem só, com a data certa.
--
-- Pedido do Vitor (30/09): os 5 dias úteis contam a partir do PRÓXIMO dia útil
-- depois da solicitação (pedido em 30/09 → conta de 01/10 → prazo 07/10), e
-- preencher a data da solicitação tem de levar a obra para a vistoria sozinho,
-- sem duas mensagens no grupo.
--
-- O que estava errado (medido em 30/09):
--
-- 1. `cpfl_texto` QUEBRAVA TODA VEZ desde 27/08 19:15 UTC (migração
--    `concessionaria_por_obra`): o texto passou a usar `v_obra.concessionaria`,
--    uma variável que não existe na função → "missing FROM-clause entry for
--    table v_obra". É ela que monta o aviso quando a data é preenchida no card.
--    O último aviso que saiu é de 27/08 17:55 (EDVALDO); depois disso 7 obras
--    tiveram a data preenchida e NENHUMA foi marcada como avisada.
--
-- 2. A conta do banco sempre esteve certa — `soma_dias_uteis` pula o dia da
--    solicitação e conta a partir do próximo dia útil (fim de semana e
--    `feriados` fora). O erro era a TELA: `fmtD()` fazia `new Date('2026-10-07')`,
--    que o navegador lê como meia-noite UTC = 21h do dia 06 em Brasília. A
--    mensagem do kanban dizia "até 06/10 (terça)" para um prazo de 07/10
--    (quarta) — um dia a menos, como se a contagem começasse no próprio dia.
--    Corrigido no painel.html (parseDate/fmtD leem data pura como data local).
--
-- 3. Havia DOIS textos da vistoria (este e o `buildWA()` da tela) e dois
--    caminhos que mandavam, sem saber um do outro: a data no card e a etapa 7
--    no kanban. Agora o texto é um só (este) e a tela só manda se o cliente
--    ainda não foi avisado DESTA data.

alter table obras add column if not exists cpfl_avisado_prazo date;
comment on column obras.cpfl_avisado_prazo is 'O prazo da vistoria que o cliente leu no último aviso. Data da solicitação mudou e o prazo também → o próximo aviso é uma atualização; mudou e o prazo é o mesmo → não manda de novo.';

-- quem já foi avisado leu o prazo de hoje (os dois de agosto)
update obras set cpfl_avisado_prazo = cpfl_prazo_em
 where cpfl_avisado_em is not null and cpfl_avisado_prazo is null;

insert into config (chave, valor) values
  ('cliente_base_url', 'https://obras.polarisenergiasolar.com/cliente.html')
on conflict (chave) do nothing;

-- A data da solicitação manda:
--   * calcula o prazo (5 dias úteis a partir do próximo dia útil);
--   * o aviso anterior deixa de valer (era de outra data);
--   * obra de instalação que ainda não estava na vistoria VAI para ela — é o
--     "preencheu a data, avançou o card" pedido pelo Vitor. Feito aqui, e não
--     na tela, para valer em qualquer caminho que grave a data.
-- 7 = "Vistoria e Conexão" da trilha padrão (é o ETAPA_VISTORIA do painel).
-- Só na padrão: no eletroposto a 7 é "Comissionamento" e a manutenção não tem
-- vistoria. Mudar a etapa daqui não perde efeito: os gatilhos de 6→7 não fazem
-- nada (status e aceite só mexem da 8 em diante) e o fn_log_etapa, que é AFTER,
-- registra a entrada na 7 no histórico.
create or replace function public.trg_cpfl_prazo()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.cpfl_solicitado_em is distinct from old.cpfl_solicitado_em then
    new.cpfl_prazo_em := case when new.cpfl_solicitado_em is null then null
                              else soma_dias_uteis(new.cpfl_solicitado_em, 5) end;
    new.cpfl_avisado_em := null;
    if new.cpfl_solicitado_em is not null
       and coalesce(new.trilha, 'padrao') = 'padrao'
       and coalesce(new.etapa_numero, 0) < 7 then
      new.etapa_numero := 7;
    end if;
  end if;
  return new;
end; $function$;

-- O texto ÚNICO da vistoria. A tela não monta outro.
create or replace function public.cpfl_texto(p_obra uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $function$
declare
  o record; v_nome text; v_conc text; v_link text; v_corrige boolean; v_conta_de date;
  v_sem text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
  v_prazo text; v_texto text;
begin
  if not is_autorizado() then return null; end if;
  select cliente, slug, cpfl_solicitado_em, cpfl_prazo_em, cpfl_avisado_em, cpfl_avisado_prazo,
         whatsapp_grupo_id, concessionaria, etapa_numero, coalesce(trilha, 'padrao') as trilha
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

  if v_corrige then
    v_texto := '📅 *Atualização da vistoria*' || chr(10) || chr(10)
      || 'Olá, ' || v_nome || '! A data da solicitação da vistoria da ' || v_conc || ' foi corrigida para *'
      || to_char(o.cpfl_solicitado_em, 'DD/MM') || '*.' || chr(10) || chr(10)
      || 'Os *5 dias úteis* contam a partir de ' || to_char(v_conta_de, 'DD/MM')
      || ', então a inspeção e a troca do medidor devem acontecer até *' || v_prazo || '*.' || chr(10) || chr(10)
      || 'Acompanhe sua obra aqui:' || chr(10) || v_link || chr(10) || chr(10)
      || '*Equipe Polaris Energia Solar* ☀️';
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
    'texto', v_texto);
end; $function$;

create or replace function public.cpfl_marcar_avisado(p_obra uuid)
returns json language plpgsql security definer set search_path to 'public' as $function$
begin
  if not is_autorizado() then return null; end if;
  update obras set cpfl_avisado_em = now(), cpfl_avisado_prazo = cpfl_prazo_em where id = p_obra;
  return json_build_object('ok', true);
end; $function$;
