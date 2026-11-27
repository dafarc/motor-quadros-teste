# De onde veio este código

*Inventário feito em 27/11/2026 lendo o `davidfarc/sistema_gestao` no commit `e6938ff` (26/11/2026), só em leitura. A extração foi feita no mesmo dia; o que ela mudou em relação a este inventário está em "O que a extração fez de diferente", no fim.*

## Resumo

O quadro sai com pouco corte. O repositório tem 408 arquivos; o quadro em si são 53 (35 de tela em `components/board`, 18 de regra em `lib/board`), mais o núcleo `packages/core` (2.526 linhas com testes). O quadro depende de fora em 17 linhas de importação, concentradas em 9 arquivos. Não há dependência do quadro em relação a salas, novos alunos ou anamnese.

## O que vem

| Parte | Onde está na origem | Observação |
| --- | --- | --- |
| Núcleo de regras | `packages/core`: `domain`, `ports`, `services/cardService`, `services/gates`, `sla`, `ranking`, `ids`, `errors`, `auth/policy`, `fieldSync`, `webpush` | Vem com os testes. |
| Telas do quadro | `apps/web/components/board` (menos os três arquivos da tabela "o que fica") | Kanban, Lista, "Minhas tarefas", cartão, checklists, comentários, anexos, histórico, transferência, formulário de entrada, modelos. |
| Regras do quadro | `apps/web/lib/board` (menos `whatsapp.ts`) | |
| Rotas | `(app)/board`, `(app)/card/[id]`, `login`, `auth`, `sem-acesso`, `privacidade` | |
| Base da aplicação | `lib/supabase`, `lib/actor.ts`, `lib/auth.ts`, `lib/roles`, `lib/env.ts`, `lib/useIsMobile.ts`, `lib/chunkReload.ts`, `components/shell`, `components/common`, `components/profile`, `lib/profile` | Menu, login, papéis, perfil. |
| Usuários e papéis | `(app)/configuracoes/usuarios`, `(app)/configuracoes/papeis`, `components/users`, parte de `components/configuracoes` | É a gestão de usuários que a aprovação por etapa vai usar. |
| Notificações | `lib/notifications`, `lib/push`, `lib/pwa`, `components/avisos`, rota `(app)/avisos`, sino do menu | Aviso no sistema e no celular. |
| Atalhos | `lib/shortcuts`, `components/home` | Decisão do David de 27/11. |
| Cronômetro (base) | `lib/time`, tabela `time_entry` | Decisão do David de 27/11: base pronta, desligado nos quatro modelos. |
| Conversas internas | `lib/comms`, `components/channels`, rota `(app)/canais`, tabelas `channel`, `channel_member`, `message` | Decisão do David de 27/11: as conversas diretas vêm. O módulo tem cerca de mil linhas e não depende de nada que fica; a conversa direta é um tipo de canal, então o módulo vem inteiro. |
| Aprovações (base) | tabela `approval`, exigência "aprovação" em `services/gates` | Base da aprovação por etapa da fase 1. |

## O que fica no `sistema_gestao`

| Parte | Onde está | Arquivos |
| --- | --- | --- |
| Novos alunos e anamnese | `lib/anamnese`, `components/anamnese`, rotas `novos-alunos`, `agendar`, `api/anamnese`, Prisma | maior bloco fora do quadro |
| Salas | `lib/salas`, `components/salas`, rotas `salas`, `api/salas` | |
| Priorização e despesas | `lib/demandas`, `lib/planejamento`, `components/prioridades`, `components/planejamento`, rota `prioridades`, `packages/core/src/alcadas.ts`, `(app)/configuracoes/alcadas` | Decisão do David de 27/11. |
| Painéis e relatórios | `lib/reports`, `lib/charts`, `components/painel`, rota `painel`, `api/relatorios` | Decisão do David de 27/11. |
| WhatsApp | `apps/whatsapp`, `lib/board/whatsapp.ts`, `components/board/WhatsappOptions.tsx`, `api/whatsapp`, `packages/core/src/whatsappAgent.ts`, `phone.ts` | Volta na fase 2, em versão enxuta. |
| Servidor MCP | `apps/mcp` | Volta quando a API for revista. |
| Pasta do Drive por cartão | tabelas `card_drive`, `drive_folder`, `lib/integrations` | Decisão do David de 27/11. |
| Três arquivos dentro do quadro | `components/board/DemandPanel.tsx`, `DemandasCreateForm.tsx`, `WhatsappOptions.tsx` | Pertencem a demandas e ao WhatsApp. |

