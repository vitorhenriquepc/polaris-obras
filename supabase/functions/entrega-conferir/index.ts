import { createClient } from '@supabase/supabase-js';

// Mensagem que a Z-API aceitou e não chegou ao grupo do cliente (29/10).
//
// JOSÉ VICENTE (4875): o painel mandou ao grupo dele a mensagem da etapa e o
// agendamento de 17/11, o notificar-grupo respondeu 200 nas duas e nenhuma
// chegou -- a Isabela não estava no grupo. Tudo o que sai pelo número dela volta
// para o webhook e é gravado como 'Sistema/Polaris' segundos depois; o que não
// volta em 10 minutos não chegou. Quem confere é o banco (entrega_conferir);
// aqui só se manda o aviso à pós-venda (resp_posvenda) e, depois que a Z-API
// aceita, marca avisado (entrega_avisada). Se a Z-API recusar, nada é marcado e
// a próxima rodada tenta de novo.
//
// Cron `entrega-conferir`, a cada 10 min das 8h às 20h50. verify_jwt false +
// cron_token no corpo (403 sem ele). {simular:true} confere sem gravar nem
// mandar e devolve o texto. Desliga com config.entrega_conferir_ativo = '0'.

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req: Request) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfg } = await admin.from('config').select('chave, valor')
      .in('chave', ['cron_token', 'entrega_conferir_ativo']);
    const C: Record<string, string> = {};
    (cfg || []).forEach((c: { chave: string; valor: string }) => { C[c.chave] = c.valor; });
    if (!C.cron_token || (body.token || '') !== C.cron_token) return json({ erro: 'Não autorizado.' }, 403);

    const simular = body.simular === true;
    if ((C.entrega_conferir_ativo || '0') !== '1' && !simular) return json({ ok: true, desligado: true });

    const { data: r, error } = await admin.rpc('entrega_conferir', { p_simular: simular });
    if (error) return json({ erro: 'entrega_conferir: ' + error.message }, 500);
    // o telefone de quem recebe não sai na resposta
    const resumo = { simular, novos: r?.novos ?? 0, tardias: r?.tardias ?? 0, grupos: r?.grupos ?? 0,
      falhando: r?.falhando ?? 0, sistema: !!r?.sistema, tem_destino: !!r?.destino };
    if (simular) return json({ ok: true, ...resumo, falta: r?.falta || [], texto: r?.texto || null });
    if (!r?.texto) return json({ ok: true, ...resumo, avisados: 0 });
    if (!r.destino) return json({ ok: false, ...resumo, erro: 'Ninguém da equipe é resp_posvenda com telefone: o aviso não saiu.' });

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZI || !ZT || !ZC) return json({ erro: 'Z-API não configurada.' }, 500);
    const z = await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
      body: JSON.stringify({ phone: r.destino, message: r.texto }),
    }).catch(() => null);
    if (!z || !z.ok) return json({ ok: false, ...resumo, erro: 'Z-API recusou o aviso (' + (z ? z.status : 'sem resposta') + '); tenta de novo na próxima rodada.' }, 502);

    const ids = (r.ids || []) as number[];
    const { data: n, error: e2 } = await admin.rpc('entrega_avisada', { p_ids: ids });
    if (e2) return json({ ok: false, ...resumo, erro: 'aviso saiu, mas não consegui marcar: ' + e2.message }, 500);
    return json({ ok: true, ...resumo, avisados: n });
  } catch (e) {
    return json({ erro: String((e as Error)?.message || e) }, 500);
  }
});
