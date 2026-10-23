import { createClient } from '@supabase/supabase-js';

// Exclui uma obra de vez (só admin, botão "Excluir esta obra permanentemente"
// do card). Versionado aqui em 23/10, na v5.
//
// Até a v4 os arquivos do storage eram apagados ANTES da obra: quando o banco
// recusava o delete (obra com movimento do extrato, compra de cartão ou visita de
// plano ligados — FK sem cascade), as fotos já tinham ido embora e a obra ficava,
// com o relatório quebrado. Agora a obra sai primeiro; só depois os arquivos.
// Se sobrar arquivo porque o storage falhou, é órfão, não perda.
//
// Cliente que desistiu não se exclui: cancela (obra_cancelar), e o histórico fica.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: admin_ok } = await userClient.rpc('is_admin');
    if (!admin_ok) return json({ error: 'Somente o administrador pode excluir obras.' }, 403);

    const { obra_id } = await req.json();
    if (!obra_id) return json({ error: 'obra_id é obrigatório.' }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: obra } = await admin.from('obras').select('id,cliente').eq('id', obra_id).maybeSingle();
    if (!obra) return json({ error: 'Obra não encontrada.' }, 404);

    // a obra primeiro: se o banco recusar, nenhum arquivo foi tocado
    const { error: eDel } = await admin.from('obras').delete().eq('id', obra_id);
    if (eDel) return json({ error: 'Erro ao excluir: ' + eDel.message }, 500);

    // Remove arquivos do storage (pasta da obra)
    let arquivos = 0;
    try {
      const { data: lista } = await admin.storage.from('fotos-obras').list(obra_id, { limit: 1000 });
      if (lista && lista.length) {
        const paths = lista.map((f: any) => `${obra_id}/${f.name}`);
        await admin.storage.from('fotos-obras').remove(paths);
        arquivos = paths.length;
      }
    } catch (_) { /* a obra já saiu; arquivo que sobrar é órfão */ }

    return json({ ok: true, cliente: obra.cliente, arquivos });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
