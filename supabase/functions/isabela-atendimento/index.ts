import { createClient } from '@supabase/supabase-js';

// Isabela — escada de atendimento nos grupos de cliente (Vitor, 14/10).
//
// Cliente escreve no grupo e ninguém da equipe responde:
//   2 h úteis → aviso no privado do VENDEDOR da obra (sem vendedor, vai ao pós-venda)
//   4 h úteis → aviso ao pós-venda (equipe.resp_posvenda)
//   mensagem mandada no sábado, domingo ou feriado: passadas 2 h, a Isabela diz
//   NO GRUPO que o atendimento é de segunda a sexta e que alguém retoma o contato.
// Antes de avisar, a IA lê a conversa e decide se a mensagem precisa mesmo de
// resposta e se alguma mensagem nossa — inclusive automática — já respondeu.
// O que sai pelo número da Isabela não fica em mensagens_recebidas; por isso
// o contexto inclui os envios automáticos conhecidos (vistoria, relatório,
// régua) como linhas da Polaris.
//
// Corpo: { token } — rodada normal (só age com atendimento_ativo = 1)
//        { token, simular: true } — decide tudo, não grava nem envia
//        { token, replay: { de, ate, passo_min, hora_ini, hora_fim } } — refaz o
//          passado em pontos de tempo, sempre simulado (para medir antes de ligar)
// Aprendizado: os casos corrigidos pela equipe (atendimento_exemplo) entram no
// prompt como exemplo — o mesmo desenho do classificacoes_exemplo do webhook.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

// Brasília: UTC-3, sem horário de verão desde 2019
const H3 = 3 * 3600000;
const brt = (d: Date) => new Date(d.getTime() - H3);
const ymd = (d: Date) => brt(d).toISOString().slice(0, 10);
const hh = (d: Date) => brt(d).getUTCHours();
const p2 = (n: number) => String(n).padStart(2, '0');
const hhmm = (d: Date) => `${p2(brt(d).getUTCHours())}:${p2(brt(d).getUTCMinutes())}`;
const ddmm = (d: Date) => `${p2(brt(d).getUTCDate())}/${p2(brt(d).getUTCMonth() + 1)}`;
const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
const CURTO = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

