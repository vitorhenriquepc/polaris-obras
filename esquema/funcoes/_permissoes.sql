-- Quem pode executar cada função desta pasta, como está no banco em 12/09/2026.
-- O pg_get_functiondef não traz isso, então fica separado.
--
-- No Supabase o padrão do Postgres (execute para PUBLIC) alcança o anon —
-- o papel de quem não fez login, cuja chave está no código das páginas.

-- ---------------------------------------------------------------------
-- Só a equipe logada
-- ---------------------------------------------------------------------
revoke all on function public.buscar_duplicata(p_data date, p_valor numeric, p_conta text) from public, anon;
revoke all on function public.calibrar_fatores(p_aplicar boolean, p_min_meses integer) from public, anon;
revoke all on function public.calibrar_tarifa(p_valor numeric, p_observacao text) from public, anon;
revoke all on function public.classificar_lote(p_itens jsonb) from public, anon;
revoke all on function public.classificar_movimento(p_memo text, p_valor numeric) from public, anon;
revoke all on function public.clientes_esperando(p_minutos integer) from public, anon;
revoke all on function public.decidir_mensagem(p_id uuid, p_acao text, p_texto text) from public, anon;
revoke all on function public.descartar_movimento(p_id bigint, p_motivo text) from public, anon;
revoke all on function public.desfazer_lancamento(p_movimento bigint) from public, anon;
revoke all on function public.dias_anormais(p_dias integer) from public, anon;
revoke all on function public.get_aprovacoes(p_situacao text) from public, anon;
revoke all on function public.get_automacoes() from public, anon;
revoke all on function public.get_cliente_ficha(p_cliente uuid) from public, anon;
revoke all on function public.get_clientes_acervo() from public, anon;
revoke all on function public.get_contas_extrato() from public, anon;
revoke all on function public.get_extrato_pendentes(p_conta uuid) from public, anon;
revoke all on function public.get_posvenda_mensagens(p_dias integer) from public, anon;
revoke all on function public.get_posvenda_usinas() from public, anon;
revoke all on function public.get_regua_aprovacoes() from public, anon;
revoke all on function public.get_relatorios_painel() from public, anon;
revoke all on function public.get_usina_causa(p_usina uuid) from public, anon;
revoke all on function public.get_usina_detalhe(p_usina uuid, p_dias integer) from public, anon;
revoke all on function public.importar_extrato(p_itens jsonb, p_conta uuid) from public, anon;
revoke all on function public.lancar_avulso(p_movimento bigint, p_cliente text, p_tipo text, p_obs text) from public, anon;
revoke all on function public.lancar_movimentos(p_itens jsonb) from public, anon;
revoke all on function public.ligar_automacao(p_chave text, p_ligar boolean) from public, anon;
revoke all on function public.marcar_todas_lidas(p_obra uuid) from public, anon;
revoke all on function public.marcos_novos() from public, anon;
revoke all on function public.obras_aguardando_ligacao() from public, anon;
revoke all on function public.painel_avulsos(p_ini date, p_fim date) from public, anon;
revoke all on function public.parcelas_abertas(p_obra uuid) from public, anon;
revoke all on function public.pista_de_causa(p_obra uuid, p_dias integer) from public, anon;
revoke all on function public.previsao_estimada(p_usina uuid, p_sobrescrever boolean) from public, anon;
revoke all on function public.queda_geracao(p_usina uuid) from public, anon;
revoke all on function public.receber_do_extrato(p_movimento bigint, p_obra uuid, p_parcela bigint) from public, anon;
revoke all on function public.recorde_do_dia(p_usina uuid) from public, anon;
revoke all on function public.registrar_google_enviado(p_nps bigint) from public, anon;
revoke all on function public.regua_decidir(p_id bigint, p_acao text, p_texto text) from public, anon;
revoke all on function public.regua_texto_item(p_item bigint) from public, anon;
revoke all on function public.salvar_causa(p_usina uuid, p_causa text, p_nota text, p_avisado boolean) from public, anon;
revoke all on function public.salvar_fator(p_usina uuid, p_fator numeric, p_nota text) from public, anon;
revoke all on function public.salvar_previsao(p_usina uuid, p_mes integer, p_kwh numeric) from public, anon;
revoke all on function public.salvar_relatorio_arquivo(p_obra uuid, p_titulo text, p_path text, p_url text, p_tamanho bigint, p_data date) from public, anon;
revoke all on function public.salvar_relatorio_link(p_obra uuid, p_titulo text, p_url text, p_origem text, p_data date) from public, anon;
revoke all on function public.tarifa_status() from public, anon;
revoke all on function public.usina_meses(p_usina uuid) from public, anon;
revoke all on function public.usina_retorno(p_usina uuid) from public, anon;

