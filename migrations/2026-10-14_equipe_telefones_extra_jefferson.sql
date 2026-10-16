-- Quem é da equipe pode escrever nos grupos de mais de um número (Vitor, 14/10).
--
-- O Jefferson usa dois: 18 99808-1313 (o do cadastro) e 18 99186-9456. As
-- mensagens do segundo entravam em mensagens_recebidas como se fossem do
-- CLIENTE: não fechavam a pendência de quem ele respondeu (tratar_por_resposta)
-- e ainda podiam virar "cliente esperando resposta" — a dele mesmo.
--
-- equipe.telefone continua sendo o número para onde os avisos vão; o extra só
-- serve para reconhecer quem escreveu. equipe_por_fone() é o único lugar do
-- banco que identifica a equipe pelo telefone (procurado em 14/10).

alter table equipe add column if not exists telefones_extra text[];

comment on column equipe.telefones_extra is
  'Outros números da pessoa, só para reconhecer as mensagens dela nos grupos. Os avisos continuam indo para equipe.telefone.';

create or replace function public.equipe_por_fone(p_fone text)
 returns json
 language sql
 security definer
 set search_path to 'public'
as $function$
  select json_build_object('id', e.id, 'nome', e.nome, 'papel', e.papel)
  from equipe e
  where e.ativo
    and length(public.fone_norm(p_fone)) >= 10
    and (public.fone_norm(e.telefone) = public.fone_norm(p_fone)
         or exists (select 1 from unnest(coalesce(e.telefones_extra, '{}'::text[])) x
                    where public.fone_norm(x) = public.fone_norm(p_fone)))
  limit 1;
$function$;

do $x$
declare
  v_jef uuid;
  v_nome text;
  r record;
  n_msg int := 0;
  n_trat int := 0;
  k int;
begin
  select id, nome into v_jef, v_nome from equipe where nome ilike 'Jefferson%' and ativo;
  if v_jef is null then raise exception 'Jefferson não encontrado na equipe'; end if;

  update equipe set telefones_extra = array['18991869456'] where id = v_jef;

  -- as mensagens que ele mandou do segundo número e ficaram como "cliente".
  -- O texto não muda (regra 3.6); muda só quem a gente diz que escreveu.
  for r in
    update mensagens_recebidas m
       set da_equipe = true, remetente_nome = v_nome, contexto = 'resposta_equipe',
           metodo = 'equipe', lida_em = coalesce(m.lida_em, m.recebida_em),
           nps_checada_em = coalesce(m.nps_checada_em, m.recebida_em)
     where public.fone_norm(m.remetente_fone) = public.fone_norm('18991869456')
       and not coalesce(m.da_equipe, false)
    returning m.obra_id, m.recebida_em
  loop
    n_msg := n_msg + 1;
    -- e o que o cliente tinha escrito antes passa a contar como respondido por ele
    select public.tratar_por_resposta(r.obra_id, v_nome, r.recebida_em) into k;
    n_trat := n_trat + coalesce(k, 0);
  end loop;

  raise notice 'Jefferson: % mensagens corrigidas, % do cliente marcadas como respondidas', n_msg, n_trat;
end $x$;
