import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// Extrai um ID de grupo válido de uma resposta da Z-API (nunca um link http)
function pickGroupId(obj: any): string | null {
  const cands = [obj?.phone, obj?.id, obj?.groupId, obj?.chatId];
  for (const v of cands) {
    if (typeof v === 'string' && v && !v.startsWith('http')) return v;
  }
  return null;
}
function normalizeGid(gid: string): string {
  gid = gid.trim();
  if (/^\d+$/.test(gid)) return gid + '-group';
  return gid;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const ZAPI_INSTANCE = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZAPI_TOKEN = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZAPI_CLIENT_TOKEN = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZAPI_INSTANCE || !ZAPI_TOKEN || !ZAPI_CLIENT_TOKEN) {
      return json({ error: 'Secrets da Z-API faltando no Supabase.' }, 500);
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: autorizado } = await userClient.rpc('is_autorizado');
    if (!autorizado) return json({ error: 'Acesso não autorizado.' }, 403);

    const { grupo_id, message } = await req.json();
    if (!grupo_id || !message) return json({ error: 'grupo_id e message são obrigatórios.' }, 400);

    const base = `https://api.z-api.io/instances/${ZAPI_INSTANCE}/token/${ZAPI_TOKEN}`;
    const zHeaders = { 'Content-Type': 'application/json', 'Client-Token': ZAPI_CLIENT_TOKEN };
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    let gid = String(grupo_id).trim();

    // Autocorreção: se ficou salvo o LINK de convite, resolve o ID real e conserta o banco
    if (gid.startsWith('http')) {
      const cleanLink = gid.split('?')[0];
      const rMeta = await fetch(`${base}/group-invitation-metadata?url=${encodeURIComponent(cleanLink)}`, { headers: zHeaders });
      const meta = await rMeta.json().catch(() => ({}));
      const resolved = pickGroupId(meta);
      if (!resolved) {
        return json({ error: 'O ID salvo é um link de convite e não consegui resolver o ID real do grupo. Recrie o grupo ou cole o ID no formulário da obra.', detalhe: meta }, 502);
      }
      const novoGid = normalizeGid(resolved);
      await admin.from('obras').update({ whatsapp_grupo_id: novoGid }).eq('whatsapp_grupo_id', grupo_id);
      gid = novoGid;
    }

    gid = normalizeGid(gid);

    // A mesma mensagem não sai duas vezes para o mesmo grupo em 24 h. JULIANO
    // (4924), 29/10: o aviso da vistoria saiu às 11:02 ao salvar o card e de novo
    // às 11:06 pelo 📣. A reserva é atômica no banco (envio_grupo_reservar): dois
    // cliques, duas abas ou duas pessoas ao mesmo tempo não passam os dois. Envio
    // que a Z-API recusou não segura o próximo. Sem conseguir conferir, não manda.
    // A recusa volta 200 com `error`, que é o que toda tela já mostra ao usuário.
    const { data: res, error: eRes } = await admin.rpc('envio_grupo_reservar', { p_grupo: gid, p_texto: String(message) });
    if (eRes || !res || res.erro || (!res.id && !res.ja_enviado)) {
      return json({ error: 'Não consegui conferir se esta mensagem já tinha ido para o grupo, então não mandei. Tente de novo em instantes.' }, 503);
    }
    if (res.ja_enviado) {
      return json({
        ok: false, repetida: true, ja_enviado: res.ja_enviado,
        error: res.enviando
          ? 'Esta mesma mensagem está saindo para o grupo agora. Não mandei de novo.'
          : `Esta mesma mensagem já foi para o grupo em ${res.quando}. Não mandei de novo.`,
      });
    }

    let r: Response;
    try {
      r = await fetch(`${base}/send-text`, {
        method: 'POST', headers: zHeaders,
        body: JSON.stringify({ phone: gid, message }),
      });
    } catch (e) {
      await admin.rpc('envio_grupo_concluir', { p_id: res.id, p_ok: false });
      return json({ error: 'Z-API (enviar): ' + (e as Error).message }, 502);
    }
    const data = await r.json().catch(() => ({}));
    await admin.rpc('envio_grupo_concluir', { p_id: res.id, p_ok: r.ok });
    if (!r.ok) return json({ error: 'Z-API (enviar): ' + (data?.error || data?.message || r.status) }, 502);

    return json({ ok: true, grupo: gid, resultado: data });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
