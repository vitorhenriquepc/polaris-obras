-- 28/09/2026 — Valdecir estava DESLIGADO, não só sem Wi-Fi; e a saúde aprende
-- a separar "desligado" de "sem comunicação" pelo que o SolarView diz.
--
-- O que aconteceu
--   VALDECIR RICOBONI (Atual Noivas, 30,25 kWp): zero de 22 a 27/09. Em 26/09
--   foi anotado Wi-Fi (usinas.causa = 'wifi') e a mensagem 598 saiu em 28/09
--   17h pedindo ao cliente para conferir a internet. Em 28/09 o Vitor foi ao
--   local: o sistema estava DESLIGADO. Religou à tarde; o SolarView registrou
--   0,25 kWh no fim do dia. Os zeros de 22–27/09 são geração que não
--   aconteceu — nenhum dia "volta" com a memória do datalogger.
--
--   O sinal estava lá o tempo todo: o SolarView dizia "operando" (falava com o
--   inversor) e a geração era zero em dia de sol. A anotação de Wi-Fi passou
--   por cima disso e a saúde mostrou "sem comunicação" em vez de crítico.
--   É a armadilha 19 de novo: palpite humano vencendo evidência.

-- Registro corrigido, sem apagar o palpite antigo (regra 3.6):
update usinas
   set causa = 'outro',
       causa_nota = 'Sistema DESLIGADO desde 22/09 (não era só Wi-Fi). Vitor foi ao local e religou em 28/09 à tarde; SolarView registrou 0,25 kWh no fim do dia. Os zeros de 22 a 27/09 são geração que não aconteceu, não medição perdida. | Antes (26/09): ' || causa_nota,
       causa_em = now(),
       causa_por = 'vitorcarvalho@polarisenergiasolar.com'
 where id = '54ecb8d6-7015-4e9d-a9fa-56839798ffb5' and causa = 'wifi';

-- ─────────────────────────────────────────────────────────────────────────────
-- usinas_saude_calc: duas trocas (migrações `usina_saude_wifi_nao_vence_operando`
-- e `usina_saude_parada_so_depois_de_voltar_a_comunicar`)
-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Wi-Fi anotado só vale se o SolarView TAMBÉM não fala com o inversor:
--      or (j.causa = 'wifi' and (ult.ult is null or ult.ult <= j.causa_em::date)
--          and coalesce(j.status_atual,'') <> 'operando')) as sem_sinal
--    e a frase de "parada" diz quando havia anotação de Wi-Fi contradita:
--      "... Confira o inversor — havia anotação de Wi-Fi em DD/MM, mas o
--       SolarView diz que está falando com ele: pode estar desligado."
--    Simulado com o Valdecir em 27/09 (anotação de Wi-Fi reposta dentro de um
--    DO com raise): crítico, com a frase acima. Lucinei (Wi-Fi + datalogger
--    offline) continua "sem comunicação", como deve.
--
-- 2) Dia de sol "sem gerar" só conta depois que a usina voltou a comunicar:
--      and r.dia > greatest(coalesce(ult.ult, j.data_instalacao, c.ate - 30),
--                  case when j.status_atual = 'operando'
--                       then (j.status_desde at time zone 'America/Sao_Paulo')::date - 1 end)
--    Porque a mudança 1 revelou um falso alarme: GILBERTO Av. Brasília ficou
--    com datalogger offline de 25 a 27/09, a leitura das 9h gravou zeros, e às
--    13h15 ela voltou e descarregou 61,5 kWh (26/09) e 32,3 kWh (27/09). Com a
--    regra 1 sozinha, esses zeros de "não medi" viravam crítico.
--
-- E os dias dela foram relidos na hora pelo solarview-diario (usina_id, 10
-- dias) — Av. Brasília, Rua São Bernardo e Valdecir: 200, 11 dias cada, 0
-- falhas. Av. Brasília voltou a "abaixo do esperado · conferir cadastro" (71%).
