import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
const BASE = 'https://obras.polarisenergiasolar.com';
const fmt = (d: string | null) => d ? String(d).split('-').reverse().join('/') : '—';

// O nome do serviço sai da TRILHA, nunca chumbado.
// Manutenção não é instalação: o cliente já tem o sistema, e mandar
// "sua instalação está agendada" numa preventiva é dizer a coisa errada.
function servicoDe(trilha: string, tipoManutencao: string | null) {
  if (trilha === 'manutencao') {
    const t = String(tipoManutencao || '').trim().toLowerCase();
    if (t === 'preventiva') return { cliente: 'manutenção preventiva', equipe: 'Manutenção preventiva' };
    if (t === 'corretiva') return { cliente: 'manutenção corretiva', equipe: 'Manutenção corretiva' };
    // 'diagnostico' é o terceiro valor que a tela grava, e o relatorio.html já
    // titula esse laudo de "Avaliação Técnica" — seguir o mesmo nome.
    if (t === 'diagnostico') return { cliente: 'avaliação técnica', equipe: 'Avaliação técnica' };
    return { cliente: 'visita técnica', equipe: 'Visita técnica' };
  }
  if (trilha === 'eletroposto') return { cliente: 'instalação do eletroposto', equipe: 'Obra' };
  return { cliente: 'instalação', equipe: 'Obra' };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const { obra_id, destinos } = body;
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Autorização: token do agendador OU usuário logado da equipe
    let autorizado = false;
    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
    if (tk && body.token && body.token === tk.valor) autorizado = true;
    if (!autorizado) {
      const authHeader = req.headers.get('Authorization') ?? '';
      if (authHeader) {
        const u = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
        const { data: ok } = await u.rpc('is_autorizado');
        autorizado = !!ok;
      }
    }
    if (!autorizado) return json({ error: 'Não autorizado.' }, 403);
    if (!obra_id) return json({ error: 'obra_id é obrigatório.' }, 400);

    const { data: o } = await admin.from('obras').select('*').eq('id', obra_id).maybeSingle();
    if (!o) return json({ error: 'Obra não encontrada.' }, 404);
    if (!o.data_instalacao) return json({ error: 'Esta obra não tem data agendada.' }, 400);

    const trilha = o.trilha || 'padrao';
    const ehManut = trilha === 'manutencao';
    const servico = servicoDe(trilha, o.tipo_manutencao);

    const { data: eq } = o.instalador_id
      ? await admin.from('equipe').select('nome,whatsapp_grupo_id').eq('id', o.instalador_id).maybeSingle()
      : { data: null };

    const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
    const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
    const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
    if (!ZI || !ZT || !ZC) return json({ error: 'Z-API não configurada.' }, 500);
    const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
    const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };

    const quais = destinos || 'ambos';
    const primeiro = String(o.cliente || '').split(' ')[0];
    const maps = o.endereco ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(o.endereco)}` : '';
    let cliente_ok = false, equipe_ok = false;

    // ---- CLIENTE ----
    if ((quais === 'ambos' || quais === 'cliente') && o.whatsapp_grupo_id) {
      const fecho = ehManut
        ? `No dia, a equipe precisa de acesso ao inversor e ao telhado. Se puder deixar o caminho livre, ajuda bastante. 😉\n\n`
        : `Um dia antes enviamos um lembrete com tudo que precisa ficar liberado no local. 😉\n\n`;
      const msg = `${ehManut ? '🔧' : '📅'} *${primeiro}, sua ${servico.cliente} está agendada!*\n\n` +
        `Data: *${fmt(o.data_instalacao)}*\n` +
        (o.endereco ? `📍 Local: ${o.endereco}\n` : '') +
        (eq?.nome ? `👷 Equipe: ${eq.nome}\n` : '') +
        `\n${fecho}` +
        `Se essa data não for boa para você, é só nos avisar por aqui.\n\n*Equipe Polaris Energia Solar* ☀️`;
      const r = await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: o.whatsapp_grupo_id, message: msg }) });
      cliente_ok = r.ok;
      await new Promise((res) => setTimeout(res, 800));
    }

    // ---- EQUIPE INSTALADORA ----
    if ((quais === 'ambos' || quais === 'equipe') && eq?.whatsapp_grupo_id) {
      // Estrutura e cabo são perguntas de OBRA NOVA — o que a equipe leva no
      // caminhão. Em manutenção o sistema já está no telhado, e os dois campos
      // saem como "❌ Sem" porque ninguém preencheu, não porque falta material.
      // Ficha de manutenção: só o que serve para a visita.
      const ficha = (ehManut
        ? [
            o.potencia_kwp
              ? `⚡ ${String(o.potencia_kwp).replace('.', ',')} kWp${o.qtd_modulos ? ` · ${o.qtd_modulos} módulos` : ''}`
              : (o.qtd_modulos ? `🔋 ${o.qtd_modulos} módulos` : null),
            o.inversor_descricao ? `🔌 ${o.inversor_descricao}` : null,
            o.tipo_telhado ? `🏠 Telhado: ${o.tipo_telhado}` : null,
            // `motivo_manutencao` tem destino declarado: nasceu para ir daqui
            // ao grupo do instalador. `observacoes` NUNCA entra — e campo
            // livre e carrega nota comercial ("Proposta: R$ 15.600,00" na
            // obra 4599); mandar de la vazaria preco.
            o.motivo_manutencao ? `📝 Relato: ${o.motivo_manutencao}` : null,
          ]
        : [
            o.potencia_kwp ? `⚡ ${String(o.potencia_kwp).replace('.', ',')} kWp` : null,
            o.qtd_modulos ? `🔋 ${o.qtd_modulos} módulos${o.modelo_modulo ? ' · ' + o.modelo_modulo : ''}` : null,
            o.inversor_descricao ? `🔌 ${o.inversor_descricao}` : null,
            o.tipo_telhado ? `🏠 Telhado: ${o.tipo_telhado}` : null,
            [o.tem_estrutura === true ? '✅ Com estrutura' : (o.tem_estrutura === false ? '❌ Sem estrutura' : null),
             o.tem_cabo === true ? '✅ Com cabo' : (o.tem_cabo === false ? '❌ Sem cabo' : null)].filter(Boolean).join(' · ') || null,
          ]
      ).filter(Boolean).join('\n');

      const titulo = ehManut ? `${servico.equipe} agendada para vocês!` : 'Obra agendada para vocês!';
      const rotuloFicha = ehManut ? 'O sistema' : 'Ficha técnica';
      const rotuloLink = ehManut ? 'Checklist da manutenção' : 'Checklist de fotos da obra';

      const msg = `🔧 *${titulo}*\n\n` +
        `👤 Cliente: *${o.cliente}*${o.contrato ? ` · #${o.contrato}` : ''}\n` +
        `📅 Data: *${fmt(o.data_instalacao)}*\n` +
        (o.endereco ? `📍 ${o.endereco}\n` : '') +
        (maps ? `🗺️ ${maps}\n` : '') +
        (ficha ? `\n*${rotuloFicha}*\n${ficha}\n` : '') +
        `\n📋 ${rotuloLink}:\n${BASE}/instalador.html?id=${o.slug}&t=${o.instalador_token}\n\n` +
        `Qualquer dúvida, é só chamar. 💪\n\n*Polaris Energia Solar* ☀️`;
      const r = await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: eq.whatsapp_grupo_id, message: msg }) });
      equipe_ok = r.ok;
    }

    return json({
      ok: true, cliente: o.cliente, data: o.data_instalacao,
      trilha, servico: servico.cliente,
      enviado_cliente: cliente_ok, enviado_equipe: equipe_ok,
      equipe: eq?.nome || null,
    });
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
