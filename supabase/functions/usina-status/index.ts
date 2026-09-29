import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BASE = 'https://api.solarview.com.br/v2';
const UA = 'POLARISENERGIASOLAR (polarisenergiasolar; engenharia@polarisenergiasolar.com)';

const STATUS: Record<string, string> = {
  '1': 'nao monitorada', '2': 'operando', '3': 'datalogger offline',
  '4': 'datalogger sem coletar', '5': 'nao injetando', '6': 'nao injetando com evento',
  '7': 'inversores inativos', '8': 'medidores inativos', '9': 'sem status',
};
// perdeu contato: pode estar gerando, so nao conseguimos ver
const COMUNICACAO = new Set(['3', '4']);
// a plataforma AFIRMA que o equipamento parou
const FALHA = new Set(['5', '6', '7', '8']);
const RUINS = new Set([...COMUNICACAO, ...FALHA]);

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

async function token(admin: any, C: Record<string, string>) {
  const idade = C.solarview_token_em ? (Date.now() - new Date(C.solarview_token_em).getTime()) / 86400000 : 999;
  if (C.solarview_token && idade < 6) return C.solarview_token;
  const r = await fetch(`${BASE}/authenticate`, {
    headers: {
      'solarview-apikey': C.solarview_apikey,
      'Authorization': 'Basic ' + btoa(`${C.solarview_user}:${C.solarview_senha}`),
      'User-Agent': UA,
    },
  });
  if (!r.ok) return null;
  const d = await r.json();
  const tk = d['solarview-token'];
  if (tk) {
    await admin.from('config').upsert([
      { chave: 'solarview_token', valor: tk },
      { chave: 'solarview_token_em', valor: new Date().toISOString() },
    ]);
  }
  return tk || null;
}

