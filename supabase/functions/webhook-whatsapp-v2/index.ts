import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

const TRIVIAIS = ['ok', 'okay', 'blz', 'beleza', 'obrigado', 'obrigada', 'obg', 'vlw', 'valeu',
  'bom dia', 'boa tarde', 'boa noite', 'oi', 'ola', 'ta bom', 'tá bom',
  'perfeito', 'show', 'top', 'joia', 'jóia', '👍', '🙏', '❤️', '😊'];
const ASSINATURA = 'equipe polaris energia solar';

function achaUrl(o: any): string | null {
  if (!o || typeof o !== 'object') return null;
  const chaves = ['audioUrl', 'imageUrl', 'documentUrl', 'videoUrl', 'stickerUrl', 'url', 'fileUrl', 'link'];
  for (const k of chaves) {
    const v = o[k];
    if (typeof v === 'string' && v.startsWith('http')) return v;
  }
  return null;
}
function achaNum(o: any, chaves: string[]): number | null {
  if (!o) return null;
  for (const k of chaves) {
    const v = o[k];
    if (typeof v === 'number' && isFinite(v)) return Math.round(v);
    if (typeof v === 'string' && v.trim() !== '' && isFinite(Number(v))) return Math.round(Number(v));
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // solta a trava de mensagem repetida se a gravação falhar, para a Z-API poder
  // entregar de novo
  let soltarTrava: (() => Promise<unknown>) | null = null;
  try {
    const url = new URL(req.url);
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { data: tk } = await admin.from('config').select('valor').eq('chave', 'webhook_token').maybeSingle();
    if (!tk || url.searchParams.get('t') !== tk.valor) return json({ error: 'Não autorizado.' }, 403);

    const body = await req.json().catch(() => ({}));
    const grupo: string = body.phone || body.chatId || body.groupId || '';
    if (!grupo || !grupo.includes('-group')) return json({ ok: true, ignorado: 'não é grupo' });

    // Um grupo pode estar em mais de uma obra: a da visita do plano herda o grupo
    // do cliente, e a manutenção nova que "puxa o cadastro" também. Com duas, o
    // maybeSingle() direto em `obras` dava erro e a mensagem era descartada como
    // "grupo interno" — a Tays e o Júnior ficaram invisíveis de 26/09 e 02/10 a
    // 15/10. Quem escolhe a obra dona é o banco (obra_do_grupo).
    const { data: donaId } = await admin.rpc('obra_do_grupo', { p_grupo: grupo });
    const { data: obra } = donaId
      ? await admin.from('obras')
        .select('id, cliente, vendedor_id, iptu_avisado_em, iptu_respondido_em, optin_pedido_em, optin_em, optout_em, aceite_em, aceite_pedido_em, nps_enviado_em')
        .eq('id', donaId).maybeSingle()
      : { data: null };
    if (!obra) return json({ ok: true, ignorado: 'grupo interno' });

    let texto = '';
    let tipo = 'texto';
    let midiaUrl: string | null = null;
    let midiaMime: string | null = null;
    let midiaSeg: number | null = null;

    if (body.sticker) {
      tipo = 'figurinha'; texto = '[figurinha]';
      midiaUrl = achaUrl(body.sticker); midiaMime = body.sticker.mimeType || null;
    } else if (body.reaction) {
      tipo = 'reacao'; texto = '[reação ' + (body.reaction.value || body.reaction.emoji || '') + ']';
    } else if (body.text?.message) texto = body.text.message;
    else if (typeof body.text === 'string') texto = body.text;
    else if (body.message?.text) texto = body.message.text;
    else if (body.image) {
      tipo = 'imagem'; texto = body.image.caption || '[imagem]';
      midiaUrl = achaUrl(body.image); midiaMime = body.image.mimeType || null;
    } else if (body.document) {
      tipo = 'documento'; texto = body.document.caption || '[documento]';
      midiaUrl = achaUrl(body.document); midiaMime = body.document.mimeType || null;
    } else if (body.audio) {
      tipo = 'audio'; texto = '[áudio]';
      midiaUrl = achaUrl(body.audio); midiaMime = body.audio.mimeType || null;
      midiaSeg = achaNum(body.audio, ['seconds', 'duration', 'segundos']);
    } else if (body.video) {
      tipo = 'video'; texto = body.video.caption || '[vídeo]';
      midiaUrl = achaUrl(body.video); midiaMime = body.video.mimeType || null;
      midiaSeg = achaNum(body.video, ['seconds', 'duration']);
    }

    // Qualquer outro formato que a Z-API mande e a gente ainda não trate:
    // guarda o nome do campo em vez de gravar linha vazia.
    if (!texto.trim()) {
      const conhecidos = ['phone', 'chatId', 'groupId', 'messageId', 'id', 'fromMe', 'momment', 'status',
        'senderName', 'senderPhone', 'participantPhone', 'participantName', 'chatName', 'instanceId',
        'connectedPhone', 'type', 'isGroup', 'isNewsletter', 'waitingMessage', 'broadcast', 'referenceMessageId',
        'externalAdReply', 'forwarded', 'fromApi', 'photo', 'senderLid', 'participantLid'];
      const extra = Object.keys(body).filter((k) => !conhecidos.includes(k) && body[k] != null);
      texto = extra.length ? '[' + extra[0] + ']' : '[mensagem sem texto]';
      if (tipo === 'texto' && extra.length) tipo = 'outro';
    }

    const zapiId: string | null = body.messageId || body.id || null;
    const limpo = texto.trim();
    const remetenteFone = body.participantPhone || body.senderPhone || null;
    const remetenteNome = body.senderName || body.participantName || body.chatName || null;
    const midia = { midia_url: midiaUrl, midia_mime: midiaMime, midia_segundos: midiaSeg, zapi_message_id: zapiId };

    // A Z-API entrega de novo o mesmo recado (mesmo messageId, mesmo texto) segundos
    // depois, e o webhook gravava todas as cópias: "vou mandar pra minha nora" virou
    // três indicações. A trava é atômica no banco (webhook_ja_visto). Edição — mesmo
    // messageId com texto novo — continua entrando como antes.
    if (zapiId) {
      const { data: jaVisto, error: eVisto } = await admin.rpc('webhook_ja_visto', { p_id: zapiId, p_texto: limpo });
      if (!eVisto && jaVisto === true) return json({ ok: true, ignorado: 'repetida' });
      // async: o rpc() do supabase-js só tem then(), e o catch() de quem chama precisa de Promise
      if (!eVisto) soltarTrava = async () => { await admin.rpc('webhook_esquecer', { p_id: zapiId, p_texto: limpo }); };
    }

    const cfg = async (k: string, d: string) => {
      const { data } = await admin.from('config').select('valor').eq('chave', k).maybeSingle();
      return data?.valor ?? d;
    };

    // ===== Mensagem da nossa equipe? =====
    let daEquipe = false;
    let quemRespondeu: string | null = null;
    if (body.fromMe === true) { daEquipe = true; quemRespondeu = 'Sistema/Polaris'; }
    if (!daEquipe && remetenteFone) {
      const { data: membro } = await admin.rpc('equipe_por_fone', { p_fone: remetenteFone });
      if (membro?.id) { daEquipe = true; quemRespondeu = membro.nome; }
    }

    if (daEquipe) {
      const automatica = limpo.toLowerCase().includes(ASSINATURA);
      await admin.from('mensagens_recebidas').insert({
        obra_id: obra.id, grupo_id: grupo, remetente_nome: quemRespondeu,
        remetente_fone: remetenteFone, texto: limpo.slice(0, 2000), tipo,
        contexto: automatica ? 'automatica' : 'resposta_equipe',
        da_equipe: true, lida_em: new Date().toISOString(), metodo: 'equipe',
        nps_checada_em: new Date().toISOString(), ...midia,
      });
      let tratadas = 0;
      if (!automatica) {
        const { data: n } = await admin.rpc('tratar_por_resposta', {
          p_obra: obra.id, p_quem: quemRespondeu, p_ate: new Date().toISOString(),
        });
        tratadas = n || 0;
      }
      return json({ ok: true, da_equipe: true, por: quemRespondeu, tratadas });
    }

    // ===== Resposta ao pedido de autorização (prioridade) =====
    if (obra.optin_pedido_em && !obra.optin_em && !obra.optout_em) {
      const { data: res } = await admin.rpc('processar_resposta_optin', { p_obra: obra.id, p_texto: limpo });
      if (res?.acao === 'autorizado' || res?.acao === 'recusado') {
        await admin.from('mensagens_recebidas').insert({
          obra_id: obra.id, grupo_id: grupo, remetente_nome: remetenteNome,
          remetente_fone: remetenteFone, texto: limpo.slice(0, 2000), tipo,
          contexto: res.acao === 'autorizado' ? 'autorizacao' : 'sair',
          confianca: 9, metodo: 'optin', da_equipe: false,
          lida_em: new Date().toISOString(),
          nps_checada_em: new Date().toISOString(), ...midia,
        });
        return json({ ok: true, optin: res.acao });
      }
    }

    // ===== Confirmação do relatório (o "OK" vale como aceite) =====
    if (obra.aceite_pedido_em && !obra.aceite_em && limpo && tipo === 'texto') {
      const { data: m0, error: e0 } = await admin.from('mensagens_recebidas').insert({
        obra_id: obra.id, grupo_id: grupo, remetente_nome: remetenteNome,
        remetente_fone: remetenteFone, texto: limpo.slice(0, 2000), tipo,
        contexto: 'geral', metodo: 'aceite', da_equipe: false,
        nps_checada_em: new Date().toISOString(), ...midia,
      }).select('id').single();
      if (!e0 && m0) {
        const { data: ac } = await admin.rpc('processar_aceite_whatsapp', { p_msg: m0.id });
        if (ac?.aceite === true) {
          return json({ ok: true, aceite: true, obra: obra.cliente, por: remetenteNome });
        }
        await admin.from('mensagens_recebidas').delete().eq('id', m0.id);
      }
    }

    // ===== Resposta ao pedido de nota (NPS) =====
    let npsNota: number | null = null;
    if (obra.nps_enviado_em && limpo && tipo === 'texto') {
      const janela = parseInt(await cfg('nps_janela_dias', '10'), 10);
      const dias = (Date.now() - new Date(obra.nps_enviado_em).getTime()) / 86400000;
      if (dias >= 0 && dias <= janela && (await cfg('nps_auto_ativo', '0')) === '1') {
        const { data: jaTem } = await admin.from('nps').select('id').eq('obra_id', obra.id).maybeSingle();
        if (!jaTem) {
          try {
            const ct = await cfg('cron_token', '');
            const rn = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/nps-resposta`, {
              method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ token: ct, obra_id: obra.id, texto: limpo }),
            });
            const dn = await rn.json();
            if (dn?.ok && dn.nota != null) npsNota = dn.nota;
          } catch (_) { /* segue o fluxo normal */ }
        }
      }
    }
    if (npsNota != null) {
      await admin.from('mensagens_recebidas').insert({
        obra_id: obra.id, grupo_id: grupo, remetente_nome: remetenteNome,
        remetente_fone: remetenteFone, texto: limpo.slice(0, 2000), tipo,
        contexto: 'nps', confianca: 9, metodo: 'nps', resumo: 'nota ' + npsNota,
        da_equipe: false, lida_em: new Date().toISOString(),
        nps_checada_em: new Date().toISOString(), ...midia,
      });
      await admin.from('obras').update({ ultima_resposta_em: new Date().toISOString() }).eq('id', obra.id);
      return json({ ok: true, nps: npsNota, obra: obra.cliente });
    }

    // ===== Classificar =====
    const min = limpo.toLowerCase().replace(/[.!?…]/g, '').trim();
    let contexto = 'geral', metodo = 'trivial', confianca = 0;
    let nomeIndicado: string | null = null, foneIndicado: string | null = null, resumo: string | null = null;

    const minChars = parseInt(await cfg('ia_min_caracteres', '12'), 10);
    const iaAtiva = (await cfg('ia_classificacao_ativa', '0')) === '1';
    // figurinha, reação e afins nunca vão para a IA
    const semConteudo = tipo === 'figurinha' || tipo === 'reacao' || tipo === 'outro';
    const ehTrivial = semConteudo || TRIVIAIS.includes(min) || limpo.length < minChars;

    if (!ehTrivial) {
      if (iaAtiva) {
        try {
          const { data: k } = await admin.from('config').select('valor').eq('chave', 'anthropic_key').maybeSingle();
          if (k?.valor) {
            const { data: ex } = await admin.from('classificacoes_exemplo')
              .select('texto,contexto').order('criado_em', { ascending: false }).limit(25);
            const bloco = (ex || []).length
              ? '\n\nExemplos já corrigidos pela equipe:\n' + (ex || []).map((e: any) => `"${e.texto}" → ${e.contexto}`).join('\n') : '';
            const sistema = `Você classifica mensagens que clientes de uma empresa de energia solar (Polaris, interior de São Paulo) enviam no grupo de WhatsApp da obra.

Contextos: indicacao, iptu, tecnico, conta, reclamacao, elogio, sair, agendamento, geral.

- indicacao: indica alguém, menciona parente/amigo/vizinho interessado, passa contato de terceiro
- iptu: desconto de IPTU sustentável
- tecnico: problema no sistema, geração baixa, inversor, app, limpeza, infiltração
- conta: dúvida sobre conta de luz, compensação, fatura
- reclamacao: insatisfação, cobrança de retorno, ameaça de cancelamento
- elogio: agradecimento ou elogio relevante
- sair: pedido para parar de receber mensagens
- agendamento: remarcar, confirmar ou perguntar sobre data
- geral: sem ação necessária

No interior indicam de forma indireta ("minha irmã perguntou quanto custou o seu"). Isso é indicacao.${bloco}

Responda APENAS com JSON:
{"contexto":"...","confianca":0-10,"nome_indicado":null,"telefone_indicado":null,"resumo":"até 8 palavras"}`;
            const r = await fetch('https://api.anthropic.com/v1/messages', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'x-api-key': k.valor, 'anthropic-version': '2023-06-01' },
              body: JSON.stringify({ model: 'claude-haiku-4-5-20251001', max_tokens: 300, system: sistema, messages: [{ role: 'user', content: limpo }] }),
            });
            if (r.ok) {
              const d = await r.json();
              const bruto = (d.content || []).filter((c: any) => c.type === 'text').map((c: any) => c.text).join('');
              const p = JSON.parse(bruto.replace(/```json|```/g, '').trim());
              contexto = p.contexto || 'geral'; confianca = p.confianca ?? 0;
              nomeIndicado = p.nome_indicado || null; foneIndicado = p.telefone_indicado || null;
              resumo = p.resumo || null; metodo = 'ia';
            }
          }
        } catch (_) { /* fallback */ }
      }
      if (metodo !== 'ia') {
        const { data: cls } = await admin.rpc('classificar_mensagem', { p_texto: limpo, p_obra: obra.id });
        contexto = cls?.contexto || 'geral'; confianca = cls?.confianca ?? 0; metodo = 'palavras';
      }
    }

    if (contexto === 'sair') {
      await admin.rpc('registrar_optout', { p_obra: obra.id, p_origem: 'whatsapp' });
    }

    let deixaPendente = false;
    if (tipo === 'texto') deixaPendente = true;
    if (tipo === 'audio' && midiaUrl) deixaPendente = true;

    const { data: msg, error } = await admin.from('mensagens_recebidas').insert({
      obra_id: obra.id, grupo_id: grupo, remetente_nome: remetenteNome,
      remetente_fone: remetenteFone, texto: limpo.slice(0, 2000), tipo, contexto,
      confianca, metodo, resumo, nome_indicado: nomeIndicado, telefone_indicado: foneIndicado,
      da_equipe: false,
      nps_checada_em: deixaPendente ? null : new Date().toISOString(),
      ...midia,
    }).select('id').single();
    if (error) {
      if (soltarTrava) await soltarTrava().catch(() => {});
      return json({ error: error.message }, 500);
    }

    const upd: Record<string, unknown> = { ultima_resposta_em: new Date().toISOString() };
    if (contexto === 'iptu' && !obra.iptu_respondido_em) upd.iptu_respondido_em = new Date().toISOString();
    await admin.from('obras').update(upd).eq('id', obra.id);

    if (contexto === 'indicacao') {
      try {
        const { data: ct } = await admin.from('config').select('valor').eq('chave', 'cron_token').maybeSingle();
        await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/alerta-indicacao`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: ct?.valor, mensagem_id: msg.id }),
        });
      } catch (_) { /* não bloqueia */ }
    }

    return json({ ok: true, obra: obra.cliente, contexto, tipo, metodo, confianca });
  } catch (err) {
    if (soltarTrava) await soltarTrava().catch(() => {});
    return json({ error: 'Erro interno: ' + (err as Error).message }, 500);
  }
});
