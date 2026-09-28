import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Sol de cada lugar com usina (Open-Meteo, shortwave_radiation_sum), um ponto
// por grade de 0,1° — usinas vizinhas dividem o ponto. É o que a
// usinas_saude_calc() usa para tirar o dia nublado da conta: sem esta rodada
// os dias novos ficam sem sol e a janela da saúde vai secando.
//
// Chamada pelo cron com {token, dias}. {simular:true} lê a API e devolve a
// comparação com o que já está gravado, sem gravar nada (regra 3.2).

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
}

// Araçatuba: o mesmo ponto que a saúde usa para usina sem coordenada
const PADRAO = { lat: -21.2, lon: -50.4 };

Deno.serve(async (req) => {
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: tok } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (!tok?.valor || (body.token || '') !== tok.valor) return json({ erro: 'Não autorizado.' }, 403);

    const simular = body.simular === true;
    const dias = Math.min(Math.max(parseInt(body.dias ?? '7', 10) || 7, 1), 60);

    const { data: us, error: eu } = await admin.from('usinas')
      .select('latitude, longitude').eq('ativa', true);
    if (eu) return json({ erro: eu.message }, 500);

    const pontos = new Map<string, { lat: number; lon: number }>();
    const r1 = (x: number) => Math.round(x * 10) / 10;
    pontos.set(`${PADRAO.lat},${PADRAO.lon}`, PADRAO);
    for (const u of us || []) {
      if (u.latitude == null || u.longitude == null) continue;
      const p = { lat: r1(Number(u.latitude)), lon: r1(Number(u.longitude)) };
      pontos.set(`${p.lat},${p.lon}`, p);
    }
    const lista = [...pontos.values()];

    const url = 'https://api.open-meteo.com/v1/forecast'
      + `?latitude=${lista.map((p) => p.lat).join(',')}`
      + `&longitude=${lista.map((p) => p.lon).join(',')}`
      + '&daily=shortwave_radiation_sum&timezone=America%2FSao_Paulo'
      + `&past_days=${dias}&forecast_days=1`;
    const resp = await fetch(url);
    if (!resp.ok) return json({ erro: `Open-Meteo respondeu ${resp.status}` }, 502);
    const dados = await resp.json();
    const arr = Array.isArray(dados) ? dados : [dados];
    if (arr.length !== lista.length) {
      return json({ erro: `Open-Meteo devolveu ${arr.length} pontos para ${lista.length} pedidos` }, 502);
    }

    // só dia fechado: o de hoje ainda está acontecendo
    const hoje = new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10);
    const linhas: { lat: number; lon: number; dia: string; kwh_m2: number; lido_em: string }[] = [];
    const agora = new Date().toISOString();
    arr.forEach((d: any, i: number) => {
      const t: string[] = d?.daily?.time || [];
      const v: (number | null)[] = d?.daily?.shortwave_radiation_sum || [];
      t.forEach((dia, j) => {
        if (dia >= hoje || v[j] == null) return;
        linhas.push({ lat: lista[i].lat, lon: lista[i].lon, dia,
                      kwh_m2: Math.round((v[j]! / 3.6) * 1000) / 1000, lido_em: agora });
      });
    });

    if (simular) {
      // compara com o que já está gravado, para ver se a fonte bate
      const ini = linhas.reduce((m, l) => (l.dia < m ? l.dia : m), '9999-12-31');
      const { data: grav } = await admin.from('radiacao_dia').select('lat, lon, dia, kwh_m2').gte('dia', ini);
      const g = new Map((grav || []).map((x: any) => [`${Number(x.lat)},${Number(x.lon)},${x.dia}`, Number(x.kwh_m2)]));
      let comparados = 0, somaDif = 0, maiorDif = 0, novos = 0;
      for (const l of linhas) {
        const k = g.get(`${l.lat},${l.lon},${l.dia}`);
        if (k == null) { novos++; continue; }
        comparados++; const d = Math.abs(l.kwh_m2 - k); somaDif += d; if (d > maiorDif) maiorDif = d;
      }
      return json({ ok: true, simular: true, nada_gravado: true, pontos: lista.length, linhas: linhas.length,
                    novos, comparados,
                    dif_media_kwh_m2: comparados ? Math.round((somaDif / comparados) * 1000) / 1000 : null,
                    dif_maior_kwh_m2: Math.round(maiorDif * 1000) / 1000,
                    ultimo_dia: linhas.reduce((m, l) => (l.dia > m ? l.dia : m), '') });
    }

    const { error: eg } = await admin.from('radiacao_dia').upsert(linhas, { onConflict: 'lat,lon,dia' });
    if (eg) return json({ erro: eg.message }, 500);
    return json({ ok: true, pontos: lista.length, linhas: linhas.length,
                  ultimo_dia: linhas.reduce((m, l) => (l.dia > m ? l.dia : m), '') });
  } catch (e) {
    return json({ erro: String((e as Error)?.message || e) }, 500);
  }
});
