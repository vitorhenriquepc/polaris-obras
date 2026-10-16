import { createClient } from '@supabase/supabase-js';

// Lembrete de autoleitura.
//
// Dois horarios, decididos pelo Vitor em 15/09/2026:
//   18h  vespera  -- cai depois da regua das 17h, entao nao disputa com ela
//    9h  no dia   -- quem le o relogio faz de manha; 17h seria tarde demais
//
// A janela de fim de semana ja foi resolvida no banco: dia_util_ate() antecipa
// o aviso da vespera para a sexta quando a leitura cai no sabado ou domingo, e
// o aviso "no dia" so existe em dia util. Entao a fila nunca traz ninguem no
// fim de semana, mesmo que o cron rode.
//
// 16/09: passou a mandar TAMBEM no WhatsApp pessoal do cliente, nao so no
// grupo. Motivo: a mensagem do calendario promete os dois canais, entao sem
// isto a promessa seria falsa. A regua continua so no grupo -- este e o unico
// lugar com canal pessoal, e ele nao encosta na `regua-disparo`.
// O aviso so e marcado como enviado se PELO MENOS UM canal aceitou.
//
// 02/10: pode ser MAIS DE UM numero pessoal. Na fazenda do Junior Bassetto
// (UNI AUTO POSTO) quem le o relogio e o caseiro (o telefone da obra) e o dono
// quer receber tambem. O banco devolve `telefone` com os numeros separados por
// virgula (o da obra + unidade_consumidora.telefones_extra), e aqui cada um e
// um envio. Um numero so continua funcionando igual.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
// O telefone do cliente é gravado sem o 55 (18999999999) e a Z-API precisa do
// DDI. Os da equipe, que recebem todo dia, estão todos com 55; os de cliente,
// nenhum (05/10). Sem isto o canal pessoal nunca teve prova de que chega.
function com55(d: string): string {
  return d.length <= 11 && !d.startsWith('55') ? '55' + d : d;
}
function fones(v: unknown): string[] {
  return [...new Set(String(v || '').split(',').map((x) => x.replace(/\D/g, '')).filter((x) => x.length >= 10).map(com55))];
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (!tk || body.token !== tk.valor) return json({ error: 'Nao autorizado.' }, 403);

    const tipo = body.tipo === 'dia' ? 'dia' : 'vespera';
    const simular = body.simular === true;

    const { data: cfg } = await admin.from('config').select('valor').eq('chave', 'autoleitura_ativo').maybeSingle();
    const ligada = (cfg?.valor ?? '0') === '1';
    if (!ligada && !simular) {
      return json({ ok: true, enviados: 0, motivo: 'autoleitura desligada' });
    }

    const { data: fila, error: eFila } = await admin.rpc('autoleitura_fila_svc', { p_tipo: tipo });
    if (eFila) return json({ error: 'Falha ao ler a fila: ' + eFila.message }, 500);
    if (!fila?.length) return json({ ok: true, tipo, enviados: 0, motivo: 'ninguem para avisar hoje' });

    if (simular) {
      return json({ ok: true, simulado: true, tipo, seriam: fila.length,
        previa: fila.map((f: Record<string, unknown>) => ({
          cliente: f.cliente,
          canais: [f.grupo ? 'grupo' : null, ...fones(f.telefone).map((n) => 'pessoal ' + n.slice(-4))].filter(Boolean),
          texto: f.texto })) });
    }

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZI || !ZT || !ZC) return json({ error: 'Z-API nao configurada.' }, 500);
    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };

    const enviar = async (destino: string, texto: string) => {
      const r = await fetch(`${base}/send-text`, {
        method: 'POST', headers: zH,
        body: JSON.stringify({ phone: destino, message: texto }),
      });
      return r.ok;
    };

    const coluna = tipo === 'dia' ? 'avisado_dia_em' : 'avisado_vespera_em';
    const hoje = new Date().toISOString().slice(0, 10);
    let enviados = 0;
    const falhas: string[] = [];
    const detalhes: string[] = [];

    for (const f of fila) {
      const pessoais = fones(f.telefone);
      if (!f.texto || (!f.grupo && !pessoais.length)) {
        falhas.push(`${f.cliente} — sem destino ou sem texto`); continue;
      }
      const chegou: string[] = [];
      const naoChegou: string[] = [];

      if (f.grupo) {
        if (await enviar(String(f.grupo), String(f.texto))) chegou.push('grupo');
        else naoChegou.push('grupo');
        await new Promise((res) => setTimeout(res, 3000));
      }
      for (const n of pessoais) {
        const rot = pessoais.length > 1 ? `pessoal …${n.slice(-4)}` : 'pessoal';
        if (await enviar(n, String(f.texto))) chegou.push(rot);
        else naoChegou.push(rot);
        if (pessoais.length > 1) await new Promise((res) => setTimeout(res, 3000));
      }

      if (chegou.length) {
        // so marca depois que pelo menos um canal aceitou
        await admin.from('uc_leitura_prevista').update({ [coluna]: hoje }).eq('id', f.leitura_id);
        enviados++;
        detalhes.push(`${f.cliente} (${chegou.join(' + ')})`);
        if (naoChegou.length) falhas.push(`${f.cliente} — nao saiu no ${naoChegou.join(' nem no ')}`);
      } else {
        falhas.push(`${f.cliente} — a Z-API recusou todos os canais`);
      }
      await new Promise((res) => setTimeout(res, 3000));
    }

    // avisa a responsavel pelo pos-venda, igual a regua faz
    if (enviados || falhas.length) {
      const { data: resp } = await admin.from('equipe')
        .select('telefone').eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
      if (resp?.telefone) {
        const quando = tipo === 'dia' ? 'hoje e o dia' : 'e amanha';
        const msg = `📷 *Autoleitura — ${enviados} aviso${enviados === 1 ? '' : 's'} (${quando})*\n\n`
          + (detalhes.length ? detalhes.map((d) => `• ${d}`).join('\n') : '_nenhum enviado_')
          + (falhas.length ? `\n\n⚠️ ${falhas.length} com problema:\n` + falhas.map((d) => `• ${d}`).join('\n') : '')
          + `\n\n*Polaris — Pos-venda* ☀️`;
        await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: resp.telefone, message: msg }) });
      }
    }

    return json({ ok: true, tipo, enviados, falhas });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
