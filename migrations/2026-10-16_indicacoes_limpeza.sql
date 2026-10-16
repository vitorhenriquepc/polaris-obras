-- APLICADA em 16/10 (dados, não esquema), com o OK do Vitor no chat:
-- "pode aceitar as correções e as limpezas que você solicitou aqui".
--
-- Das 20 indicações que a IA detectou nos grupos desde agosto, 17 não eram
-- indicação (ver CLAUDE.md §4, "Indicações"). Simulada antes com a função final,
-- em begin … rollback, e o resultado real bateu com a simulação:
--
--   17 viram "não era indicação" (status anterior guardado em motivo_perda)
--   12 mensagens voltam para `geral`
--    9 exemplos novos em classificacoes_exemplo (a IA do webhook aprende)
--    0 erros
--
-- O funil fica com 3 de verdade: a irmã do 4618 (#12, nova, sem telefone,
-- vendedor Vitor), o filho do 4791 (#6) e o amigo do 4425 (#11), contatadas.
-- Na régua, 4324 e 4620 voltam a poder receber o d90_indica2 (04/11 e 10/11);
-- 4425, 4618 e 4791 seguem "cliente já indicou", que é verdade.
--
-- A ordem importa: das cópias de um mesmo falso alarme (13/14/15, 19/20), só a
-- última reclassifica o recado e vira exemplo — a função devolve `copia_de`
-- enquanto existir outra cópia viva com o mesmo texto. As do grupo de baixo são
-- cópias de indicações que CONTINUAM valendo (6 e 11): descartam sem
-- reclassificar, para o recado continuar contando como indicação.
--
-- indicacao_descartar confere is_autorizado(): rodou com as claims da conta do
-- Vitor (admin), dentro de uma transação só, e aborta tudo se qualquer uma der erro.

begin;
select set_config('request.jwt.claims', json_build_object(
  'email', (select email from usuarios_autorizados where nivel = 'admin' and email ilike 'vitor%' limit 1),
  'role', 'authenticated')::text, true);

do $x$
declare a record; r json; erros text := '';
begin
  for a in select * from (values
    -- falsos alarmes: reclassifica o recado e ensina a IA
    (13, 'ia mandar a conta de luz para a nora — não é indicação', true),
    (14, 'ia mandar a conta de luz para a nora — não é indicação', true),
    (15, 'ia mandar a conta de luz para a nora — não é indicação', true),
    (22, 'ia mandar o vídeo do Wi-Fi para o filho — não é indicação', true),
    (23, 'contatos da atendente da CPFL, não de interessado', true),
    (19, 'vontade de indicar, sem nome nem telefone de ninguém', true),
    (20, 'vontade de indicar, sem nome nem telefone de ninguém', true),
    (21, 'vontade de indicar, sem nome nem telefone de ninguém', true),
    (1,  'contato do eletricista, não de interessado', true),
    (2,  'aviso de prestador no telhado — não é indicação', true),
    (3,  'aviso de prestador no telhado — não é indicação', true),
    (4,  'aviso de prestador no telhado — não é indicação', true),
    -- cópias de indicações que continuam valendo: não reclassifica
    (5,  'cópia da indicação do filho (a 6 continua)', false),
    (7,  'cópia: o amigo indicado é a indicação 11', false),
    (8,  'cópia: o amigo indicado é a indicação 11', false),
    (9,  'cópia: o amigo indicado é a indicação 11', false),
    (10, 'cópia: o amigo indicado é a indicação 11', false)
  ) v(id, motivo, recl) loop
    r := public.indicacao_descartar(a.id, a.motivo, a.recl, false);
    if r->>'erro' is not null then erros := erros || a.id || ': ' || (r->>'erro') || ' | '; end if;
  end loop;
  if erros <> '' then raise exception 'limpeza abortada: %', erros; end if;
end $x$;
commit;
