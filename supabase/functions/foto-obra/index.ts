import { createClient } from '@supabase/supabase-js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

// Até 17/09 aqui havia `const ETAPA_POS_INSTALACAO = 7`, chumbado. Na trilha
// `manutencao`, que vai só até a etapa 4, o trg_valida_etapa clampava o 7 para
// 4 em SILÊNCIO — e a mensagem, que buscava a etapa 7 *da trilha da obra*, não
// achava nada e saía com o nome vazio: "Sua obra avançou para a etapa *.*".
// Aconteceu com a Fatima Rino (3067) em 17/09. Agora o destino sai da trilha.
const ETAPA_POS_EXECUCAO = 7;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json();
    const { acao, slug, token } = body;
    if (!acao || !slug || !token) return json({ error: 'Parâmetros incompletos.' }, 400);

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: obra } = await admin.from('obras').select('*').eq('slug', slug).eq('instalador_token', token).maybeSingle();
    if (!obra) return json({ error: 'Link inválido ou expirado.' }, 403);

    if (acao === 'upload') {
      const { item_id, foto_base64, mime, apontamento_id } = body;
      if (!foto_base64) return json({ error: 'Foto faltando.' }, 400);
      const bytes = Uint8Array.from(atob(foto_base64), (c) => c.charCodeAt(0));
      if (bytes.length > 9_000_000) return json({ error: 'Foto muito grande (máx 9MB).' }, 400);
      const ext = (mime || 'image/jpeg').includes('png') ? 'png' : 'jpg';
      const path = `${obra.id}/item${item_id || 'ap'}-${Date.now()}.${ext}`;
      const { error: eUp } = await admin.storage.from('fotos-obras').upload(path, bytes, { contentType: mime || 'image/jpeg' });
      if (eUp) return json({ error: 'Erro no upload: ' + eUp.message }, 500);
      const { data: pub } = admin.storage.from('fotos-obras').getPublicUrl(path);
      const { data: foto, error: eIns } = await admin.from('fotos').insert({
        obra_id: obra.id, item_id: item_id || null, url: pub.publicUrl,
        etapa_numero: obra.etapa_numero, tipo: 'foto', apontamento_id: apontamento_id || null,
      }).select().single();
      if (eIns) return json({ error: 'Erro ao registrar: ' + eIns.message }, 500);
      return json({ ok: true, foto: { id: foto.id, item_id: foto.item_id, url: pub.publicUrl, tipo: 'foto', apontamento_id: foto.apontamento_id } });
    }

    if (acao === 'video-url') {
      const e = (body.ext || 'mp4').replace(/[^a-z0-9]/gi, '').slice(0, 5) || 'mp4';
      const path = `${obra.id}/video-${Date.now()}.${e}`;
      const { data, error } = await admin.storage.from('fotos-obras').createSignedUploadUrl(path);
      if (error) return json({ error: 'Erro ao preparar envio: ' + error.message }, 500);
      return json({ ok: true, path, token: data.token, signedUrl: data.signedUrl });
    }

    if (acao === 'video-registrar') {
      const { path, item_id, apontamento_id } = body;
      if (!path || !String(path).startsWith(`${obra.id}/`)) return json({ error: 'Caminho inválido.' }, 400);
      const { data: pub } = admin.storage.from('fotos-obras').getPublicUrl(path);
      const { data: mid, error } = await admin.from('fotos').insert({
        obra_id: obra.id, item_id: item_id || null, url: pub.publicUrl,
        etapa_numero: obra.etapa_numero, tipo: 'video', apontamento_id: apontamento_id || null,
      }).select().single();
      if (error) return json({ error: 'Erro ao registrar vídeo: ' + error.message }, 500);
      return json({ ok: true, foto: { id: mid.id, item_id: mid.item_id, url: pub.publicUrl, tipo: 'video', apontamento_id: mid.apontamento_id } });
    }

    if (acao === 'apontamento-criar') {
      const { descricao } = body;
      if (!descricao || !String(descricao).trim()) return json({ error: 'Descreva o apontamento.' }, 400);
      const { data, error } = await admin.from('apontamentos').insert({ obra_id: obra.id, descricao: String(descricao).trim() }).select().single();
      if (error) return json({ error: 'Erro ao salvar: ' + error.message }, 500);
      return json({ ok: true, apontamento: data });
    }
    if (acao === 'apontamento-excluir') {
      const { apontamento_id } = body;
      const { data: ap } = await admin.from('apontamentos').select('id').eq('id', apontamento_id).eq('obra_id', obra.id).maybeSingle();
      if (!ap) return json({ error: 'Apontamento não encontrado.' }, 404);
      const { data: mids } = await admin.from('fotos').select('url').eq('apontamento_id', apontamento_id);
      const marker = '/fotos-obras/';
      const paths = (mids || []).map((m: any) => { const i = m.url.indexOf(marker); return i > -1 ? decodeURIComponent(m.url.substring(i + marker.length)) : null; }).filter(Boolean) as string[];
      if (paths.length) await admin.storage.from('fotos-obras').remove(paths);
      await admin.from('apontamentos').delete().eq('id', apontamento_id);
      return json({ ok: true });
    }

    if (acao === 'excluir') {
      const { foto_id } = body;
      const { data: foto } = await admin.from('fotos').select('*').eq('id', foto_id).eq('obra_id', obra.id).maybeSingle();
      if (!foto) return json({ error: 'Arquivo não encontrado.' }, 404);
      const marker = '/fotos-obras/';
      const idx = foto.url.indexOf(marker);
      if (idx > -1) await admin.storage.from('fotos-obras').remove([decodeURIComponent(foto.url.substring(idx + marker.length))]);
      await admin.from('fotos').delete().eq('id', foto_id);
      return json({ ok: true });
    }

    // ---------- TERMO DE ACEITE (com opt-in LGPD) ----------
    if (acao === 'aceite') {
      const { assinatura_base64, nome, documento, optin } = body;
      if (!assinatura_base64 || !nome) return json({ error: 'Assinatura e nome são obrigatórios.' }, 400);
      const bytes = Uint8Array.from(atob(assinatura_base64), (c) => c.charCodeAt(0));
      const path = `${obra.id}/assinatura-${Date.now()}.png`;
      const { error: eUp } = await admin.storage.from('fotos-obras').upload(path, bytes, { contentType: 'image/png' });
      if (eUp) return json({ error: 'Erro ao salvar assinatura: ' + eUp.message }, 500);
      const { data: pub } = admin.storage.from('fotos-obras').getPublicUrl(path);

      const agora = new Date().toISOString();
      const upd: Record<string, unknown> = {
        aceite_assinatura: pub.publicUrl, aceite_nome: nome,
        aceite_documento: documento || null, aceite_em: agora,
      };

      // Consentimento LGPD — só registra se o cliente marcou
      let consentiu = false;
      if (optin === true) {
        const { data: txt } = await admin.from('config').select('valor').eq('chave', 'optin_texto').maybeSingle();
        upd.optin_em = agora;
        upd.optin_texto = txt?.valor || null;
        upd.optin_origem = 'termo';
        upd.optout_em = null;
        upd.optout_origem = null;
        consentiu = true;
        await admin.from('consentimentos').insert({
          obra_id: obra.id, acao: 'optin', texto: txt?.valor || null,
          origem: 'termo', nome, documento: documento || null,
        });
      }

      await admin.from('obras').update(upd).eq('id', obra.id);

      if (obra.whatsapp_grupo_id) {
        const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
        const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
        const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
        if (ZI && ZT && ZC) {
          const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
          const hoje = new Date().toLocaleDateString('pt-BR');
          const linkRel = `https://obras.polarisenergiasolar.com/relatorio.html?id=${obra.slug}`;
          // o termo também segue a trilha: numa manutenção não se conclui instalação
          const oQue = (obra.trilha === 'manutencao') ? 'o atendimento' : 'a instalação';
          await fetch(`${base}/send-text`, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
            body: JSON.stringify({ phone: obra.whatsapp_grupo_id,
              message: `✅ *Termo de conclusão assinado!*\n\nRecebemos o aceite de *${nome}* em ${hoje}, confirmando a conclusão d${oQue}. 🎉\n\n📄 O termo assinado já consta no relatório oficial da obra:\n${linkRel}\n\nObrigado pela confiança! ☀️\n\n*Equipe Polaris Energia Solar*` }),
          });
        }
      }
      return json({ ok: true, optin: consentiu });
    }

    // ---------- ENVIAR RELATÓRIO ----------
    if (acao === 'enviar') {
      if (!obra.whatsapp_grupo_id) return json({ error: 'Esta obra ainda não tem grupo de WhatsApp. Peça ao escritório para criar pelo painel.' }, 400);
      const force = body.force === true;

      if (!force) {
        const { data: lock } = await admin.from('obras')
          .update({ relatorio_enviado_em: new Date().toISOString() })
          .eq('id', obra.id).is('relatorio_enviado_em', null).select('id');
        if (!lock || !lock.length) {
          return json({ ja_enviado: true, enviado_em: obra.relatorio_enviado_em, error: 'O relatório desta obra já foi enviado no grupo.' }, 409);
        }
      } else {
        await admin.from('obras').update({ relatorio_enviado_em: new Date().toISOString() }).eq('id', obra.id);
      }

      const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
      const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
      const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
      if (!ZI || !ZT || !ZC) {
        if (!force) await admin.from('obras').update({ relatorio_enviado_em: null }).eq('id', obra.id);
        return json({ error: 'Z-API não configurada.' }, 500);
      }

      const { data: fotos } = await admin.from('fotos').select('*, checklist_itens(titulo)').eq('obra_id', obra.id).order('item_id').order('criado_em');
      if (!fotos || !fotos.length) {
        if (!force) await admin.from('obras').update({ relatorio_enviado_em: null }).eq('id', obra.id);
        return json({ error: 'Nenhuma foto enviada ainda.' }, 400);
      }

      const trilha = obra.trilha || 'padrao';
      const ehManut = trilha === 'manutencao';
      const elet = trilha === 'eletroposto';

      // O texto segue a TRILHA, como o relatorio.html já faz. Antes toda obra
      // recebia texto de instalação -- inclusive uma manutenção preventiva.
      const Servico = ehManut ? 'Manutenção' : 'Instalação';
      const servico = ehManut ? 'manutenção' : 'instalação';
      const abriu = ehManut ? '🔧' : '☀️';
      const fezOQue = ehManut
        ? 'Nossa equipe concluiu a manutenção do seu sistema! Veja os principais registros: 👇'
        : 'Nossa equipe finalizou a instalação do seu sistema! Veja os principais registros: 👇';

      const imagens = fotos.filter((f: any) => f.tipo !== 'video');
      const nVid = fotos.length - imagens.length;
      // os ids de destaque são da checklist de instalação; a manutenção tem a
      // dela, então ali vale o começo da sequência mesmo
      const idsDestaque = elet ? [24, 30] : [3, 5];
      let destaque = ehManut ? [] : imagens.filter((f: any) => idsDestaque.includes(f.item_id));
      if (!destaque.length) destaque = imagens.slice(0, 3);
      destaque = destaque.slice(0, 8);

      const base = `https://api.z-api.io/instances/${ZI}/token/${ZT}`;
      const zH = { 'Content-Type': 'application/json', 'Client-Token': ZC };
      const gid = obra.whatsapp_grupo_id;
      const linkRel = `https://obras.polarisenergiasolar.com/relatorio.html?id=${obra.slug}`;
      const linkCli = `https://obras.polarisenergiasolar.com/cliente.html?id=${obra.slug}`;

      await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({
        phone: gid,
        message: `${abriu} *${Servico} concluída — ${obra.cliente}*${obra.contrato ? ' #' + obra.contrato : ''}\n\n${fezOQue}`,
      })});

      let enviadas = 0;
      for (const f of destaque) {
        const cap = f.checklist_itens?.titulo || '';
        const r = await fetch(`${base}/send-image`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: gid, image: f.url, caption: cap }) });
        if (r.ok) enviadas++;
        await new Promise((res) => setTimeout(res, 900));
      }

      // A etapa de destino sai da TRILHA: 7 na padrão ("Vistoria e Conexão") e
      // no eletroposto ("Comissionamento"), 4 na manutenção ("Concluída").
      // Com o número chumbado o banco clampava e o nome da etapa saía vazio.
      const { data: etapasTrilha } = await admin.from('etapas')
        .select('numero,nome,icone,prazo_texto').eq('trilha', trilha).order('numero');
      const maxEtapa = (etapasTrilha || []).reduce((m: number, e: any) => Math.max(m, e.numero), 0);
      const etapaDestino = maxEtapa ? Math.min(ETAPA_POS_EXECUCAO, maxEtapa) : ETAPA_POS_EXECUCAO;

      let avancou = false; let proxNome = ''; let proxPrazo = '';
      if (obra.etapa_numero < etapaDestino) {
        const { error: eEt } = await admin.from('obras').update({ etapa_numero: etapaDestino }).eq('id', obra.id);
        if (!eEt) {
          avancou = true;
          const et = (etapasTrilha || []).find((e: any) => e.numero === etapaDestino);
          proxNome = `${et?.icone || ''} ${(et?.nome || '').replace('!', '')}`.trim();
          proxPrazo = et?.prazo_texto || '';
        }
      }

      let msgFinal = `📄 *Relatório oficial da ${servico}*\n\nPreparamos um relatório completo com ${imagens.length} fotos${nVid ? ` e ${nVid} vídeo${nVid > 1 ? 's' : ''}` : ''}, os dados técnicos e o termo de conclusão:\n\n🔗 ${linkRel}\n\nToque nas fotos do relatório para vê-las em tela cheia. 📱`;
      // só anuncia a etapa se ela tiver nome -- sem nome a frase fica "avançou
      // para a etapa *.*", que foi o que o cliente leu em 17/09
      if (avancou && proxNome) {
        msgFinal += `\n\n✅ Sua obra avançou para a etapa *${proxNome}*.`;
        if (proxPrazo) msgFinal += `\n⏱️ ${proxPrazo}`;
        msgFinal += `\n\nAcompanhe em tempo real:\n${linkCli}`;
      }
      msgFinal += `\n\n*Equipe Polaris Energia Solar* ☀️`;
      await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: gid, message: msgFinal }) });

      let avisoParceiro = false;
      const { data: info } = await admin.rpc('obra_para_instalador_grupo', { p_obra: obra.id });
      if (info?.instalador_grupo) {
        const fmtData = (d: string | null) => d ? String(d).split('-').reverse().join('/') : '—';
        const ficha = [
          `👤 Cliente: *${obra.cliente}*${obra.contrato ? ` · #${obra.contrato}` : ''}`,
          obra.endereco ? `📍 ${obra.endereco}` : null,
          obra.potencia_kwp ? `⚡ ${String(obra.potencia_kwp).replace('.', ',')} kWp` : null,
          obra.qtd_modulos ? `🔋 ${obra.qtd_modulos} módulos${obra.modelo_modulo ? ' · ' + obra.modelo_modulo : ''}` : null,
          obra.inversor_descricao ? `🔌 ${obra.inversor_descricao}` : null,
          obra.data_instalacao ? `📅 ${ehManut ? 'Atendimento' : 'Instalação'}: ${fmtData(obra.data_instalacao)}` : null,
        ].filter(Boolean).join('\n');
        const msgP = `✅ *Checklist concluído — obra registrada*\n\n${ficha}\n\n📸 ${imagens.length} foto${imagens.length > 1 ? 's' : ''}${nVid ? ` e ${nVid} vídeo${nVid > 1 ? 's' : ''}` : ''} no relatório\n📄 Relatório completo:\n${linkRel}\n\nO relatório foi enviado ao cliente. Valeu pelo trabalho, equipe! 💪\n\n*Polaris Energia Solar* ☀️`;
        const rp = await fetch(`${base}/send-text`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: info.instalador_grupo, message: msgP }) });
        avisoParceiro = rp.ok;
        for (const f of destaque.slice(0, 4)) {
          await fetch(`${base}/send-image`, { method: 'POST', headers: zH, body: JSON.stringify({ phone: info.instalador_grupo, image: f.url, caption: f.checklist_itens?.titulo || '' }) });
          await new Promise((res) => setTimeout(res, 900));
        }
      }

      return json({ ok: true, enviadas, total_fotos: imagens.length, videos: nVid, trilha, etapa_destino: etapaDestino, etapa_avancada: avancou, etapa_nome: proxNome, aviso_parceiro: avisoParceiro });
    }

    return json({ error: 'Ação desconhecida.' }, 400);
  } catch (err) {
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
