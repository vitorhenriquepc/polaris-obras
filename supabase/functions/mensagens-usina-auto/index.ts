import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

const MODELO: Record<string, string> = {
  wifi: 'usina_wifi',
  parada: 'usina_parada',
  queda: 'geracao_baixa',
  recorde: 'geracao_recorde',
  resumo_mensal: 'geracao_resumo',
};
const URGENTES = ['usina_wifi', 'usina_parada', 'geracao_baixa'];
// `resumo_mensal` e o resumo do cliente modelo (edge function resumo-mensal):
// conta como cortesia para o descanso entre mensagens
const CORTESIA = ['geracao_recorde', 'geracao_resumo', 'retorno_marco', 'resumo_mensal'];
// estados que pedem contato com o cliente sobre comunicacao.
// "recém-ligada" NAO entra: a usina acabou de ser energizada e pode nao ter reportado ainda.
const PEDE_WIFI = ['sem comunicação', 'alerta', 'nunca gerou', 'sem dado'];

Deno.serve(async (req) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });
    if ((body.token || '') !== C.cron_token) return json({ erro: 'nao autorizado' }, 403);

    const simular = body.simular === true;
    const rodada = body.rodada || 'problemas';

    const ligadoProblema = (C.msg_ia_ativa || '0') === '1';
    const ligadoRecorde = (C.recorde_ativo || '0') === '1';
    const ligadoQueda = (C.ger_alerta_ativo || '0') === '1';
    const ligadoMensal = (C.pilula_mensal_ativa || '0') === '1';

    if (rodada === 'mensal' && !ligadoMensal && !body.forcar) return json({ ok: true, desligado: true });
    if (rodada === 'problemas' && !ligadoProblema && !ligadoRecorde && !ligadoQueda && !body.forcar) {
      return json({ ok: true, desligado: true });
    }

    const intervalo = parseInt(C.msg_ia_intervalo_dias || '20', 10);
    const intervaloUrgente = parseInt(C.msg_ia_intervalo_urgente || '7', 10);
    const maxDia = parseInt(
      rodada === 'mensal' ? (C.pilula_max_por_rodada || '25') : (C.msg_ia_max_por_dia || '5'), 10);
    const minDiasParada = parseInt(C.msg_ia_min_dias_parada || '3', 10);

    // obras do cliente modelo recebem o resumo proprio (resumo-mensal, 9h do dia 5),
    // entao ficam fora do resumo mensal escrito pela IA — senao seriam dois resumos
    const modelo = new Set((C.resumo_mensal_obras || '').split(',').map((s) => s.trim()).filter(Boolean));

    const { data: usinas } = await admin.from('v_usinas_monitoradas').select('*');
    if (!usinas?.length) return json({ ok: true, usinas: 0 });

    const gerar: any[] = [];
    const pulados: any[] = [];

    for (const u of usinas as any[]) {
      if (gerar.length >= maxDia) break;
      if (!u.whatsapp_grupo_id || u.optout_em) continue;

      let tipo: string | null = null;
      let motivo: string | null = null;

      if (rodada === 'mensal') {
        if (modelo.has(u.obra_id)) {
          pulados.push({ cliente: u.cliente, motivo: 'cliente modelo: recebe o resumo proprio (resumo-mensal)' });
          continue;
        }
        tipo = 'resumo_mensal';
        motivo = 'resumo do mes fechado';
      } else {
        const { data: est } = await admin.rpc('usina_estado', { p_usina: u.usina_id });
        const e = Array.isArray(est) ? est[0] : est;

        // usina recem-ligada fica so no acompanhamento, sem mensagem
        if (e?.estado === 'recém-ligada') {
          pulados.push({ cliente: u.cliente, motivo: 'recem-ligada, em carencia' });
          continue;
        }

        if (ligadoProblema || body.forcar) {
          if (e) {
            if (e.estado === 'parada' && (e.dias_sem_gerar || 0) >= minDiasParada) { tipo = 'parada'; motivo = e.motivo; }
            else if (PEDE_WIFI.includes(e.estado)) { tipo = 'wifi'; motivo = e.motivo; }
          }
        }
        if (!tipo && (ligadoQueda || body.forcar)) {
          const { data: qd } = await admin.rpc('queda_geracao', { p_usina: u.usina_id });
          const q = Array.isArray(qd) ? qd[0] : qd;
          if (q?.caiu) { tipo = 'queda'; motivo = q.motivo; }
        }
        if (!tipo && (ligadoRecorde || body.forcar)) {
          const { data: rec } = await admin.rpc('recorde_do_dia', { p_usina: u.usina_id });
          const r = Array.isArray(rec) ? rec[0] : rec;
          if (r?.elegivel) {
            tipo = 'recorde';
            motivo = `melhor dia dela: ${r.kwh_recorde} kWh, ${r.ganho_pct}% acima do anterior`;
          }
        }
      }
      if (!tipo) continue;

      const modeloReg = MODELO[tipo];
      const urgente = URGENTES.includes(modeloReg);
      const janela = urgente ? intervaloUrgente : intervalo;
      const olhar = urgente ? URGENTES : [...URGENTES, ...CORTESIA];
      const desde = new Date(Date.now() - janela * 86400000).toISOString().slice(0, 10);

      const { data: recente } = await admin.from('regua_contatos')
        .select('id, modelo').eq('obra_id', u.obra_id)
        .in('modelo', olhar).gte('data_programada', desde).limit(1);
      if (recente?.length) {
        pulados.push({ cliente: u.cliente, tipo,
                       motivo: `ja teve ${recente[0].modelo} nos ultimos ${janela} dias` });
        continue;
      }

      gerar.push({ usina_id: u.usina_id, obra_id: u.obra_id, cliente: u.cliente,
                   tipo, modelo: modeloReg, motivo, urgente });
    }

    if (simular) return json({ ok: true, rodada, geraria: gerar.length, gerar, pulados: pulados.slice(0, 8) });
    if (!gerar.length) return json({ ok: true, rodada, geradas: 0, pulados: pulados.length });

    let ok = 0; const erros: any[] = []; const recusados: any[] = [];
    for (const g of gerar) {
      try {
        const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/mensagem-gerar`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: C.cron_token, usina_id: g.usina_id, tipo: g.tipo,
                                 so_gerar: g.tipo === 'queda' ? false : true }),
        });
        const d = await r.json();

        if (g.tipo === 'queda') {
          if (d?.ok) ok++; else recusados.push({ cliente: g.cliente, motivo: d?.erro || 'recusado' });
          await new Promise((s) => setTimeout(s, 400));
          continue;
        }

        if (!d?.texto) { recusados.push({ cliente: g.cliente, motivo: d?.erro || 'sem texto' }); continue; }
        const hoje = new Date().toISOString().slice(0, 10);
        const limite = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
        const { error } = await admin.from('regua_contatos').insert({
          obra_id: g.obra_id, usina_id: g.usina_id, modelo: g.modelo,
          data_programada: hoje, data_limite: limite,
          status: 'pendente', status_aprovacao: 'aguardando',
          texto_custom: d.texto,
          bloqueio_motivo: (d.avisos && d.avisos.length) ? d.avisos.join(' · ') : g.motivo,
        });
        if (error) { erros.push({ cliente: g.cliente, erro: error.message }); continue; }
        ok++;
      } catch (err) {
        erros.push({ cliente: g.cliente, erro: String(err).slice(0, 80) });
      }
      await new Promise((s) => setTimeout(s, 400));
    }

    if (ok > 0 && (C.msg_ia_avisa || '1') === '1') {
      const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
      const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
      const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
      const { data: resp } = await admin.from('equipe').select('telefone')
        .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
      if (ZI && ZT && ZC && resp?.telefone) {
        const rotulo: Record<string, string> = {
          wifi: 'sem comunicar', parada: 'parada',
          queda: 'gerando pouco', recorde: 'recorde!', resumo_mensal: 'resumo do mes',
        };
        const titulo = rodada === 'mensal'
          ? `☀️ *${ok} resumo${ok > 1 ? 's' : ''} do mês esperando revisão*`
          : `✍️ *${ok} mensagem${ok > 1 ? 's' : ''} esperando sua revisão*`;
        const msg = `${titulo}\n\n`
          + gerar.slice(0, 8).map((g: any) =>
              `• ${String(g.cliente).split(' ').slice(0, 2).join(' ')} — ${rotulo[g.tipo] || g.tipo}`).join('\n')
          + `\n\n_Abra o Pós-venda → Régua para ler e aprovar. Nada sai sem sua confirmação._`;
        await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
          body: JSON.stringify({ phone: resp.telefone, message: msg }),
        });
      }
    }

    return json({ ok: true, rodada, geradas: ok, pulados: pulados.length,
                  recusadas: recusados.length, erros: erros.slice(0, 5),
                  detalhe_recusa: recusados.slice(0, 5) });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
