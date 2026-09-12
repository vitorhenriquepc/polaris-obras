-- Checklist espelhando a Ordem de Serviço Digital (Auvo) da Polaris
insert into public.checklist_itens (id, titulo, descricao, obrigatorio, ordem) values
  (1,  'Telhado antes da instalação', 'Onde serão instalados os módulos. Verificar se há algum ponto que possa comprometer a obra.', true, 1),
  (2,  'Estrutura dos módulos instalada', 'Trilhos e fixação da estrutura no telhado.', true, 2),
  (3,  'Módulos fotovoltaicos instalados', 'Painéis instalados — fotos gerais do telhado.', true, 3),
  (4,  'Teste de água', 'Se realizado, registre fotos do teste. (Opcional)', false, 4),
  (5,  'Inversor e proteções instalados', 'Instalação do inversor fotovoltaico e suas proteções.', true, 5),
  (6,  'Teste de tensão e corrente no inversor', 'Fotos das medições com alicate/multímetro.', true, 6),
  (7,  'Aterramento', 'Conexão de aterramento do sistema.', true, 7),
  (8,  'Conexão CA no ponto elétrico', 'Conexão CA no ponto elétrico do local.', true, 8),
  (9,  'Monitoramento Wi-Fi conectado', 'Print/foto do diagnóstico de comunicação do inversor. Se não conectou, registre o motivo.', true, 9),
  (10, 'Teste de tensão de flutuação', 'Fotos das medições do teste de flutuação.', true, 10),
  (11, 'Etiqueta lateral do inversor (SN)', 'Foto legível da etiqueta com número de série.', true, 11),
  (12, 'Placa de geração própria', 'Placa de geração própria de energia instalada no padrão.', true, 12),
  (13, 'Observação geral / Extra', 'Qualquer detalhe adicional da obra. (Opcional)', false, 13)
on conflict (id) do update set
  titulo = excluded.titulo,
  descricao = excluded.descricao,
  obrigatorio = excluded.obrigatorio,
  ordem = excluded.ordem;
