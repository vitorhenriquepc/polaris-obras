# Começar aqui — primeira vez no Claude Code

Passo a passo. Leva uns 15 minutos.

---

## 1. Clonar o repositório

No terminal, na pasta onde você quer o projeto:

```
git clone https://github.com/vitorhenriquepc/polaris-obras.git
cd polaris-obras
```

---

## 2. Ligar o Supabase (NÃO vem automático)

O Supabase que está ligado no aplicativo do Claude **não passa para o Claude
Code** — são configurações separadas. Precisa adicionar uma vez, por máquina.

No terminal, **fora** de uma sessão do Claude:

```
claude mcp add --transport http supabase https://mcp.supabase.com/mcp
```

Depois abra o Claude Code:

```
claude
```

e dentro da sessão:

```
/mcp
```

Escolha `supabase` na lista e autentique. Abre o navegador para você entrar
na sua conta.

Para conferir:

```
claude mcp list
```

**Observação:** o Claude Code rodando dentro do aplicativo de desktop usa a
configuração dele (`~/.claude.json`), não a do aplicativo. O comando acima
resolve nos dois casos.

Se quiser a configuração no projeto em vez da máquina, dá para usar um
arquivo `.mcp.json` na raiz.

---

## 3. Primeiro teste

Abra o Claude Code na pasta do projeto e peça:

> Leia o CLAUDE.md e me diga quantas usinas estão sem comunicação hoje.

Se ele ler o arquivo e consultar o banco, está tudo ligado.

---

## 4. O que fazer primeiro

1. **Conferir a migração** — comparar `migrations/2026-09-12_*.sql` com o banco
   e apontar diferença
2. **Exportar o resto do esquema** — só a sessão de 12/09 está versionada;
   o que veio antes não está
3. **Tela de indicação** com o funil novo (telefone obrigatório, paga só se fechar)
4. **Garantia e nota fiscal** — módulo que não existe e destrava atendimento,
   manutenção e venda de plano

---

## O que continua no celular

Decisão, análise, acompanhamento do dia a dia, conferir usina, ver o que a
régua vai mandar. O Claude Code é para construir.
