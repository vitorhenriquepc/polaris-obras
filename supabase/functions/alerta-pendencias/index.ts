import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

const CTX: Record<string, string> = {
  indicacao: '🎁 indicação', iptu: '🏛️ IPTU', tecnico: '🔧 técnico',
  conta: '📄 conta de luz', reclamacao: '😠 reclamação', elogio: '💚 elogio',
  sair: '🚪 pediu para sair', agendamento: '📅 agendamento', geral: '💬 mensagem',
};
const NOME_BRINDE: Record<string, string> = { copo: 'copo térmico', fone: 'fone Bluetooth' };

// "#4791" quando tem contrato; obra de manutenção não tem, e imprimir
// "#null" seria pior do que não imprimir nada.
const tag = (c: string | null) => (c ? ` #${c}` : '');

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (!tk || body.token !== tk.valor) return json({ error: 'Não autorizado.' }, 403);

    const simular = body.simular === true;

    const { data: cfg } = await admin.from('config').select('valor').eq('chave', 'alerta_pendencias_ativo').maybeSingle();
    if (cfg?.valor !== '1' && !body.forcar && !simular) return json({ ok: true, enviado: false, motivo: 'desativado' });

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!simular && (!ZI || !ZT || !ZC)) return json({ error: 'Z-API não configurada.' }, 500);

    const { data: p } = await admin.rpc('pendencias_posvenda');
    if (!p) return json({ error: 'Sem dados.' }, 500);

    const resp = p.respostas || [];
    const ind = p.indicacoes_pendentes || [];
    const ger = p.geracao_faltando || [];
    const semNps = p.sem_nps_lista || [];
    const brindes = p.brindes_lista || [];
    const google = p.google_lista || [];

    const total = resp.length + ger.length + (p.sem_nps || 0)
      + (p.brindes_pendentes || 0) + (p.google_pendente || 0);

    if (total === 0 && (p.sem_aniversario || 0) === 0) {
      return json({ ok: true, enviado: false, motivo: 'nada pendente' });
    }

    let msg = `☀️ *Bom dia! Pendências do pós-venda*\n`;

    if (ind.length) {
      msg += `\n🎁 *${ind.length} ${ind.length > 1 ? 'indicações' : 'indicação'} aguardando retorno*\n`;
      ind.slice(0, 5).forEach((i: any) => {
        msg += `• ${i.cliente}${i.indicado ? ' → ' + i.indicado : ''} (há ${i.horas}h)\n`;
      });
    }

    const outras = resp.filter((r: any) => r.contexto !== 'indicacao');
    if (outras.length) {
      msg += `\n💬 *${outras.length} ${outras.length > 1 ? 'mensagens' : 'mensagem'} sem resposta*\n`;
      outras.slice(0, 6).forEach((r: any) => {
        msg += `• ${r.cliente} — ${CTX[r.contexto] || r.contexto} (há ${r.horas}h)\n`;
      });
      if (outras.length > 6) msg += `• ...e mais ${outras.length - 6}\n`;
    }

    if (ger.length) {
      msg += `\n⚡ *${ger.length} cliente${ger.length > 1 ? 's' : ''} sem geração registrada*\n`;
      msg += `_A devolutiva da conta não pode ser enviada sem isso._\n`;
      ger.slice(0, 5).forEach((g: any) => {
        msg += `• ${g.cliente} (${g.dias} dias de ativo)\n`;
      });
    }

    // O que faltava: promotor que deu 9 ou 10 e não avaliou no Google.
    // Com nome, porque numero sozinho nao diz em quem falar.
    if (google.length) {
      msg += `\n⭐ *${google.length} promotor${google.length > 1 ? 'es' : ''} sem avaliação no Google*\n`;
      google.slice(0, 6).forEach((g: any) => {
        msg += `• ${g.cliente}${tag(g.contrato)} — nota ${g.nota}, respondeu há ${g.dias} dia${g.dias === 1 ? '' : 's'}`;
        msg += g.ja_convidado ? ` (já recebeu o convite)\n` : ` (ainda sem convite)\n`;
      });
      if (google.length > 6) msg += `• ...e mais ${google.length - 6}\n`;
      msg += `_O convite automático sai uma vez só. Daqui em diante é no grupo, na mão._\n`;
    }

    if (brindes.length) {
      msg += `\n🎁 *${brindes.length} brinde${brindes.length > 1 ? 's' : ''} para entregar*\n`;
      brindes.slice(0, 6).forEach((b: any) => {
        msg += `• ${b.cliente}${tag(b.contrato)} — ${NOME_BRINDE[b.brinde] || b.brinde} · ${b.voucher}`;
        msg += b.avaliou ? ` ✅ já avaliou\n` : ` ⏳ ainda não avaliou no Google\n`;
      });
      if (brindes.length > 6) msg += `• ...e mais ${brindes.length - 6}\n`;
    }

    if (semNps.length) {
      msg += `\n📋 *${semNps.length} cliente${semNps.length > 1 ? 's' : ''} sem pesquisa respondida*\n`;
      semNps.slice(0, 6).forEach((s: any) => {
        msg += `• ${s.cliente}${tag(s.contrato)} — ativo há ${s.dias} dias\n`;
      });
      if (semNps.length > 6) msg += `• ...e mais ${semNps.length - 6}\n`;
    }

    if (p.sem_aniversario) msg += `\n🎂 *${p.sem_aniversario}* cliente${p.sem_aniversario > 1 ? 's' : ''} sem data de aniversário\n`;

    msg += `\n📊 https://obras.polarisenergiasolar.com/posvenda.html\n\n*Polaris — Pós-venda* ☀️`;

    const { data: r } = await admin.from('equipe')
      .select('nome, telefone').eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
    if (!r?.telefone) return json({ error: 'Sem responsável pelo pós-venda definido.' }, 500);

    // Simular nao envia nada: devolve a mensagem exata para conferir antes.
    if (simular) return json({ ok: true, simulado: true, para: r.nome, itens: total, mensagem: msg });

    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const env = await fetch(`${base}/send-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
      body: JSON.stringify({ phone: r.telefone, message: msg }),
    });

    return json({ ok: true, enviado: env.ok, para: r.nome, itens: total });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
