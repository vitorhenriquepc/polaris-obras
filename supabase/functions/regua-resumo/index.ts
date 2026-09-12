import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });
    if ((body.token || '') !== C.cron_token) return json({ erro: 'nao autorizado' }, 403);

    if ((C.regua_resumo_ativa || '0') !== '1' && !body.forcar) return json({ ok: true, desligado: true });

    const { data: r } = await admin.rpc('regua_resumo_dia');
    const esperando = (r?.esperando || []) as any[];
    const saiHoje = (r?.sai_hoje || []) as any[];
    const venceAmanha = r?.vence_amanha || 0;

    // silencio quando nao ha nada a dizer: aviso que sempre chega vira ruido
    if (!esperando.length && !saiHoje.length) {
      return json({ ok: true, nada_a_avisar: true });
    }

    let msg = '📋 *Régua de hoje*\n';

    if (esperando.length) {
      msg += `\n*${esperando.length} esperando sua autorização:*\n`;
      msg += esperando.slice(0, 10).map((e: any) => {
        const tempo = e.dias_parada > 0
          ? ` _(parada há ${e.dias_parada} dia${e.dias_parada > 1 ? 's' : ''})_` : '';
        return `• ${e.cliente} — ${e.assunto}${tempo}`;
      }).join('\n');
      if (esperando.length > 10) msg += `\n_e mais ${esperando.length - 10}_`;
      msg += '\n';
    }

    if (saiHoje.length) {
      msg += `\n*${saiHoje.length} sai${saiHoje.length > 1 ? 'em' : ''} hoje às 17h, sem precisar de você:*\n`;
      msg += saiHoje.slice(0, 8).map((e: any) => `• ${e.cliente} — ${e.assunto}`).join('\n');
      if (saiHoje.length > 8) msg += `\n_e mais ${saiHoje.length - 8}_`;
      msg += '\n';
    }

    if (venceAmanha > 0) {
      msg += `\n⏰ ${venceAmanha} perde${venceAmanha > 1 ? 'm' : ''} a validade amanhã.\n`;
    }

    if (esperando.length) {
      msg += '\n_Abra o Pós-venda → Régua para ler e aprovar. O que não for aprovado não sai._';
    }

    if (body.simular) return json({ ok: true, simulado: true, mensagem: msg });

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    const { data: resp } = await admin.from('equipe').select('nome,telefone')
      .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
    if (!ZI || !ZT || !ZC || !resp?.telefone) return json({ erro: 'sem canal ou sem responsavel' }, 500);

    const env = await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
      body: JSON.stringify({ phone: resp.telefone, message: msg }),
    });
    const det = await env.json().catch(() => ({}));

    return json({ ok: env.ok, para: resp.nome, esperando: esperando.length,
                  sai_hoje: saiHoje.length, detalhe: det });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
