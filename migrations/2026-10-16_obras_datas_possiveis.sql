-- APLICADA em 16/10 (aprovada pelo Vitor no chat: "pode aceitar as correções").
--
-- O caso que pediu: RINALDO DE CASTRO (4519), 13/10 10:25 — o card foi salvo com
-- a data de instalação 01/01/0001. O banco aceitou, a receita de R$ 42.000 foi
-- para o ano 1 no DRE (trg_dre_from_obra usa a data de instalação como
-- competência) e o grupo da CJP Solar recebeu "Obra remarcada — Nova data:
-- 01/01/0001". A data foi limpa em 14/10 (migração 2026-10-14_rinaldo...), mas
-- nada impedia de acontecer de novo.
--
-- Agora o banco recusa, em obras, data antes de 2020 ou a mais de 3 anos de hoje
-- nos campos que alguém digita. Só confere o campo que MUDOU: o card regrava
-- todos os campos a cada salvar, e um valor antigo não pode impedir de salvar
-- outra coisa. Apagar a data (null) continua permitido.
--
-- Conferido antes de gravar, em begin … rollback: ano 0001, ano 20261, insert com
-- 1900 e +4 anos recusam com a mensagem em português; data certa, apagar, insert
-- sem data, +2 anos e regravar igual (3 obras) passam. Nenhuma rotina do banco
-- grava data fora disso (plano_visita_abrir_obra usa a data prevista da visita,
-- dentro do contrato). O painel recusa a mesma faixa antes de mandar (painel.html,
-- dataImpossivel), e esta trava é a rede para qualquer outro caminho.
--
-- A tela mostra o erro como veio: "Erro: Data impossível em data de instalação:
-- 01/01/0001. Confira o ano."

create or replace function public.trava_datas_obra()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_min date := date '2020-01-01';
  v_max date := (current_date + interval '3 years')::date;
  r_novo jsonb := to_jsonb(new);
  r_velho jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  c record; v date;
begin
  for c in select * from (values
      ('data_fechamento',    'data de fechamento'),
      ('data_instalacao',    'data de instalação'),
      ('data_fim',           'término previsto'),
      ('data_conclusao',     'data de conclusão'),
      ('cpfl_solicitado_em', 'data da solicitação da vistoria'),
      ('cpfl_prazo_em',      'prazo da vistoria'),
      ('trava_em',           'data da trava')) x(campo, rotulo)
  loop
    -- só confere o que mudou: o card regrava todos os campos a cada salvar, e
    -- um valor antigo não pode impedir de salvar outra coisa
    if (r_novo->>c.campo) is not null and (r_novo->>c.campo) is distinct from (r_velho->>c.campo) then
      v := (r_novo->>c.campo)::date;
      if v < v_min or v > v_max then
        raise exception 'Data impossível em %: %. Confira o ano.', c.rotulo, to_char(v, 'DD/MM/YYYY')
          using errcode = 'P0001';
      end if;
    end if;
  end loop;
  return new;
end $function$;

revoke execute on function public.trava_datas_obra() from public;
revoke execute on function public.trava_datas_obra() from anon;

-- create or replace (Postgres 14+): o drop pelo MCP fica esperando confirmação
-- e expira calado (armadilha 32)
create or replace trigger trg_datas_obra
  before insert or update of data_fechamento, data_instalacao, data_fim, data_conclusao,
                             cpfl_solicitado_em, cpfl_prazo_em, trava_em
  on public.obras for each row execute function public.trava_datas_obra();
