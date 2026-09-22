import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

    // regra 3.2: rotina em lote tem modo simular. Com simular = true nada e
    // gravado, nada e gerado e nada e enviado — so a previa do que aconteceria.
    const simular = body.simular === true;

    if ((C.marco_ativo || '0') !== '1' && !body.forcar && !simular) return json({ ok: true, desligado: true });

    const { data: novos, error } = await admin.rpc('marcos_novos');
    if (error) return json({ erro: error.message }, 500);
    const lista = (novos || []) as any[];
    if (!lista.length) return json({ ok: true, simular, marcos: 0 });

    const teto = parseInt(C.marco_max_por_rodada || '10', 10);
    const intervalo = parseInt(C.msg_ia_intervalo_dias || '20', 10);
    const desde = new Date(Date.now() - intervalo * 86400000).toISOString().slice(0, 10);

    const feitos: any[] = []; const pulados: any[] = []; const erros: any[] = [];

    for (const m of lista) {
      if (feitos.length >= teto) break;

      // so o marco mais alto de cada usina vira mensagem
      const maior = Math.max(...lista.filter((x) => x.usina_id === m.usina_id).map((x) => x.marco));
      if (m.marco !== maior) {
        if (!simular) {
          await admin.from('usina_marco').update({ avisado_em: new Date().toISOString() })
            .eq('usina_id', m.usina_id).eq('marco', m.marco);
        } else {
          pulados.push({ cliente: m.cliente, marco: m.marco,
                         motivo: `marco menor que ${maior}% — seria so carimbado como avisado` });
        }
        continue;
      }

      // descobre a obra e confere grupo, optout e mensagens recentes
      const { data: vinc } = await admin.from('obra_usina')
        .select('obra_id, obras!inner(whatsapp_grupo_id, optout_em)')
        .eq('usina_id', m.usina_id).eq('principal', true).maybeSingle();
      const o: any = vinc?.obras;
      if (!vinc || !o?.whatsapp_grupo_id || o?.optout_em) {
        pulados.push({ cliente: m.cliente, marco: m.marco, motivo: 'sem grupo ou pediu para sair' });
        continue;
      }

      const { data: recente } = await admin.from('regua_contatos')
        .select('id, modelo').eq('obra_id', vinc.obra_id)
        .in('modelo', ['usina_wifi', 'usina_parada', 'geracao_recorde', 'geracao_resumo', 'retorno_marco'])
        .gte('data_programada', desde).limit(1);
      if (recente?.length) {
        pulados.push({ cliente: m.cliente, marco: m.marco,
                       motivo: `ja teve ${recente[0].modelo} nos ultimos ${intervalo} dias` });
        continue;
      }

      if (simular) { feitos.push({ cliente: m.cliente, marco: m.marco, obra_id: vinc.obra_id }); continue; }

      try {
        const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/mensagem-gerar`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: C.cron_token, usina_id: m.usina_id, tipo: 'marco', marco: m.marco }),
        });
        const d = await r.json();
        if (d?.ok) feitos.push({ cliente: m.cliente, marco: m.marco });
        else pulados.push({ cliente: m.cliente, motivo: d?.erro || 'recusado' });
      } catch (e) {
        erros.push({ cliente: m.cliente, erro: String(e).slice(0, 80) });
      }
      await new Promise((s) => setTimeout(s, 500));
    }

    if (simular) {
      return json({ ok: true, simular: true, nada_gravado: true,
                    marcos_detectados: lista.length, geraria: feitos.length,
                    pularia: pulados.length, detalhe: { feitos, pulados: pulados.slice(0, 10) } });
    }

    if (feitos.length && (C.msg_ia_avisa || '1') === '1') {
      const ZI = (Deno.env.get('ZAPI_INSTANCE_ID') || '').trim();
      const ZT = (Deno.env.get('ZAPI_TOKEN') || Deno.env.get('ZAPI_INSTANCE_TOKEN') || '').trim();
      const ZC = (Deno.env.get('ZAPI_CLIENT_TOKEN') || '').trim();
      const { data: resp } = await admin.from('equipe').select('telefone')
        .eq('resp_posvenda', true).eq('ativo', true).maybeSingle();
      if (ZI && ZT && ZC && resp?.telefone) {
        const msg = `\u{1F4B0} *${feitos.length} cliente${feitos.length > 1 ? 's' : ''} bateu marco de retorno*\n\n`
          + feitos.map((f: any) => `• ${String(f.cliente).split(' ').slice(0, 2).join(' ')} — ${f.marco}%`).join('\n')
          + `\n\n_Abra o Pós-venda → Régua para ler e aprovar._`;
        await fetch(`https://api.z-api.io/instances/${ZI}/token/${ZT}/send-text`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Client-Token': ZC },
          body: JSON.stringify({ phone: resp.telefone, message: msg }),
        });
      }
    }

    return json({ ok: true, marcos_detectados: lista.length, mensagens: feitos.length,
                  pulados: pulados.length, detalhe: { feitos, pulados: pulados.slice(0, 6) },
                  erros: erros.slice(0, 3) });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
