-- 22/09/2026 — A corretiva ganha onde dizer POR QUE está indo.
--
-- Pendência aberta hoje mesmo, ao corrigir a `enviar-os`: a manutenção passou
-- a ter ficha própria na OS, mas o instalador vai à **corretiva** sem saber o
-- que o cliente relatou. Ele chega e descobre no telhado.
--
-- ⚠️ `obras.observacoes` NÃO servia, e é por isso que este campo existe.
-- É campo livre e hoje carrega nota comercial — a obra 4599 (JOSE OLIONI) tem
-- *"Proposta: R$ 15.600,00"* lá dentro. Mandar `observacoes` para o grupo do
-- instalador vazaria preço de venda. Campo com um dono só não se reaproveita
-- para outra coisa.
--
-- `motivo_manutencao` nasce com destino declarado: vai na OS, para o grupo do
-- instalador. Quem escreve sabe quem lê — e a tela diz isso embaixo do campo.

alter table obras add column if not exists motivo_manutencao text;

comment on column obras.motivo_manutencao is
  'O que o cliente relatou, em uma linha — vai na OS para o grupo do instalador. '
  'Serve sobretudo à corretiva e ao diagnóstico. NÃO use observacoes para isto: '
  'aquele campo é livre e carrega nota comercial (preço de proposta).';

-- ── Conferência ─────────────────────────────────────────────────────────────
-- Coluna criada; `painel.html` grava por `f_motman` (só aparece em obra de
-- trilha manutencao) e a `enviar-os` imprime "📝 Relato: …" na ficha da
-- manutenção, e só quando preenchido.
--
-- Junto veio a correção do terceiro tipo: a tela grava `diagnostico` além de
-- `preventiva` e `corretiva`, e a `enviar-os` jogava ele no genérico "visita
-- técnica". Agora vira **"Avaliação técnica"**, que é como o `relatorio.html`
-- já titula esse laudo.
