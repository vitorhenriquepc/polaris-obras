import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
const BASE_URL = 'https://obras.polarisenergiasolar.com';

// Se o endereço contém coordenada, o link usa só os números.
// Texto junto (ex: "Fazenda solar") quebra o Google Maps.
function linkMaps(endereco?: string | null): string {
  if (!endereco) return '';
  const coord = String(endereco).match(/-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+/);
  const q = coord ? coord[0].replace(/\s+/g, '') : String(endereco);
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}
// Nome legível do local: sem os números da coordenada
function localLegivel(endereco?: string | null): string {
  if (!endereco) return '';
  const limpo = String(endereco)
    .replace(/-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+/, '')
    .replace(/[()]/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
    .replace(/^[-,·\s]+|[-,·\s]+$/g, '');
  return limpo || String(endereco);
}
// Sem grupo, o lembrete vai para o telefone da obra -- que é gravado sem o 55
// (18999999999). A Z-API precisa do DDI; os telefones da equipe, que recebem
// todo dia, estão todos com 55 (05/10). Manutenção muitas vezes não tem grupo.
function com55(tel?: string | null): string {
  const d = String(tel || '').replace(/\D/g, '');
  if (d.length < 10) return '';
  return d.length <= 11 && !d.startsWith('55') ? '55' + d : d;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const { token } = await req.json().catch(() => ({}));
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (!tk || !token || token !== tk.valor) return json({ error: 'Não autorizado.' }, 403);

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZI || !ZT || !ZC) return json({ error: 'Z-API não configurada.' }, 500);

    const { data: obras } = await admin.rpc('obras_para_lembrete');
    if (!obras || !obras.length) return json({ ok: true, clientes: 0, equipes: 0 });

    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };
    const fmt = (d: string) => String(d).split('-').reverse().join('/');

    const TIPO: Record<string, string> = {
      preventiva: 'manutenção preventiva',
      corretiva: 'visita técnica',
      diagnostico: 'avaliação do sistema',
    };

    let clientes = 0;
    for (const o of obras) {
      const destino = o.whatsapp_grupo_id || com55(o.telefone);
      if (!destino) continue;
      const primeiro = String(o.cliente || '').split(' ')[0];
      const manut = o.trilha === 'manutencao';
      const equipe = o.instalador || 'Polaris Energia Solar';
      const local = localLegivel(o.endereco);
      const maps = linkMaps(o.endereco);
      let msg = '';

      if (manut && o.tipo_manutencao === 'corretiva') {
        msg = `🔧 *${primeiro}, nossa visita técnica é amanhã!*\n\n` +
          `📅 Data: *${fmt(o.data_instalacao)}*\n👷 Equipe: ${equipe}\n`;
        if (local) msg += `📍 Local: ${local}\n`;
        msg += `\nSó precisamos que alguém esteja no local para *liberar o acesso* — telhado, inversor e quadro de energia.\n\n` +
          `✅ *Uma ajuda:* se o problema mudou ou parou de acontecer, avise por aqui antes da visita. ` +
          `Isso pode poupar uma viagem e ajuda a equipe a chegar preparada.\n\n` +
          `Vamos identificar a causa e resolver na hora sempre que possível. Se precisar de alguma peça, ` +
          `enviamos o orçamento antes de qualquer troca — nada é feito sem sua aprovação.\n\n` +
          `Ao final você recebe o *relatório com fotos e laudo* do que foi encontrado.\n\n` +
          `Até amanhã! ☀️\n\n*Equipe Polaris Energia Solar*`;

      } else if (manut && o.tipo_manutencao === 'diagnostico') {
        msg = `🔎 *${primeiro}, sua avaliação técnica é amanhã!*\n\n` +
          `📅 Data: *${fmt(o.data_instalacao)}*\n👷 Equipe: ${equipe}\n`;
        if (local) msg += `📍 Local: ${local}\n`;
        msg += `\nSó precisamos que alguém esteja no local para *liberar o acesso* — telhado, inversor e quadro de energia.\n\n` +
          `📄 Se tiver em mãos, separe uma *conta de luz recente*. Ela ajuda a comparar o que o sistema deveria estar gerando.\n\n` +
          `Ao final você recebe um *laudo com fotos* e, se houver algo a corrigir, um orçamento sem compromisso.\n\n` +
          `Até amanhã! ☀️\n\n*Equipe Polaris Energia Solar*`;

      } else if (manut) {
        const nomeServ = TIPO[o.tipo_manutencao] || 'visita técnica';
        msg = `🧽 *${primeiro}, sua ${nomeServ} é amanhã!*\n\n` +
          `📅 Data: *${fmt(o.data_instalacao)}*\n👷 Equipe: ${equipe}\n`;
        if (local) msg += `📍 Local: ${local}\n`;
        msg += `\n*Para agilizar, deixe liberado:*\n` +
          `• Acesso ao telhado, inversor e quadro de energia\n` +
          `• Um ponto de água, se possível (usamos na limpeza) 💧\n\n` +
          `Ao final, enviamos um *relatório com fotos e laudo* do que foi verificado.\n\n` +
          `Se precisar remarcar, é só avisar por aqui. Até amanhã! ☀️\n\n*Equipe Polaris Energia Solar*`;

      } else {
        msg = `🔧 *${primeiro}, sua instalação é amanhã!*\n\n` +
          `📅 Data: *${fmt(o.data_instalacao)}*\n👷 Equipe: ${equipe}\n`;
        if (local) msg += `📍 Local: ${local}\n`;
        msg += `\n*Para agilizar, deixe liberado:*\n` +
          `• Acesso ao telhado e ao quadro de energia\n` +
          `• Um ponto de tomada próximo\n` +
          `• A senha do Wi-Fi (usamos para conectar o monitoramento) 📶\n\n` +
          `Se precisar remarcar, é só nos avisar por aqui. Até amanhã! ☀️\n\n*Equipe Polaris Energia Solar*`;
      }

      const r = await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: destino, message: msg }) });
      if (r.ok) {
        clientes++;
        await admin.from('obras').update({ instalacao_lembrete_em: o.data_instalacao }).eq('id', o.id);
      }
      await new Promise((res) => setTimeout(res, 1000));
    }

    const porEquipe = new Map<string, any[]>();
    for (const o of obras) {
      if (!o.instalador_grupo) continue;
      const arr = porEquipe.get(o.instalador_grupo) || [];
      arr.push(o);
      porEquipe.set(o.instalador_grupo, arr);
    }

    let equipes = 0;
    for (const [grupo, lista] of porEquipe) {
      const nome = lista[0].instalador || 'equipe';
      const dia = fmt(lista[0].data_instalacao);
      let msg = `📅 *Agenda de amanhã — ${dia}*\n\n` +
        `${nome}, vocês têm *${lista.length} serviço${lista.length > 1 ? 's' : ''}* programado${lista.length > 1 ? 's' : ''}:\n`;
      lista.forEach((o: any, i: number) => {
        const maps = linkMaps(o.endereco);
        const local = localLegivel(o.endereco);
        const tag = o.trilha === 'manutencao' ? ` — _${(TIPO[o.tipo_manutencao] || 'visita técnica').toUpperCase()}_` : '';
        msg += `\n*${i + 1}. ${o.cliente}*${o.contrato ? ` · #${o.contrato}` : ''}${tag}\n`;
        if (o.potencia_kwp) msg += `⚡ ${String(o.potencia_kwp).replace('.', ',')} kWp\n`;
        if (local) msg += `📍 ${local}\n`;
        if (maps) msg += `🗺️ ${maps}\n`;
        msg += `📋 ${BASE_URL}/instalador.html?id=${o.slug}&t=${o.instalador_token}\n`;
      });
      msg += `\nBom trabalho, pessoal! 💪\n\n*Polaris Energia Solar* ☀️`;

      const r = await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: grupo, message: msg }) });
      if (r.ok) equipes++;
      await new Promise((res) => setTimeout(res, 1000));
    }

    return json({ ok: true, clientes, equipes });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
