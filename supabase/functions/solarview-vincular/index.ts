import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BASE = 'https://api.solarview.com.br/v2';
const UA = 'POLARISENERGIASOLAR (polarisenergiasolar; engenharia@polarisenergiasolar.com)';

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), {
    status: s,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
    },
  });
}

async function pegarToken(admin: any, C: Record<string, string>) {
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

// Baixa o portfolio inteiro do SolarView. Usado pelo vinculador automatico e
// pelo modo `listar`, que a tela chama para oferecer as usinas por NOME em vez
// de pedir um id que ninguem sabe de cor.
async function baixarPortfolio(tk: string) {
  const lista: any[] = [];
  let pagina = 1, totalPaginas = 1;
  while (pagina <= totalPaginas && pagina <= 30) {
    const r = await fetch(`${BASE}/portfolio/1/consumerUnit/${pagina}`, {
      headers: { 'solarview-token': tk, 'User-Agent': UA },
    });
    if (!r.ok) return { erro: 'portfolio', status: r.status, lista: [] as any[] };
    const d = await r.json();
    const p = d.PaginationOfConsumerUnit || d;
    const achatar = (v: any): any[] => !v ? [] : Array.isArray(v) ? v.flatMap(achatar) : [v];
    for (const u of achatar(p.content)) {
      const id = String(u?.consumerUnitEntityID || u?.consumerUnitId || '');
      if (!id) continue;
      lista.push({
        id, nome: String(u?.consumerUnitName || ''),
        kwp: parseFloat(u?.consumerUnitConfiguration?.systemSize || '0') || 0,
        instalada: String(u?.consumerUnitConfiguration?.installDate || '').slice(0, 10) || null,
        cidade: u?.consumerUnitLocation?.city || null,
      });
    }
    totalPaginas = parseInt(p.totalPages || '1', 10);
    pagina++;
  }
  return { lista };
}

function palavras(s: string): string[] {
  return String(s || '').toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ').split(/\s+/)
    .filter((w) => w.length > 2 && !['dos','das','ltda','mei','epp','eireli','outro'].includes(w));
}
function sobrenomes(s: string): Set<string> {
  return new Set(palavras(s).slice(1));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });

    // Duas portas, e elas NAO valem o mesmo:
    //  · cron_token  -> tudo, inclusive gravar vinculo (e o que o cron usa)
    //  · usuario logado -> SO o modo `listar`, que nao grava nada
    // A tela nao tem (nem pode ter) o cron_token: a RLS da config so expoe
    // quatro chaves, e nenhuma e essa.
    const porToken = (body.token || '') === C.cron_token;
    let porUsuario = false;
    if (!porToken) {
      const authHeader = req.headers.get('Authorization') ?? '';
      if (authHeader) {
        const u = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
        const { data: ok } = await u.rpc('is_autorizado');
        porUsuario = !!ok;
      }
    }
    if (!porToken && !porUsuario) return json({ erro: 'nao autorizado' }, 403);
    if (!porToken && body.listar !== true) {
      return json({ erro: 'usuario logado so pode listar; vincular em lote e do cron' }, 403);
    }

    // ── modo LISTAR: devolve o portfolio para a tela escolher pelo nome ─────
    if (body.listar === true) {
      const tk = await pegarToken(admin, C);
      if (!tk) return json({ erro: 'sem token do solarview' }, 400);
      const p = await baixarPortfolio(tk);
      if ((p as any).erro) return json(p, 400);
      const { data: usados } = await admin.from('usina_monitoramento')
        .select('id_externo, usina_id, usinas(apelido)').eq('plataforma', 'solarview').eq('ativo', true);
      const dono = new Map<string, string>();
      (usados || []).forEach((x: any) => dono.set(String(x.id_externo), x.usinas?.apelido || 'outra usina'));
      const lista = p.lista
        .map((u: any) => ({ ...u, vinculada_a: dono.get(u.id) || null }))
        .sort((a: any, b: any) => String(a.nome).localeCompare(String(b.nome), 'pt-BR'));
      return json({ ok: true, total: lista.length, lista });
    }

    if ((C.solarview_vincular_ativo || '0') !== '1' && !body.forcar) return json({ ok: true, desligado: true });

    const etapaMin = parseInt(C.solarview_etapa_minima || '7', 10);
    const limiteComum = parseInt(C.vinculo_palavra_comum || '3', 10);
    const minIguais = parseInt(C.vinculo_min_palavras_iguais || '2', 10);

    const { data: obras } = await admin.from('obras')
      .select('id, cliente, contrato, potencia_kwp, cidade, cliente_id, data_conclusao, data_instalacao, etapa_numero')
      .gte('etapa_numero', etapaMin)
      .neq('status', 'Cancelado');
    if (!obras?.length) return json({ ok: true, pendentes: 0 });

    const freq = new Map<string, number>();
    for (const o of obras as any[]) {
      for (const w of new Set(palavras(o.cliente))) freq.set(w, (freq.get(w) || 0) + 1);
    }
    const comuns = new Set([...freq.entries()].filter(([, n]) => n >= limiteComum).map(([w]) => w));

    const { data: ligadas } = await admin.from('obra_usina').select('obra_id');
    const jaTem = new Set((ligadas || []).map((x: any) => x.obra_id));
    const pendentes = (obras as any[]).filter((o) => !jaTem.has(o.id));
    if (!pendentes.length) return json({ ok: true, pendentes: 0 });

    const tk = await pegarToken(admin, C);
    if (!tk) return json({ erro: 'sem token do solarview' }, 400);

    const { data: usados } = await admin.from('usina_monitoramento').select('id_externo').eq('plataforma', 'solarview');
    const ocupados = new Set((usados || []).map((x: any) => String(x.id_externo)));

    const p = await baixarPortfolio(tk);
    if ((p as any).erro) return json(p, 400);
    const lista = p.lista.filter((u: any) => !ocupados.has(u.id));

    const ligados: any[] = [], duvidosos: any[] = [];

    for (const o of pendentes) {
      const palObra = new Set(palavras(o.cliente));
      const sobObra = sobrenomes(o.cliente);
      let melhor: any = null, nota = -1, detalhe = '';

      for (const u of lista) {
        if (ocupados.has(u.id)) continue;
        const temAlgumContrato = /\b4\d{3}\b/.test(u.nome);
        const temEsteContrato = !!(o.contrato && new RegExp('\\b' + o.contrato + '\\b').test(u.nome));
        if (temAlgumContrato && !temEsteContrato) continue;

        const palUsina = new Set(palavras(u.nome));
        const sobUsina = sobrenomes(u.nome);

        let raras = 0, comunsIguais = 0;
        for (const w of palObra) {
          if (!palUsina.has(w)) continue;
          if (comuns.has(w)) comunsIguais++; else raras++;
        }
        const totalIguais = raras + comunsIguais;
        let sobrenomeIgual = false;
        for (const w of sobObra) if (sobUsina.has(w)) { sobrenomeIgual = true; break; }
        const kwpBate = u.kwp > 0 && o.potencia_kwp && Math.abs(u.kwp - parseFloat(o.potencia_kwp)) <= 0.05;

        // regra: o contrato no nome resolve tudo. Sem ele, exige varias palavras
        // iguais E que pelo menos uma seja sobrenome E que pelo menos uma seja rara.
        let n = -1, why = '';
        if (temEsteContrato) { n = 4; why = 'contrato no nome'; }
        else if (totalIguais >= 3 && raras >= 1 && sobrenomeIgual) {
          n = 3; why = totalIguais + ' palavras iguais, com sobrenome';
        } else if (totalIguais >= minIguais && raras >= 1 && sobrenomeIgual && kwpBate) {
          n = 2.5; why = totalIguais + ' palavras iguais + potencia exata';
        } else if (totalIguais >= 1) {
          n = 0.5;
          why = totalIguais === 1
            ? (sobrenomeIgual ? 'so um sobrenome em comum' : 'so o primeiro nome em comum')
            : (sobrenomeIgual ? 'poucas palavras em comum' : 'nenhum sobrenome bate');
        }
        if (n > nota) { nota = n; melhor = u; detalhe = why; }
      }

      if (!melhor || nota < 2) {
        duvidosos.push({ contrato: o.contrato, cliente: o.cliente, etapa: o.etapa_numero,
                         sugestao: melhor?.nome || null, motivo: melhor ? detalhe : 'nada parecido' });
        continue;
      }
      if (body.simular === true) {
        ligados.push({ contrato: o.contrato, cliente: o.cliente, etapa: o.etapa_numero,
                       usina: melhor.nome, nota, por: detalhe, simulado: true });
        ocupados.add(melhor.id);
        continue;
      }

      const { data: nova, error: e1 } = await admin.from('usinas').insert({
        cliente_id: o.cliente_id,
        apelido: o.cidade || 'Usina principal',
        potencia_kwp: o.potencia_kwp,
        data_instalacao: o.data_instalacao || melhor.instalada || o.data_conclusao,
        data_estimada: !o.data_instalacao,
        cidade: o.cidade || melhor.cidade,
        ativa: true,
      }).select('id').single();
      if (e1 || !nova) { duvidosos.push({ contrato: o.contrato, erro: e1?.message }); continue; }

      await admin.from('obra_usina').insert({
        obra_id: o.id, usina_id: nova.id, papel: 'propria', medicao: 'inversor_proprio',
        entrou_em: o.data_instalacao || o.data_conclusao, principal: true,
      });
      await admin.from('usina_monitoramento').insert({
        usina_id: nova.id, plataforma: 'solarview', id_externo: melhor.id, ativo: true,
      });
      ocupados.add(melhor.id);
      ligados.push({ contrato: o.contrato, cliente: o.cliente, etapa: o.etapa_numero,
                     usina: melhor.nome, nota, por: detalhe });
    }

    if (duvidosos.length && !body.simular && (C.solarview_avisa_pendente || '1') === '1') {
      const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
      const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
      const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
      const { data: resp } = await admin.from('equipe').select('telefone')
        .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
      if (ZI && ZT && ZC && resp?.telefone) {
        let msg = `🔌 *${duvidosos.length} obra${duvidosos.length > 1 ? 's' : ''} sem usina no monitoramento*\n\n`;
        for (const d of duvidosos.slice(0, 8)) {
          msg += `• ${String(d.cliente || '').split(' ').slice(0, 2).join(' ')} (${d.contrato || 'sem contrato'})\n`;
        }
        msg += `\n_Cadastre no SolarView com o contrato no nome que eu conecto sozinho._`;
        await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
          body: JSON.stringify({ phone: resp.telefone, message: msg }),
        });
      }
    }

    return json({ ok: true, pendentes: pendentes.length, ligados: ligados.length,
                  sem_certeza: duvidosos.length, detalhe: { ligados, duvidosos } });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
