-- Para quem a nota do plano e emitida.
--
-- A Tays pediu no CPF dela, mas o sistema e do acougue -- e no proximo
-- contrato pode ser o contrario. O documento da nota nao e sempre o mesmo do
-- cadastro do cliente, entao ele vive no CONTRATO, nao em `clientes`.
--
-- Um campo so guarda os dois: 11 digitos e CPF, 14 e CNPJ. Guardar o "tipo"
-- ao lado seria redundante e daria chance de divergir do numero.

alter table plano_contratos add column if not exists nota_documento text;
alter table plano_contratos add column if not exists nota_nome text;

alter table plano_contratos drop constraint if exists plano_contratos_nota_doc_ok;
alter table plano_contratos add constraint plano_contratos_nota_doc_ok
  check (
    nota_documento is null
    or length(regexp_replace(nota_documento,'\D','','g')) in (11, 14)
  );

comment on column plano_contratos.nota_documento is
  'CPF (11 digitos) ou CNPJ (14) para a nota deste contrato. O tipo se deduz '
  'do tamanho -- nao existe campo separado para nao divergir do numero.';
comment on column plano_contratos.nota_nome is
  'Nome ou razao social na nota, quando diferente do nome do cliente.';

-- Diz se o documento da nota e CPF ou CNPJ, para a tela nao ter de contar digito.
create or replace function public.plano_nota_tipo(p_documento text)
returns text
language sql immutable
as $function$
  select case length(regexp_replace(coalesce(p_documento,''),'\D','','g'))
           when 11 then 'cpf' when 14 then 'cnpj' else null end;
$function$;