## Onde o quadro está amarrado ao que fica

São os pontos de corte da extração. Cada um precisa ser desfeito à mão.

| # | Ponto | Arquivos | O que fazer |
| --- | --- | --- | --- |
| 1 | Demandas e RICE dentro do quadro | `ListView.tsx` (cálculo da demanda), `cardMoveAdapter.ts` (campos RICE exigidos para mover), `NewCardDialog.tsx` (formulário de demandas) | Remover. O formulário de criação fica só nos modos simples e genérico. |
| 2 | Selo "Aguarda priorização" e etapas com fila | `CardTile.tsx`, `localState.ts`, `BoardView.tsx`, `queries.ts`, `types.ts` | Remover o selo e a exigência "priorizado" das regras de fluxo. |
| 3 | Emendas | `CardTile.tsx` (contador), `CardContent.tsx`, `StageHeader.tsx` ("conta emenda"), `ActivityFeed.tsx`, exigência "emenda concluída" em `gates` | Remover. |
| 4 | Aviso por conversa direta | `lib/board/actions.ts`, `cardOps.ts` chamam `ensureDmChannel` | Fica como está: ao atribuir um cartão, a pessoa recebe a mensagem direta. O David escolheu trazer as conversas (27/11). |
| 5 | WhatsApp nas opções do quadro | `BoardOptionsDialog.tsx`, `templates.ts`, `actions.ts` | Remover a seção; volta na fase 2. |
| 6 | Painel próprio do quadro | opção `ownPanel` em `templates.ts` e `BoardOptionsDialog.tsx` | Remover a opção. |
| 7 | Cronômetro | `MyTasksView.tsx`, `BoardOptionsDialog.tsx`, `cardOps.ts`, `transfer.ts` | Fica (decisão do David). |

## Achados que mudam o que eu tinha escrito

- **O README cita `packages/adapters/supabase`, mas a pasta não existe.** O acesso ao banco está dentro de `apps/web/lib`. A passagem de execução manda copiar esse pacote; não há o que copiar.
- **As conversas internas entraram no escopo.** A SPEC as deixava de fora, mas o aviso de atribuição depende delas; o David decidiu trazê-las em 27/11.
- **Os quatro tipos de etapa já existem:** lista, em andamento, revisão e concluído (`backlog`, `in_progress`, `review`, `done`).

## O que a extração fez de diferente do inventário

- **O contador de emendas ficou, adormecido.** O inventário previa remover. Ele é um contador genérico de "quantas vezes o cartão voltou para uma etapa de ajuste", ligado por gatilho no banco, e pode servir à recusa da aprovação por etapa (fase 1). Nenhum modelo marca etapa de emenda, então ele não aparece. A tabela `emenda` (rodadas com status) não veio. Decisão pendente: `docs/PENDENCIAS.md`, item 2.
- **A coluna `board.release_required` ficou.** Ela faz o cartão novo só sair da primeira etapa pelas mãos da gestão. A tela que a ligava era a de opções do WhatsApp, que não veio; a regra está no código, sem botão.
- **A página de alçadas voltou, sem as faixas de valor.** Ela também abriga "quem pode abrir cartões" e "quem edita cada propriedade", que são do quadro.
- **Telefone do usuário (`user_phone`, `packages/core/src/phone.ts`) ficou.** O perfil e a tela de usuários usam. O convite automático para cadastrar o telefone foi desligado.
- **A página de privacidade não veio.** O texto era da central de anamneses.
- **Tabela `api_token_call` e funções `report_*` e `mcp_call` não vieram.** Pertencem ao servidor MCP e aos relatórios.
- **Esquema do banco:** `infra/migrations/0001_esquema_inicial.sql` foi gerado aplicando as 58 migrations da origem num Postgres de rascunho, removendo o que fica e exportando. São 31 tabelas, todas com separação por empresa ligada, 32 políticas e 6 tabelas em tempo real.
