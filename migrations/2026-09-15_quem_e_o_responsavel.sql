-- Trocar a pessoa do pos-venda: o que segue o papel e o que nao segue.
--
-- Decisao do Vitor em 15/09: o aviso de vinculo de usina fica sempre com o
-- RESPONSAVEL PELO POS-VENDA, e trocar a pessoa deve ser so trocar o numero.
-- Fui conferir se isso e verdade hoje. Metade e.
--
-- SEGUE O PAPEL (trocar a pessoa em `equipe` resolve):
--   solarview-vincular  -> equipe.resp_posvenda   <- o vinculo, que era a pergunta
--   conferencia-diaria  -> equipe.resp_posvenda
--   autoleitura-aviso   -> equipe.resp_posvenda
--   plano-vencimento    -> equipe.resp_alertas
--
-- NAO SEGUE: tres chaves da `config` guardam NUMERO, nao papel. Trocar a
-- pessoa em `equipe` nao muda nenhuma delas:
--   alerta_destinos          -> lido por `alerta-prazos` (hoje: so o Vitor)
--   alerta_credito_destinos  -> Livia + Vitor
--   grupo_fixos              -> Livia + Vitor
-- Conferido cruzando cada numero contra `equipe.telefone`: batem com a Livia
-- (...2573) e com o Vitor (...2812). Nenhuma funcao do banco e nenhuma tela le
-- essas chaves -- so edge function.
--
-- Nao mexi nelas: mudar quem recebe alerta e decisao do Vitor, nao varredura.
-- Fica como pendencia no CLAUDE.md.
--
-- Nenhuma funcao do banco tem numero de telefone chumbado (conferido com
-- regex sobre `pg_proc.prosrc`), e nenhuma cita a Livia pelo nome.

-- O bug que apareceu na auditoria
-- -------------------------------
-- `get_responsavel_posvenda()` lia `e.responsavel_posvenda` -- coluna que NAO
-- EXISTE; a coluna e `resp_posvenda`. Quebrava com 42703 para qualquer usuario
-- autorizado. Reproduzido com `set local role authenticated`.
--
-- Passou em branco porque ninguem chama: nem tela, nem outra funcao do banco,
-- nem edge function (as edge functions consultam `equipe` direto). Por isso
-- ampliar o retorno para os DOIS papeis e seguro -- nao ha chamador para
-- quebrar, e e o formato que uma tela de "quem recebe o que" precisa.
--
-- `definir_responsavel(equipe, funcao)` -- a funcao que de fato troca a pessoa,
-- com `is_admin()` -- ja existia e funciona. Tambem nao tem chamador: hoje a
-- troca so acontece pelo banco, na mao. Anotado como pendencia.
create or replace function public.get_responsavel_posvenda()
returns json language plpgsql stable security definer set search_path to 'public' as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'posvenda', (select json_build_object('id',e.id,'nome',e.nome,'telefone',e.telefone)
                   from equipe e where e.resp_posvenda and e.ativo limit 1),
    'alertas',  (select json_build_object('id',e.id,'nome',e.nome,'telefone',e.telefone)
                   from equipe e where e.resp_alertas and e.ativo limit 1)
  ) into v;
  return v;
end; $function$;

-- Armadilha 10: dois revokes. Conferido pela ACL depois, nao pelo comando
-- ter passado: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke execute on function public.get_responsavel_posvenda() from public;
revoke execute on function public.get_responsavel_posvenda() from anon;
grant  execute on function public.get_responsavel_posvenda() to authenticated;
