import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SISTEMA = `Você lê mensagens que clientes de uma empresa de energia solar (Polaris, interior de São Paulo) mandam no grupo de WhatsApp da obra, LOGO DEPOIS de a empresa pedir uma nota de 0 a 10 sobre o serviço.

Sua tarefa: descobrir se a mensagem contém a NOTA e se o cliente está elogiando ou reclamando.

REGRAS DURAS:
- "tem_nota" só é true se o cliente disser explicitamente uma nota de 0 a 10 sobre o serviço da Polaris. Pode ser algarismo ("10", "nota 9") ou por extenso ("dez", "nove").
- Números que NÃO são nota: valores em reais, parcelas, horários, quantidades de telhas ou módulos, endereços, números de protocolo, datas. Exemplos que NÃO são nota: "Restante ficou 8.000", "Apartir das 7:00 hs", "3 cartório", "71.000 36x 2.707,61".
- Elogio sem número NÃO é nota. "Estão de parabéns, empresa de excelência" → tem_nota false, tipo elogio.
- Se o cliente dá a nota e junto aponta um problema, tipo = "misto" e descreva em "reclamacao". Exemplo: "Só não pude dar 10 pela quantidade de telhas quebradas: 50 telhas. Por isso dei 9" → nota 9, tipo misto, reclamacao "50 telhas quebradas".
- Mensagem de logística ou combinação ("ok", "já está ligado", "acabaram de trocar o relógio") → tipo neutro, tem_nota false.
- Dúvida técnica sem nota → tipo neutro, tem_nota false.
- Se ficar em dúvida, baixe a confiança. É melhor não registrar do que registrar errado.

tipo: "elogio" (satisfeito, sem ressalva) | "misto" (satisfeito mas com ressalva) | "reclamacao" (insatisfeito) | "neutro"

Responda APENAS com JSON, sem markdown:
{"tem_nota":true/false,"nota":0-10 ou null,"tipo":"...","reclamacao":"..." ou null,"resumo":"até 8 palavras","confianca":0-10}`;

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

    const obraId: string = body.obra_id;
    const texto: string = (body.texto || '').trim();
    const simular: boolean = body.simular === true;
    if (!obraId || !texto) return json({ erro: 'faltam dados' }, 400);

    // ---- lê a mensagem ----
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': C.anthropic_key, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: 'claude-haiku-4-5-20251001', max_tokens: 300, system: SISTEMA, messages: [{ role: 'user', content: texto }] })
    });
    if (!r.ok) return json({ acao: 'nada', motivo: 'ia indisponivel' });
    const d = await r.json();
    const bruto = (d.content || []).filter((c: any) => c.type === 'text').map((c: any) => c.text).join('');
    let p: any;
    try { p = JSON.parse(bruto.replace(/```json|```/g, '').trim()); }
    catch (_) { return json({ acao: 'nada', motivo: 'json invalido' }); }

    if (!p.tem_nota || p.nota == null) return json({ acao: 'nada', motivo: 'sem nota', leitura: p });
    if ((p.confianca ?? 0) < 7) return json({ acao: 'avisar_equipe', motivo: 'confianca baixa', leitura: p });

    // Decisão do Vitor (17/09): SER PROMOTOR JÁ LIBERA o convite do Google.
    // Antes exigia `nota >= 9 && elogio limpo`, e nota 10 com qualquer ressalva
    // junto ficava sem convite para sempre — o convite automático sai uma vez só.
    // As duas coisas agora são independentes: a ressalva continua acionando a
    // equipe, e deixou de calar o convite.
    const semRessalva = p.tipo === 'elogio';
    const pedeGoogle = p.nota >= 9;
    const avisaEquipe = !semRessalva || p.nota < 9;

    if (simular) return json({ acao: 'registrar', pede_google: pedeGoogle, avisa_equipe: avisaEquipe, leitura: p });

    // ---- não registra duas vezes ----
    const { data: existe } = await admin.from('nps').select('id').eq('obra_id', obraId).maybeSingle();
    if (existe) return json({ acao: 'nada', motivo: 'ja tinha nota' });

    const { data: obra } = await admin.from('obras')
      .select('id,cliente,whatsapp_grupo_id').eq('id', obraId).maybeSingle();
    if (!obra) return json({ erro: 'obra nao encontrada' }, 404);

    // ---- agenda o Google respeitando o horário ----
    const atraso = parseInt(C.google_atraso_minutos || '3', 10);
    const hMin = parseInt(C.google_hora_minima || '9', 10);
    const hMax = parseInt(C.google_hora_maxima || '21', 10);
    let quando: Date | null = null;
    if (pedeGoogle) {
      quando = new Date(Date.now() + atraso * 60000);
      const local = new Date(quando.getTime() - 3 * 3600000); // horário de Brasília
      const h = local.getUTCHours();
      if (h >= hMax) { local.setUTCDate(local.getUTCDate() + 1); local.setUTCHours(hMin, 5, 0, 0); quando = new Date(local.getTime() + 3 * 3600000); }
      else if (h < hMin) { local.setUTCHours(hMin, 5, 0, 0); quando = new Date(local.getTime() + 3 * 3600000); }
    }

    await admin.from('nps').insert({
      obra_id: obraId, nota: p.nota,
      comentario: texto.slice(0, 500),
      origem: 'whatsapp',
      agradecido_em: new Date().toISOString(),
      google_agendado_para: quando ? quando.toISOString() : null,
    });

    // ---- agradece na hora ----
    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    const primeiro = String(obra.cliente || '').split(' ')[0];
    let enviado = false;

    // O agradecimento continua seguindo a RESSALVA, não o convite: quem apontou
    // algo recebe "obrigado pela sinceridade", não a comemoração.
    if (ZI && ZT && ZC && obra.whatsapp_grupo_id) {
      const msg = semRessalva && p.nota >= 9
        ? `💚 *${primeiro}, nota ${p.nota}! Muito obrigado.*\n\nVou levar isso para a equipe que trabalhou na sua obra — eles vão ficar felizes. 🙏`
        : `💚 *${primeiro}, obrigado pela sinceridade.*\n\nAnotei sua nota ${p.nota} e o que você apontou. Vou passar para a equipe e alguém te procura por aqui. 🙏`;
      const rr = await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
        body: JSON.stringify({ phone: obra.whatsapp_grupo_id, message: msg })
      });
      enviado = rr.ok;
    }

    // ---- avisa a equipe quando tem ressalva ou nota baixa ----
    if (avisaEquipe) {
      try {
        await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/notificar-grupo`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') },
          body: JSON.stringify({ obra_id: obraId, titulo: 'NPS com ressalva',
            texto: `${obra.cliente} deu nota ${p.nota}. ${p.reclamacao || p.resumo || ''}` })
        });
      } catch (_) { /* nao bloqueia */ }
    }

    return json({ ok: true, nota: p.nota, tipo: p.tipo, agradecido: enviado,
                  avisou_equipe: avisaEquipe,
                  google_para: quando ? quando.toISOString() : null });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
