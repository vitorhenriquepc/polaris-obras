import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
function pickGroupId(o: any): string | null {
  for (const v of [o?.phone, o?.id, o?.groupId, o?.chatId]) {
    if (typeof v === 'string' && v && !v.startsWith('http')) return v;
  }
  return null;
}
function norm(g: string): string {
  g = g.trim();
  return /^\d+$/.test(g) ? g + '-group' : g;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (!tk || !body.token || body.token !== tk.valor) return json({ error: 'Não autorizado.' }, 403);

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZI || !ZT || !ZC) return json({ error: 'Z-API não configurada.' }, 500);
    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };

    // 02/10: modo SÓ LEITURA. Recebe um link de convite e diz que grupo é —
    // id, nome e tamanho — sem gravar nada em lugar nenhum e sem entrar no
    // grupo. Serve para conferir, antes de ligar, se o link é mesmo o grupo
    // certo (o Júnior Bassetto tem dois grupos com a Polaris) e se ele já está
    // cadastrado em alguma obra.
    if (body.convite) {
      const limpo = String(body.convite).split('?')[0].trim();
      const r = await fetch(`${base}/group-invitation-metadata?url=${encodeURIComponent(limpo)}`, { headers: zH });
      const meta = await r.json().catch(() => ({}));
      const gid = pickGroupId(meta);
      if (!r.ok || !gid) return json({ ok: false, resposta: JSON.stringify(meta).slice(0, 200) }, r.ok ? 200 : 502);
      const id = norm(gid);
      const { data: obras } = await admin.from('obras').select('id, contrato, cliente, trilha').eq('whatsapp_grupo_id', id);
      return json({ ok: true, grupo_id: id, nome: meta?.subject || meta?.name || null,
                    participantes: meta?.size || meta?.participants?.length || null,
                    ja_cadastrado_em: obras || [] });
    }

    if (body.so_status) {
      const st = await fetch(`${base}/status`, { headers: zH });
      const s = await st.json().catch(() => ({}));
      const { count } = await admin.from('obras').select('id', { count: 'exact', head: true }).like('whatsapp_grupo_id', 'http%');
      return json({ status: s, grupos_em_link: count });
    }

    // uma obra específica (usado pelo gatilho, logo após salvar)
    let alvo: any[] = [];
    if (body.obra_id) {
      const { data } = await admin.from('obras')
        .select('id, cliente, whatsapp_grupo_id').eq('id', body.obra_id).maybeSingle();
      if (data && String(data.whatsapp_grupo_id || '').startsWith('http')) alvo = [data];
    } else {
      const lote = Math.min(parseInt(body.lote || '5', 10), 8);
      const { data } = await admin.from('obras')
        .select('id, cliente, whatsapp_grupo_id').like('whatsapp_grupo_id', 'http%').limit(lote);
      alvo = data || [];
    }

    const res: any[] = [];
    for (const o of alvo) {
      const limpo = String(o.whatsapp_grupo_id).split('?')[0].trim();
      const r = await fetch(`${base}/group-invitation-metadata?url=${encodeURIComponent(limpo)}`, { headers: zH });
      const meta = await r.json().catch(() => ({}));
      const gid = pickGroupId(meta);
      if (gid) {
        await admin.from('obras').update({ whatsapp_grupo_id: norm(gid) }).eq('id', o.id);
        res.push({ cliente: o.cliente, ok: true, id: norm(gid) });
      } else {
        res.push({ cliente: o.cliente, ok: false, resposta: JSON.stringify(meta).slice(0, 120) });
      }
    }
    const { count: restam } = await admin.from('obras').select('id', { count: 'exact', head: true }).like('whatsapp_grupo_id', 'http%');
    return json({ processados: res.length, ok: res.filter((x) => x.ok).length, falhas: res.filter((x) => !x.ok), restam });
  } catch (err) {
    return json({ error: 'Erro: ' + (err as Error).message }, 500);
  }
});
