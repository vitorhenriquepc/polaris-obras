-- Preparo para ligar "Notificar as enviadas por mim também" na Z-API (instância
-- POS-VENDA, o número da Isabela) — Vitor, 15/10.
--
-- Com a opção ligada, tudo o que sai pelo número da Isabela entra no
-- webhook-whatsapp-v2 como fromMe e vira linha em mensagens_recebidas com
-- da_equipe = true: 'automatica' quando o texto traz a assinatura
-- "Equipe Polaris Energia Solar", 'resposta_equipe' (e fecha a pendência do
-- cliente) quando não traz — que é o caso de quem DIGITA no WhatsApp da Isabela.
--
-- Três lugares iam ler essas linhas novas do jeito errado:
--
-- 1) O aviso de fim de semana da Isabela (atendimento_fds_texto) é o único texto
--    automático sem a assinatura. Sem ela, o próprio aviso contaria como "a
--    equipe respondeu" e calaria a escada na segunda-feira. Ganha a assinatura
--    padrão no fim; o resto do texto é o aprovado pelo Vitor em 15/10.
-- 2) pista_de_causa(obra, dias) procura "wi-fi", "internet", "desligado"... nas
--    mensagens da obra, inclusive da equipe. O nosso próprio aviso usina_wifi
--    ("confira o wi-fi") viraria prova de que a causa é wi-fi — o sistema
--    confirmando o próprio palpite (família da armadilha 19). Ignora 'automatica'.
-- 3) get_marco_svc e get_queda_svc mandam para a IA as últimas mensagens da
--    equipe como contexto. Ignoram 'automatica' para a IA não ler os modelos da
--    régua como se fossem conversa.
--
-- Recorte por marcador (cada um conferido: aparece uma vez só).
do $do$
declare
  r record;
  d text;
  mk text;
  novo text;
begin
  for r in select * from (values
      ('public.pista_de_causa(uuid,integer)',
       'and coalesce(m.transcricao, m.texto) is not null',
       'and coalesce(m.transcricao, m.texto) is not null
      and coalesce(m.contexto, '''') <> ''automatica''  -- não ler os próprios avisos como pista (15/10)'),
      ('public.get_marco_svc(uuid,integer)',
       'where mr.obra_id=o.id and mr.da_equipe',
       'where mr.obra_id=o.id and mr.da_equipe and coalesce(mr.contexto, '''') <> ''automatica'''),
      ('public.get_queda_svc(uuid)',
       'where mr.obra_id=o.id and mr.da_equipe',
       'where mr.obra_id=o.id and mr.da_equipe and coalesce(mr.contexto, '''') <> ''automatica''')
    ) as t(fn, marcador, troca)
  loop
    d := pg_get_functiondef(r.fn::regprocedure);
    if (length(d) - length(replace(d, r.marcador, ''))) / length(r.marcador) <> 1 then
      raise exception 'marcador não está uma vez só em %', r.fn;
    end if;
    execute replace(d, r.marcador, r.troca);
  end loop;

  update config
     set valor = valor || E'\n\n*Equipe Polaris Energia Solar* ☀️'
   where chave = 'atendimento_fds_texto'
     and valor not ilike '%equipe polaris energia solar%';
end $do$;
