import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Resumo do mês do cliente modelo (config.resumo_mensal_obras — hoje só o
// GILBERTO, 4436). Roda às 9h, segunda a sexta, pelo cron `resumo-mensal`:
//
//  1. a partir do dia `resumo_mensal_preparo_dia` (3), põe na régua o resumo do
//     mês que fechou, como `aguardando` (resumo_mensal_enfileirar), e avisa a
//     Lívia que tem resumo para aprovar;
//  2. envia no grupo o que já foi APROVADO e está programado para hoje ou antes
//     (dia 5, ou o próximo dia útil). Nada sai sem aprovação (regra 3.5).
//
// Fim de semana e feriado não envia. Fora das 9h não envia (só enfileira), a
// menos que venha {forcar_hora:true}. O disparo das 17h não pega este modelo
// (regua_modelos.envio_proprio). {simular:true} não grava, não envia, não avisa.

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

const NOMES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
  'setembro', 'outubro', 'novembro', 'dezembro'];

Deno.serve(async (req) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });
    if (!C.cron_token || (body.token || '') !== C.cron_token) return json({ erro: 'Não autorizado.' }, 403);

    const simular = body.simular === true;
    if ((C.resumo_mensal_ativo || '0') !== '1' && !simular) return json({ ok: true, desligado: true });

    const agora = new Date(Date.now() - 3 * 3600000);   // Brasília
    const hoje = agora.toISOString().slice(0, 10);
    const hora = agora.getUTCHours();
    const diaMes = agora.getUTCDate();

    const { data: util } = await admin.rpc('proximo_dia_util', { p: hoje });
    const diaUtil = util === hoje;

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };
    const { data: resp } = await admin.from('equipe').select('telefone')
      .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
    const avisaEquipe = async (msg: string) => {
      if (simular || !ZI || !ZT || !ZC || !resp?.telefone) return;
      await fetch(`${base}/send-text`, { method: 'POST', headers: zH,
        body: JSON.stringify({ phone: resp.telefone, message: msg }) });
    };
    const nome2 = (s: string) => String(s || '').split(' ').slice(0, 2).join(' ');
    const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;

    // ---------- 1. enfileirar o mês que fechou ----------
    let enfileirados: any[] = [];
    const preparo = parseInt(C.resumo_mensal_preparo_dia || '3', 10);
    if (diaMes >= preparo) {
      const { data: r, error } = await admin.rpc('resumo_mensal_enfileirar', { p_simular: simular });
      if (error) return json({ erro: 'enfileirar: ' + error.message }, 500);
      enfileirados = ((r?.itens || []) as any[]).filter((i) => !i.pulado);
      const mes = r?.mes ? NOMES[parseInt(String(r.mes).slice(5, 7), 10) - 1] : '';
      if (enfileirados.length) {
        await avisaEquipe(`☀️ *Resumo de ${mes} esperando revisão*\n\n`
          + enfileirados.map((i) => `• ${nome2(i.cliente)} — sai às 9h de ${ddmm(String(i.envio))} se aprovado`).join('\n')
          + `\n\n_Abra o Pós-venda → Régua para ler e aprovar. Nada sai sem sua confirmação._`);
      }
    }

    // ---------- 2. enviar o que foi aprovado ----------
    if (!diaUtil) return json({ ok: true, simular, enfileirados: enfileirados.length, enviados: 0, motivo: 'não é dia útil' });
    if (hora !== 9 && !body.forcar_hora) {
      return json({ ok: true, simular, enfileirados: enfileirados.length, enviados: 0, motivo: `envio só às 9h (agora ${hora}h)` });
    }

    const { data: fila, error: ef } = await admin.from('regua_contatos')
      .select('id, obra_id, texto_custom, status_aprovacao, data_programada, adiado_para, data_limite, obras(cliente, whatsapp_grupo_id, optout_em)')
      .eq('modelo', 'resumo_mensal').eq('status', 'pendente')
      .lte('data_programada', hoje).gte('data_limite', hoje);
    if (ef) return json({ erro: 'fila: ' + ef.message }, 500);

    const enviados: string[] = [];
    const esperando: string[] = [];
    const bloqueados: string[] = [];
    for (const c of (fila || []) as any[]) {
      const o = c.obras || {};
      if ((c.adiado_para || c.data_programada) > hoje) continue;
      if (c.status_aprovacao !== 'aprovada') { esperando.push(nome2(o.cliente)); continue; }
      if (!o.whatsapp_grupo_id || String(o.whatsapp_grupo_id).startsWith('http') || o.optout_em || !c.texto_custom) {
        bloqueados.push(nome2(o.cliente)); continue;
      }
      if (simular) { enviados.push(nome2(o.cliente)); continue; }
      if (!ZI || !ZT || !ZC) return json({ erro: 'Z-API não configurada.' }, 500);
      const r = await fetch(`${base}/send-text`, { method: 'POST', headers: zH,
        body: JSON.stringify({ phone: o.whatsapp_grupo_id, message: c.texto_custom }) });
      if (!r.ok) { bloqueados.push(`${nome2(o.cliente)} (Z-API ${r.status})`); continue; }
      await admin.rpc('regua_marcar_enviado', { p_id: c.id, p_texto: c.texto_custom });
      enviados.push(nome2(o.cliente));
    }

    if (enviados.length || esperando.length || bloqueados.length) {
      await avisaEquipe(
        (enviados.length ? `📬 *Resumo do mês enviado*\n${enviados.map((n) => `• ${n}`).join('\n')}\n` : '')
        + (esperando.length ? `\n⏳ *Não saiu — falta aprovar:*\n${esperando.map((n) => `• ${n}`).join('\n')}\n`
           + `_Aprovando, sai às 9h do próximo dia útil._\n` : '')
        + (bloqueados.length ? `\n⚠️ *Não saiu:*\n${bloqueados.map((n) => `• ${n}`).join('\n')}\n` : ''));
    }

    return json({ ok: true, simular, enfileirados: enfileirados.length, enviados, esperando, bloqueados });
  } catch (e) {
    return json({ erro: String((e as Error)?.message || e) }, 500);
  }
});