Deno.serve(async (req) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });
    if ((body.token || '') !== C.cron_token) return json({ erro: 'nao autorizado' }, 403);

    const agora = new Date(Date.now() - 3 * 3600000);
    const h = agora.getUTCHours();
    const hIni = parseInt(C.usina_hora_ini || '9', 10);
    const hFim = parseInt(C.usina_hora_fim || '17', 10);
    if ((h < hIni || h >= hFim) && !body.forcar) return json({ ok: true, fora_da_janela: true, hora: h });

    const tk = await token(admin, C);
    if (!tk) return json({ erro: 'sem token' }, 400);

    const mapa = new Map<string, string>();
    let pagina = 1, totalPaginas = 1;
    while (pagina <= totalPaginas && pagina <= 30) {
      const r = await fetch(`${BASE}/portfolio/1/consumerUnit/${pagina}`, {
        headers: { 'solarview-token': tk, 'User-Agent': UA },
      });
      if (!r.ok) return json({ erro: 'portfolio', status: r.status }, 400);
      const d = await r.json();
      const p = d.PaginationOfConsumerUnit || d;
      const achatar = (v: any): any[] => !v ? [] : Array.isArray(v) ? v.flatMap(achatar) : [v];
      for (const u of achatar(p.content)) {
        const id = String(u?.consumerUnitEntityID || u?.consumerUnitId || '');
        if (id) mapa.set(id, String(u?.powerPlantStatus ?? ''));
      }
      totalPaginas = parseInt(p.totalPages || '1', 10);
      pagina++;
    }

    const { data: usinas } = await admin.from('v_usinas_monitoradas').select('*').eq('plataforma', 'solarview');
    if (!usinas?.length) return json({ ok: true, usinas: 0 });

    let ruins = 0, lidas = 0;
    const linhas: any[] = [];
    for (const u of usinas as any[]) {
      const cod = mapa.get(String(u.id_externo));
      if (cod === undefined) continue;
      lidas++;
      if (RUINS.has(cod)) ruins++;
      linhas.push({ usina_id: u.usina_id, status_cod: cod, status: STATUS[cod] || cod });
    }
    if (!lidas) return json({ ok: true, lidas: 0 });

    await admin.from('usina_leitura').insert(
      linhas.map((l) => ({ usina_id: l.usina_id, plataforma: 'solarview', status_cod: l.status_cod, status: l.status })),
    );

    for (const l of linhas) {
      const u = (usinas as any[]).find((x) => x.usina_id === l.usina_id);
      const patch: any = { status_atual: l.status };
      if (u?.status_atual !== l.status) patch.status_desde = new Date().toISOString();
      await admin.from('usinas').update(patch).eq('id', l.usina_id);
    }

    // ---- daqui para baixo e so aviso. A leitura acima sempre acontece. ----
    if ((C.usina_alerta_ativo || '0') !== '1' && !body.forcar_alerta) {
      return json({ ok: true, lidas, ruins, aviso: 'desligado — so leitura' });
    }

    // primeira leitura do dia nao dispara: o inversor pode estar acordando
    const hMinAlerta = parseInt(C.usina_hora_min_alerta || String(hIni + 3), 10);
    if (h < hMinAlerta && !body.forcar_alerta) {
      return json({ ok: true, lidas, ruins, aviso: `so a partir das ${hMinAlerta}h` });
    }

    const limite = parseFloat(C.usina_limite_geral || '0.5');
    if (ruins / lidas >= limite) {
      return json({ ok: true, lidas, ruins, silenciado: 'muitas ruins ao mesmo tempo' });
    }

    // dias em que o CLIENTE desliga a usina de proposito (usinas.desliga_dias_semana,
    // 0 = domingo). Usina desligada nesse dia nao e parada: nao avisa.
    const hojeDow = agora.getUTCDay();
    const { data: desl } = await admin.from('usinas').select('id,desliga_dias_semana')
      .not('desliga_dias_semana', 'is', null);
    const desligaHoje = new Set((desl || [])
      .filter((x: any) => (x.desliga_dias_semana || []).includes(hojeDow))
      .map((x: any) => x.id));

    const diasComm = parseInt(C.usina_alerta_comunicacao_dias || '2', 10);
    const candidatas: any[] = [];

    for (const l of linhas) {
      if (!RUINS.has(l.status_cod)) continue;
      const u = (usinas as any[]).find((x) => x.usina_id === l.usina_id);
      if (!u || u.optout_em) continue;
      if (desligaHoje.has(l.usina_id)) continue;

      // exige duas leituras ruins seguidas (evita oscilacao pontual)
      const { data: ant } = await admin.from('usina_leitura')
        .select('status_cod').eq('usina_id', l.usina_id)
        .order('lida_em', { ascending: false }).range(1, 1);
      if (!ant?.[0] || !RUINS.has(String(ant[0].status_cod))) continue;

      // nao repete o aviso do mesmo episodio
      if (u.alerta_parada_em && u.status_desde
          && new Date(u.alerta_parada_em) > new Date(u.status_desde)) continue;

      let tipo = FALHA.has(l.status_cod) ? 'falha' : 'comunicacao';

      if (tipo === 'comunicacao') {
        // perda de contato so vira aviso se ja durou alguns dias E a usina parou de gerar
        const { data: ultimo } = await admin.from('usina_dia')
          .select('dia').eq('usina_id', l.usina_id).gt('kwh', 0.5)
          .order('dia', { ascending: false }).limit(1).maybeSingle();
        const diasSemGerar = ultimo?.dia
          ? Math.floor((Date.now() - new Date(ultimo.dia + 'T12:00:00Z').getTime()) / 86400000)
          : 999;
        if (diasSemGerar < diasComm) continue;   // caiu agora: espera
        // e uma parada de verdade, nao so wi-fi instavel
        candidatas.push({ ...u, status: l.status, tipo, dias: diasSemGerar });
      } else {
        candidatas.push({ ...u, status: l.status, tipo, dias: null });
      }
    }
    if (!candidatas.length) return json({ ok: true, lidas, ruins, alertas: 0, desligadas_pelo_cliente: desligaHoje.size });

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    const { data: resp } = await admin.from('equipe').select('nome,telefone')
      .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();

    if (body.simular === true) {
      return json({ ok: true, lidas, ruins, alertas: candidatas.length, desligadas_pelo_cliente: desligaHoje.size,
        detalhe: candidatas.map((c: any) => ({ cliente: c.cliente, tipo: c.tipo, status: c.status, dias: c.dias })) });
    }

    let enviado = false;
    if (ZI && ZT && ZC && resp?.telefone) {
      const falhas = candidatas.filter((c: any) => c.tipo === 'falha');
      const comms = candidatas.filter((c: any) => c.tipo === 'comunicacao');
      let msg = `⚠️ *${candidatas.length} usina${candidatas.length > 1 ? 's' : ''} para olhar*\n`;
      if (falhas.length) {
        msg += `\n*Equipamento parado* — a plataforma acusa falha:\n`;
        for (const c of falhas.slice(0, 8)) {
          msg += `• ${String(c.cliente).split(' ').slice(0, 2).join(' ')} (${c.contrato})`
               + (c.apelido ? ` — ${c.apelido}` : '') + `\n  ${c.status}\n`;
        }
      }
      if (comms.length) {
        msg += `\n*Sem comunicar e sem gerar*:\n`;
        for (const c of comms.slice(0, 8)) {
          msg += `• ${String(c.cliente).split(' ').slice(0, 2).join(' ')} (${c.contrato})`
               + ` — ${c.dias} dias sem gerar\n`;
        }
      }
      msg += `\n_Duas leituras seguidas, com sol._`;
      const r = await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
        body: JSON.stringify({ phone: resp.telefone, message: msg }),
      });
      enviado = r.ok;
    }
    if (enviado) {
      await admin.from('usinas').update({ alerta_parada_em: new Date().toISOString() })
        .in('id', candidatas.map((c: any) => c.usina_id));
    }
    return json({ ok: true, lidas, ruins, alertas: candidatas.length, enviado });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