grant execute on function public.buscar_duplicata(p_data date, p_valor numeric, p_conta text) to authenticated;
grant execute on function public.calibrar_fatores(p_aplicar boolean, p_min_meses integer) to authenticated;
grant execute on function public.calibrar_tarifa(p_valor numeric, p_observacao text) to authenticated;
grant execute on function public.classificar_lote(p_itens jsonb) to authenticated;
grant execute on function public.classificar_movimento(p_memo text, p_valor numeric) to authenticated;
grant execute on function public.clientes_esperando(p_minutos integer) to authenticated;
grant execute on function public.decidir_mensagem(p_id uuid, p_acao text, p_texto text) to authenticated;
grant execute on function public.descartar_movimento(p_id bigint, p_motivo text) to authenticated;
grant execute on function public.desfazer_lancamento(p_movimento bigint) to authenticated;
grant execute on function public.dias_anormais(p_dias integer) to authenticated;
grant execute on function public.get_aprovacoes(p_situacao text) to authenticated;
grant execute on function public.get_automacoes() to authenticated;
grant execute on function public.get_cliente_ficha(p_cliente uuid) to authenticated;
grant execute on function public.get_clientes_acervo() to authenticated;
grant execute on function public.get_contas_extrato() to authenticated;
grant execute on function public.get_extrato_pendentes(p_conta uuid) to authenticated;
grant execute on function public.get_posvenda_mensagens(p_dias integer) to authenticated;
grant execute on function public.get_posvenda_usinas() to authenticated;
grant execute on function public.get_regua_aprovacoes() to authenticated;
grant execute on function public.get_relatorios_painel() to authenticated;
grant execute on function public.get_usina_causa(p_usina uuid) to authenticated;
grant execute on function public.get_usina_detalhe(p_usina uuid, p_dias integer) to authenticated;
grant execute on function public.importar_extrato(p_itens jsonb, p_conta uuid) to authenticated;
grant execute on function public.lancar_avulso(p_movimento bigint, p_cliente text, p_tipo text, p_obs text) to authenticated;
grant execute on function public.lancar_movimentos(p_itens jsonb) to authenticated;
grant execute on function public.ligar_automacao(p_chave text, p_ligar boolean) to authenticated;
grant execute on function public.marcar_todas_lidas(p_obra uuid) to authenticated;
grant execute on function public.marcos_novos() to authenticated;
grant execute on function public.obras_aguardando_ligacao() to authenticated;
grant execute on function public.painel_avulsos(p_ini date, p_fim date) to authenticated;
grant execute on function public.parcelas_abertas(p_obra uuid) to authenticated;
grant execute on function public.pista_de_causa(p_obra uuid, p_dias integer) to authenticated;
grant execute on function public.previsao_estimada(p_usina uuid, p_sobrescrever boolean) to authenticated;
grant execute on function public.queda_geracao(p_usina uuid) to authenticated;
grant execute on function public.receber_do_extrato(p_movimento bigint, p_obra uuid, p_parcela bigint) to authenticated;
grant execute on function public.recorde_do_dia(p_usina uuid) to authenticated;
grant execute on function public.registrar_google_enviado(p_nps bigint) to authenticated;
grant execute on function public.regua_decidir(p_id bigint, p_acao text, p_texto text) to authenticated;
grant execute on function public.regua_texto_item(p_item bigint) to authenticated;
grant execute on function public.salvar_causa(p_usina uuid, p_causa text, p_nota text, p_avisado boolean) to authenticated;
grant execute on function public.salvar_fator(p_usina uuid, p_fator numeric, p_nota text) to authenticated;
grant execute on function public.salvar_previsao(p_usina uuid, p_mes integer, p_kwh numeric) to authenticated;
grant execute on function public.salvar_relatorio_arquivo(p_obra uuid, p_titulo text, p_path text, p_url text, p_tamanho bigint, p_data date) to authenticated;
grant execute on function public.salvar_relatorio_link(p_obra uuid, p_titulo text, p_url text, p_origem text, p_data date) to authenticated;
grant execute on function public.tarifa_status() to authenticated;
grant execute on function public.usina_meses(p_usina uuid) to authenticated;
grant execute on function public.usina_retorno(p_usina uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Só o backend (cron e service_role); nem a equipe logada chama pela API
-- ---------------------------------------------------------------------
revoke all on function public.conferir_saude_base() from public, anon, authenticated;
revoke all on function public.get_marco_svc(p_usina uuid, p_marco integer) from public, anon, authenticated;
revoke all on function public.get_usina_detalhe_svc(p_usina uuid, p_dias integer) from public, anon, authenticated;
revoke all on function public.trg_marcar_aceite_pedido() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- NO PADRÃO DO POSTGRES — execute liberado para PUBLIC, o que inclui o anon
-- ---------------------------------------------------------------------
-- Sem statement aqui: é o estado que o banco tem hoje, e este arquivo
-- registra o que existe, não o que deveria existir.
--
-- Para a maioria não custa nada: auto_lida, espelha_preco_na_ficha,
-- mascara_credencial, trg_valida_lancamento e valida_obra_usina só rodam
-- por trigger; chave_nome, pontua_nome, tokens_iguais, mensagem_sem_acao e
-- fracao_polaris são cálculo puro; zz_lista e zz_brindes conferem permissão
-- por dentro.
--
-- Três NÃO conferem nada e são SECURITY DEFINER, ou seja, passam por cima
-- da RLS. Ver o aviso em ../../migrations/COBERTURA.md.
--
--   revoke all on function public._t_pend(p_conta uuid) from public, anon;
--   revoke all on function public.zz_det(p_usina uuid) from public, anon;
--   revoke all on function public.manutencao_usinas() from public, anon;
--
-- Deixado comentado de propósito: mexer em permissão de produção é decisão
-- do Vitor, não efeito colateral de um export.