function quando(d: Date, agora: Date) {
  const dd = Math.round((Date.parse(ymd(agora)) - Date.parse(ymd(d))) / 86400000);
  if (dd === 0) return `hoje às ${hhmm(d)}`;
  if (dd === 1) return `ontem às ${hhmm(d)}`;
  return `${CURTO[brt(d).getUTCDay()]} ${ddmm(d)} às ${hhmm(d)}`;
}
function com55(tel?: string | null) {
  const d = String(tel || '').replace(/\D/g, '');
  if (d.length < 10) return '';
  return d.length <= 11 && !d.startsWith('55') ? '55' + d : d;
}
const cap = (w: string) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
const primeiroNome = (s: string) => cap(String(s || '').trim().split(/\s+/)[0] || '');
const nomeCliente = (s: string) => String(s || '').trim().split(/\s+/).slice(0, 2).map(cap).join(' ');
// senha e e-mail que o cliente mandou no grupo não vão para a IA nem para o aviso
const mascara = (t: string) => String(t || '')
  .replace(/(senha\s*[:=]?\s*)\S+/gi, '$1***')
  .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, '[e-mail]');

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { data: cfgRows } = await admin.from('config').select('chave,valor');
    const C: Record<string, string> = {};
    (cfgRows || []).forEach((c: any) => { C[c.chave] = c.valor; });
    if (!C.cron_token || (body.token || '') !== C.cron_token) return json({ erro: 'Não autorizado.' }, 403);

    const replay = body.replay || null;
    const simular = body.simular === true || !!replay;
    if (C.atendimento_ativo !== '1' && !simular) return json({ ok: true, desligado: true });
    if (!C.anthropic_key) return json({ erro: 'sem chave da IA' }, 500);

    const num = (k: string, d: number) => { const v = parseInt(C[k] || '', 10); return isFinite(v) ? v : d; };
    const P = {
      vendMin: num('atendimento_vendedor_min', 120),
      posMin: num('atendimento_posvenda_min', 240),
      hIni: num('atendimento_hora_ini', 8),
      hFim: num('atendimento_hora_fim', 18),
      fdsAtivo: C.atendimento_fds_ativo === '1',
      fdsMin: num('atendimento_fds_min', 120),
      fdsIni: num('atendimento_fds_hora_ini', 8),
      fdsFim: num('atendimento_fds_hora_fim', 20),
      fdsTexto: C.atendimento_fds_texto || '',
      modelo: C.ia_modelo || 'claude-haiku-4-5-20251001',
      desde: C.atendimento_desde ? new Date(C.atendimento_desde) : null,
    };

    const { data: fer } = await admin.from('feriados').select('data').eq('ativo', true);
    const FER = new Set((fer || []).map((f: any) => f.data));
    const diaUtil = (d: Date) => { const w = brt(d).getUTCDay(); return w >= 1 && w <= 5 && !FER.has(ymd(d)); };
    const expediente = (d: Date) => diaUtil(d) && hh(d) >= P.hIni && hh(d) < P.hFim;
    const proximoUtil = (d: Date) => {
      let x = d;
      for (let i = 0; i < 15; i++) { x = new Date(x.getTime() + 86400000); if (diaUtil(x)) break; }
      return x;
    };
    const quandoRetorno = (T: Date) => {
      const x = proximoUtil(T);
      return `na ${DIAS[brt(x).getUTCDay()]}-feira (${ddmm(x)})`;
    };

    const { data: eq } = await admin.from('equipe').select('id,nome,telefone,ativo,resp_posvenda');
    const EQ: Record<string, any> = {};
    (eq || []).forEach((e: any) => { EQ[e.id] = e; });
    const posvenda = (eq || []).find((e: any) => e.ativo && e.resp_posvenda && e.telefone) || null;
    const vendedorDe = (c: any) => {
      const v = c.vendedor_id ? EQ[c.vendedor_id] : null;
      return v && v.ativo && v.telefone ? v : null;
    };

    const { data: ex } = await admin.from('atendimento_exemplo')
      .select('trecho,precisa_resposta,observacao').eq('ativo', true)
      .order('criado_em', { ascending: false }).limit(20);
    const exemplos = (ex || []).length
      ? '\n\nExemplos já corrigidos pela equipe (siga o mesmo critério):\n' + (ex || []).map((e: any) =>
        `- "${mascara(String(e.trecho)).slice(0, 220)}" → ${e.precisa_resposta ? 'PRECISA de resposta' : 'NÃO precisa'}${e.observacao ? ' (' + e.observacao + ')' : ''}`).join('\n')
      : '';

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    const zapi = async (phone: string, message: string) => {
      if (!ZI || !ZT || !ZC || !phone) return false;
      const r = await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
        body: JSON.stringify({ phone, message }),
      });
      return r.ok;
    };

    // ---------- a conversa como a IA vai ler ----------
    async function montarContexto(c: any, T: Date) {
      const ini = new Date(new Date(c.desde).getTime() - 2 * 86400000);
      const { data: ms } = await admin.from('mensagens_recebidas')
        .select('recebida_em,da_equipe,remetente_nome,tipo,texto,transcricao,contexto')
        .eq('obra_id', c.obra_id).gte('recebida_em', ini.toISOString()).lte('recebida_em', T.toISOString())
        .order('recebida_em', { ascending: false }).limit(30);
      const { data: o } = await admin.from('obras')
        .select('cpfl_avisado_em,cpfl_solicitado_em,cpfl_prazo_em,relatorio_enviado_em').eq('id', c.obra_id).maybeSingle();
      const { data: rg } = await admin.from('regua_contatos').select('enviado_em,modelo,texto_custom')
        .eq('obra_id', c.obra_id).gte('enviado_em', ini.toISOString()).lte('enviado_em', T.toISOString());

      const itens: { t: Date; txt: string; cliente: boolean; conteudo: string }[] = [];
      (ms || []).forEach((m: any) => {
        // "outro" é evento do WhatsApp que não é mensagem (troca de foto do grupo, etc.)
        if (m.tipo === 'outro') return;
        const conteudo = mascara(String(m.transcricao || m.texto || '').replace(/\s+/g, ' ')).slice(0, 300);
        // "[imagem]" sem legenda já vem assim do webhook; o prefixo é só para legenda e transcrição
        const midia = m.tipo && m.tipo !== 'texto' && !conteudo.startsWith('[') ? `[${m.tipo}] ` : '';
        const auto = m.contexto === 'automatica' || /sistema/i.test(m.remetente_nome || '');
        const quem = m.da_equipe
          ? (auto ? 'POLARIS (Isabela, automática)' : `POLARIS (${primeiroNome(m.remetente_nome || 'equipe')})`)
          : `CLIENTE (${primeiroNome(m.remetente_nome || 'cliente')})`;
        itens.push({ t: new Date(m.recebida_em), txt: `${quem}: ${midia}${conteudo}`, cliente: !m.da_equipe, conteudo: midia + conteudo });
      });
      const evento = (iso: string | null | undefined, txt: string) => {
        if (!iso) return;
        const t = new Date(iso);
        if (t >= ini && t <= T) itens.push({ t, txt: `POLARIS (Isabela, automática): ${txt}`, cliente: false, conteudo: txt });
      };
      // o aviso da vistoria responde "quando começa a contar?": as datas têm de estar na linha
      const dm = (s: string | null | undefined) => s ? String(s).split('-').reverse().slice(0, 2).join('/') : '';
      const contaDe = o?.cpfl_solicitado_em ? ddmm(proximoUtil(new Date(`${o.cpfl_solicitado_em}T12:00:00-03:00`))) : '';
      evento(o?.cpfl_avisado_em, '[aviso da vistoria da concessionária'
        + (o?.cpfl_solicitado_em ? `: solicitada em ${dm(o.cpfl_solicitado_em)}; os 5 dias úteis contam a partir de ${contaDe}` : '')
        + (o?.cpfl_prazo_em ? `; inspeção e troca do medidor até ${dm(o.cpfl_prazo_em)}` : '') + ']');
      evento(o?.relatorio_enviado_em, '[relatório da instalação, com fotos]');
      (rg || []).forEach((r: any) => evento(r.enviado_em,
        `[mensagem automática "${r.modelo}"${r.texto_custom ? ': ' + mascara(String(r.texto_custom).replace(/\s+/g, ' ')).slice(0, 160) : ''}]`));

      itens.sort((a, b) => a.t.getTime() - b.t.getTime());
      const desde = new Date(c.desde);
      const texto = `Agora: ${CURTO[brt(T).getUTCDay()]} ${ddmm(T)} ${hhmm(T)}\n\n` + itens.map((x, i) =>
        `[${i + 1}] ${x.cliente && x.t >= desde ? '→ ' : ''}${CURTO[brt(x.t).getUTCDay()]} ${ddmm(x.t)} ${hhmm(x.t)} ${x.txt}`).join('\n');
      return { texto, itens };
    }

    async function julgar(conversa: string) {
      const sistema = `Você é a Isabela, assistente da Polaris Energia Solar (instalação de energia solar, interior de São Paulo). Você lê a conversa do grupo de WhatsApp de uma obra, entre o cliente e a equipe da Polaris, e decide se o CLIENTE está esperando uma resposta da Polaris.

NÃO precisa de resposta: agradecimento, "ok", "combinado", "beleza", "claro, tranquilo", cumprimento sozinho, figurinha, reação, confirmação de algo que a Polaris pediu (inclusive mandar um dado que a Polaris pediu, como e-mail ou foto do relógio, quando a Polaris não precisa responder nada), recado informativo que não pede nada, conversa entre pessoas da família do cliente.
PRECISA de resposta: pergunta, pedido, reclamação, problema na usina, foto ou documento que pede análise (conta de luz, erro no inversor, papel para assinar), áudio com pedido, cobrança de retorno ("alguém?", "?").
Foto, vídeo ou documento SEM explicação: considere que PRECISA de resposta (pode ser um problema), a não ser que a conversa mostre que foi a Polaris que pediu aquilo.
JÁ RESPONDIDA: quando, depois da mensagem do cliente, veio uma mensagem da Polaris — de uma pessoa ou da Isabela automática — que responde ao que ele quer.
Cada linha tem um número [n]. As marcadas com → são do cliente e vieram depois da última resposta de uma PESSOA da equipe.${exemplos}

Responda APENAS com JSON:
{"precisa_resposta": true|false, "ja_respondida": true|false, "a_partir_de": n ou null, "resumo": "o que o cliente quer, até 15 palavras", "urgente": true|false, "motivo": "até 12 palavras"}
"a_partir_de" é o número da PRIMEIRA mensagem do cliente que ainda espera resposta (null se nenhuma).`;
      const r = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-api-key': C.anthropic_key, 'anthropic-version': '2023-06-01' },
        body: JSON.stringify({ model: P.modelo, max_tokens: 300, system: sistema, messages: [{ role: 'user', content: conversa }] }),
      });
      if (!r.ok) throw new Error('IA respondeu ' + r.status);
      const d = await r.json();
      const bruto = (d.content || []).filter((x: any) => x.type === 'text').map((x: any) => x.text).join('');
      const m = bruto.match(/\{[\s\S]*\}/);
      return JSON.parse(m ? m[0] : bruto);
    }

    // ---------- a decisão (a mesma no ao vivo e no replay) ----------
    type Estado = { parecer?: any; avaliado_ate?: string; vend_em?: string; pos_em?: string; fds_em?: string; ia?: number };
    let chamadasIA = 0;

    async function decidir(c: any, T: Date, st: Estado) {
      const minCorr = (T.getTime() - new Date(c.desde).getTime()) / 60000;
      const devido = (expediente(T) && c.min_uteis >= P.vendMin && (!st.vend_em || !st.pos_em))
        || (!diaUtil(T) && !diaUtil(new Date(c.ultima)) && minCorr >= P.fdsMin && hh(T) >= P.fdsIni && hh(T) < P.fdsFim
            && !st.fds_em && T.getTime() - new Date(c.ultima).getTime() < 3 * 86400000);
      if (!devido) return null;

      if (!st.parecer || !st.avaliado_ate || new Date(c.ultima) > new Date(st.avaliado_ate)) {
        const ctx = await montarContexto(c, T);
        const p = await julgar(ctx.texto);
        chamadasIA++;
        const idx = Number(p.a_partir_de);
        const item = isFinite(idx) && idx >= 1 ? ctx.itens[idx - 1] : null;
        p.pendente_desde = item && item.cliente ? item.t.toISOString() : c.desde;
        p.trecho = (item && item.cliente ? item.conteudo : mascara(String(c.trecho || ''))).slice(0, 200);
        st.parecer = p;
        st.avaliado_ate = c.ultima;
      }
      const p = st.parecer;
      if (!p.precisa_resposta || p.ja_respondida) return { fechar: p.ja_respondida ? 'respondida_isabela' : 'nao_precisava' };

      // a espera conta da mensagem que a IA apontou, não da primeira do bloco
      const pend = new Date(p.pendente_desde || c.desde);
      const { data: mu } = await admin.rpc('minutos_uteis', { p_ini: pend.toISOString(), p_fim: T.toISOString() });
      const minUteis = Number(mu || 0);
      const minCorrPend = (T.getTime() - pend.getTime()) / 60000;
      const vend = vendedorDe(c);
      const out: any = { minUteis, pend };
      if (expediente(T) && minUteis >= P.vendMin && !st.vend_em) out.degrau1 = vend || posvenda;
      if (expediente(T) && minUteis >= P.posMin && !st.pos_em && vend) out.degrau2 = posvenda;
      // o aviso de horário é para quem escreveu NO fim de semana ou feriado (Vitor, 14/10);
      // mensagem de quinta ou sexta sem resposta é assunto da escada, não do aviso no grupo
      if (!diaUtil(T) && !diaUtil(pend) && minCorrPend >= P.fdsMin && hh(T) >= P.fdsIni && hh(T) < P.fdsFim && !st.fds_em) out.fds = true;
      return out;
    }

    function textoEquipe(c: any, st: Estado, T: Date, tipo: 'vendedor' | 'posvenda' | 'sem_vendedor') {
      const p = st.parecer || {};
      const pend = new Date(p.pendente_desde || c.desde);
      const vend = vendedorDe(c);
      let m = (tipo === 'posvenda' ? '⏳ *Cliente ainda sem resposta*' : '⏳ *Cliente esperando resposta*') + '\n\n'
        + `*${nomeCliente(c.cliente)}*${c.contrato ? ' (' + c.contrato + ')' : ''} escreveu no grupo ${quando(pend, T)}:\n`
        + `_"${p.trecho || mascara(c.trecho || '')}"_\n`;
      if (p.resumo) m += `\n🧠 ${p.resumo}\n`;
      if (tipo === 'posvenda' && vend && st.vend_em) m += `\nJá avisei: ${vend.nome.split(' ')[0]} (vendas), ${quando(new Date(st.vend_em), T)}.\n`;
      if (tipo === 'sem_vendedor') m += `\nEsta obra não tem vendedor no cadastro, por isso o aviso veio direto para você.\n`;
      m += `\nPode responder lá no grupo? Quando alguém da equipe responder, eu paro de avisar.\n\n— Isabela ☀️`;
      return m;
    }

    async function agir(c: any, T: Date, st: Estado, out: any) {
      const feito: any = {};
      if (out.degrau1) {
        const semVend = !vendedorDe(c);
        const texto = textoEquipe(c, st, T, semVend ? 'sem_vendedor' : 'vendedor');
        const ok = simular ? true : await zapi(com55(out.degrau1.telefone), texto);
        feito.aviso1 = { para: out.degrau1.nome, texto, enviado: !simular && ok };
        if (ok) { st.vend_em = T.toISOString(); if (semVend) st.pos_em = st.vend_em; }
      }
      if (out.degrau2 && !st.pos_em) {
        const texto = textoEquipe(c, st, T, 'posvenda');
        const ok = simular ? true : await zapi(com55(out.degrau2.telefone), texto);
        feito.aviso2 = { para: out.degrau2.nome, texto, enviado: !simular && ok };
        if (ok) st.pos_em = T.toISOString();
      }
      if (out.fds) {
        const texto = P.fdsTexto.replace('{quando}', quandoRetorno(T));
        const vai = !simular && P.fdsAtivo;
        const ok = vai ? await zapi(c.grupo, texto) : simular;
        feito.grupo = { texto, enviado: vai && ok, ligado: P.fdsAtivo };
        if (ok) st.fds_em = T.toISOString();
      }
      return feito;
    }

    // ---------- replay: refaz o passado, nunca grava nem envia ----------
    if (replay) {
      const de = new Date(`${replay.de}T00:00:00-03:00`);
      const ate = new Date(`${replay.ate}T23:59:59-03:00`);
      const passo = Math.max(10, parseInt(replay.passo_min || '30', 10)) * 60000;
      const hI = parseInt(replay.hora_ini ?? '7', 10), hF = parseInt(replay.hora_fim ?? '21', 10);
      const estados = new Map<string, Estado & { fechado?: string }>();
      const eventos: any[] = [];
      for (let T = new Date(de.getTime()); T <= ate; T = new Date(T.getTime() + passo)) {
        if (hh(T) < hI || hh(T) >= hF) continue;
        const { data: cands, error } = await admin.rpc('atendimento_candidatos', { p_agora: T.toISOString(), p_desde_min: null });
        if (error) return json({ erro: 'candidatos: ' + error.message }, 500);
        for (const c of (cands || []) as any[]) {
          const chave = `${c.obra_id}|${c.desde}`;
          let st = estados.get(chave) || {};
          if (st.fechado && st.avaliado_ate && new Date(c.ultima) <= new Date(st.avaliado_ate)) continue;
          if (st.fechado) st = { vend_em: st.vend_em, pos_em: st.pos_em, fds_em: st.fds_em };
          let out: any;
          try { out = await decidir(c, T, st); } catch (err) {
            eventos.push({ quando: `${ddmm(T)} ${hhmm(T)}`, contrato: c.contrato, acao: 'erro', motivo: String(err) });
            continue;
          }
          if (out && out.fechar) {
            st.fechado = out.fechar;
            eventos.push({ quando: `${ddmm(T)} ${hhmm(T)}`, contrato: c.contrato, acao: out.fechar,
              resumo: st.parecer?.resumo, motivo: st.parecer?.motivo, trecho: st.parecer?.trecho });
          } else if (out && (out.degrau1 || out.degrau2 || out.fds)) {
            const feito = await agir(c, T, st, out);
            const { data: r } = await admin.from('mensagens_recebidas').select('recebida_em,remetente_nome')
              .eq('obra_id', c.obra_id).eq('da_equipe', true).gt('recebida_em', T.toISOString())
              .order('recebida_em').limit(1).maybeSingle();
            eventos.push({
              quando: `${ddmm(T)} ${hhmm(T)}`, contrato: c.contrato, cliente: nomeCliente(c.cliente),
              acao: [feito.aviso1 && `avisaria ${feito.aviso1.para}`, feito.aviso2 && `avisaria ${feito.aviso2.para}`,
                     feito.grupo && 'mandaria o aviso de horário no grupo'].filter(Boolean).join(' + '),
              espera_desde: `${ddmm(out.pend)} ${hhmm(out.pend)}`, resumo: st.parecer?.resumo, trecho: st.parecer?.trecho,
              equipe_respondeu: r ? `${ddmm(new Date(r.recebida_em))} ${hhmm(new Date(r.recebida_em))} (${primeiroNome(r.remetente_nome || '')})` : 'sem resposta visível',
              texto: feito.aviso2?.texto || feito.aviso1?.texto || feito.grupo?.texto,
            });
          }
          estados.set(chave, st);
        }
      }
      return json({ ok: true, replay: true, de: replay.de, ate: replay.ate, chamadas_ia: chamadasIA,
        avisos: eventos.filter((e) => e.acao && !['nao_precisava', 'respondida_isabela'].includes(e.acao)).length,
        descartados_pela_ia: eventos.filter((e) => ['nao_precisava', 'respondida_isabela'].includes(e.acao)).length,
        eventos });
    }

    // ---------- rodada normal (ou simulada agora) ----------
    const T = new Date();
    const { data: cands, error: e0 } = await admin.rpc('atendimento_candidatos',
      { p_agora: T.toISOString(), p_desde_min: P.desde ? P.desde.toISOString() : null });
    if (e0) return json({ erro: 'candidatos: ' + e0.message }, 500);
    const { data: recentes } = await admin.from('atendimento_espera').select('*')
      .gte('criado_em', new Date(T.getTime() - 8 * 86400000).toISOString()).order('id', { ascending: false });
    const abertos = (recentes || []).filter((e: any) => !e.fechado_em);
    const naLista = new Set(((cands || []) as any[]).map((c) => c.obra_id));
    const resumo: any = { candidatos: (cands || []).length, fechadas: [], avisos: [], descartadas: [] };

    // espera aberta que saiu da lista: alguém da equipe respondeu no grupo
    for (const e of abertos) {
      if (naLista.has(e.obra_id)) continue;
      const { data: r } = await admin.from('mensagens_recebidas').select('recebida_em,remetente_nome')
        .eq('obra_id', e.obra_id).eq('da_equipe', true).gt('recebida_em', e.desde)
        .order('recebida_em').limit(1).maybeSingle();
      resumo.fechadas.push({ id: e.id, por: r?.remetente_nome || null });
      if (!simular) {
        await admin.from('atendimento_espera').update({ fechado_em: T.toISOString(), fechado_como: 'respondida',
          fechado_por: r?.remetente_nome || null, respondido_em: r?.recebida_em || null }).eq('id', e.id).is('fechado_em', null);
      }
    }

    for (const c of (cands || []) as any[]) {
      const daObra = (recentes || []).filter((e: any) => e.obra_id === c.obra_id);
      let aberto = daObra.find((e: any) => !e.fechado_em) || null;
      if (aberto && new Date(aberto.desde).getTime() !== new Date(c.desde).getTime()) {
        // a espera antiga foi respondida no meio e começou outra
        if (!simular) await admin.from('atendimento_espera').update({ fechado_em: T.toISOString(), fechado_como: 'respondida' })
          .eq('id', aberto.id).is('fechado_em', null);
        aberto = null;
      }
      if (!aberto) {
        // já julgada e fechada pela IA, sem mensagem nova do cliente: nada a fazer
        const julgada = daObra.find((e: any) => e.fechado_em && new Date(e.desde).getTime() === new Date(c.desde).getTime());
        if (julgada && julgada.avaliado_ate && new Date(c.ultima) <= new Date(julgada.avaliado_ate)) continue;
      }
      const st: Estado = aberto
        ? { parecer: aberto.parecer, avaliado_ate: aberto.avaliado_ate, vend_em: aberto.vendedor_avisado_em,
            pos_em: aberto.posvenda_avisado_em, fds_em: aberto.fds_avisado_em }
        : {};
      // o aviso de horário sai uma vez só por fim de semana em cada grupo
      if (!st.fds_em) {
        const fds = daObra.find((e: any) => e.fds_avisado_em && T.getTime() - new Date(e.fds_avisado_em).getTime() < 3 * 86400000);
        if (fds) st.fds_em = fds.fds_avisado_em;
      }
      let out: any;
      try { out = await decidir(c, T, st); } catch (err) { resumo.avisos.push({ contrato: c.contrato, erro: String(err) }); continue; }
      if (!out) continue;
      const feito = out.fechar ? null : await agir(c, T, st, out);
      const linha: any = {
        obra_id: c.obra_id, grupo_id: c.grupo, desde: c.desde, ultima_msg_em: c.ultima, avaliado_ate: st.avaliado_ate,
        precisa_resposta: !!st.parecer?.precisa_resposta, ja_respondida: !!st.parecer?.ja_respondida,
        resumo: st.parecer?.resumo || null, urgente: !!st.parecer?.urgente, parecer: st.parecer || null,
        vendedor_id: c.vendedor_id || null, vendedor_avisado_em: st.vend_em || null,
        posvenda_avisado_em: st.pos_em || null, fds_avisado_em: st.fds_em || null,
      };
      if (out.fechar) {
        linha.fechado_em = T.toISOString(); linha.fechado_como = out.fechar; linha.fechado_por = 'Isabela';
        resumo.descartadas.push({ contrato: c.contrato, como: out.fechar, motivo: st.parecer?.motivo });
      } else {
        resumo.avisos.push({ contrato: c.contrato, ...feito });
      }
      if (!simular) {
        if (aberto) await admin.from('atendimento_espera').update(linha).eq('id', aberto.id);
        else await admin.from('atendimento_espera').insert(linha);
      }
    }
    return json({ ok: true, simular, chamadas_ia: chamadasIA, ...resumo });
  } catch (err) {
    return json({ erro: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
