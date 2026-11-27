# Motor de quadros (nome de trabalho)

Kanban de processos para empresas de serviços: quadros, etapas, cartões, propriedades, conversas e avisos. Extraído do `sistema_gestao` na fase 0 da SPEC "Motor de quadros". O nome final está em aberto.

**Estado em 27/11/2026: fase 0 em andamento, nada publicado.** O código confere os tipos e os testes do núcleo passam, mas nenhuma tela foi aberta ainda neste repositório. Leia `docs/PENDENCIAS.md` antes de qualquer coisa.

## Onde está cada coisa

| Pasta | O que tem |
| --- | --- |
| `packages/core` | Regras de negócio puras, com testes: posição dos cartões, regras de fluxo, prazos, permissões. |
| `apps/web` | A aplicação (Next.js): telas do quadro, cartão, conversas, avisos, usuários e papéis. |
| `infra/migrations` | Esquema inicial do banco, para um projeto Supabase novo e vazio. |
| `infra/seeds` | Criação da empresa e dos papéis iniciais. |
| `docs/ORIGEM.md` | O que veio do `sistema_gestao`, o que ficou e por quê. |
| `docs/PENDENCIAS.md` | O que falta decidir e fazer. |

O nome do produto fica em um arquivo só: `apps/web/lib/brand.ts`.

## Rodar no computador

Requisitos: Node 20 ou mais novo e pnpm.

```bash
pnpm install
pnpm typecheck
pnpm test
cp .env.example apps/web/.env.local   # preencha com as chaves do projeto Supabase de teste
pnpm dev
```

Sem as três variáveis do Supabase o sistema não sobe. Nenhuma chave fica no repositório.

## Banco

1. Num projeto Supabase novo e vazio, rode `infra/migrations/0001_esquema_inicial.sql` e depois `0002_endurecimento_supabase.sql`. (Já feito no projeto de teste `motor-quadros-teste`, em São Paulo.)
2. Edite o nome e o domínio em `infra/seeds/0001_empresa.sql` e rode.
3. Configure o login com Google no painel do Supabase (Authentication → Providers).
4. O primeiro usuário interno que entrar vira Gestor.

## Hospedagem

Preparado para Cloudflare Workers com OpenNext, como a origem (`apps/web/wrangler.jsonc`). Nada foi publicado.
