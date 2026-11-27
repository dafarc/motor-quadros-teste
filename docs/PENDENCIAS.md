# Pendências da fase 0

*Escrito em 27/11/2026, ao fim da primeira rodada de extração, feita sem o David presente. Cada item diz o que foi encontrado, o que foi feito por conta própria e o que precisa de decisão. A ordem é a de importância.*

## Para decidir

### 1. O sistema atende uma empresa por banco

**O que foi encontrado.** A SPEC trata cada cliente como uma empresa separada dentro do mesmo sistema, com um papel de Assessor que entra em várias. O código herdado não funciona assim: no login ele usa sempre a primeira empresa cadastrada no banco (`apps/web/lib/actor.ts`). As tabelas já guardam a empresa em cada linha e o banco já separa os dados por empresa, mas a aplicação nunca precisou escolher entre duas.

**Por que importa.** Atender vários clientes pede uma destas duas coisas: um banco por cliente (mais simples agora, mais caro e trabalhoso de manter) ou ensinar o sistema a escolher a empresa no login (trabalho de fase 1, mexe em login, convites e papéis).

**Recomendação.** Tratar como item novo da fase 1 e decidir entre as duas formas antes de começar a fase 1. A fase 0 segue com uma empresa de teste.

### 2. Contador de emendas: remover, ou reaproveitar como "devoluções"

**O que foi encontrado.** O inventário previa remover as emendas. O contador é genérico: conta quantas vezes um cartão voltou para uma etapa marcada como "de emenda", por um gatilho no banco. Ele aparece em 13 arquivos.

**O que foi feito.** Ficou no código, adormecido: nenhum modelo marca etapa de emenda, então nada aparece na tela. A tabela `emenda` (rodadas com status), que é da editora, não veio.

**Decisão.** Remover de vez, ou renomear para "devoluções" e usar na recusa da aprovação por etapa (fase 1). Recomendação: reaproveitar.

### 3. Região do banco de teste

O projeto `motor-quadros-teste` no Supabase foi criado em Oregon (us-west-2), não em São Paulo. A região não muda depois. **O esquema ainda não foi aplicado nele**, justamente por isso: se for recriar em São Paulo, é melhor aplicar só uma vez. Decisão: recriar ou manter.

### 4. Repositório público

`dafarc/motor-quadros-teste` está público. Qualquer pessoa pode ler e copiar o código. Recomendação: tornar privado antes de o sistema ter cliente.

### 5. Imagens dos cartões ficam em endereço público

Herdado da origem: as imagens coladas na descrição de um cartão vão para um balde público do Supabase. Quem tiver o endereço de uma imagem abre sem login. Para um sistema com dados de clientes, recomendo balde privado com endereço assinado. É mudança de código, fase 1.

### 6. Etapas e propriedades de dois modelos

"Acompanhamento de demandas" e "Registro de reclamação" foram montados como proposta em `apps/web/lib/board/templates.ts`. Falta o David ver e ajustar.

- **Acompanhamento de demandas:** Recebida → Em análise → Em andamento → Aguardando retorno → Concluída. Propriedades: área solicitante, urgência, o que precisa.
- **Registro de reclamação:** Registrada → Em apuração → Resposta ao cliente → Resolvida. Propriedades: cliente, canal, gravidade, o que aconteceu, solução dada.

"Quadro em branco" passou a nascer sem nenhuma etapa. Na origem, "em branco" criava A fazer, Fazendo e Feito, que agora é o modelo "Processo simples".

### 7. Lista de cargos

`apps/web/lib/roles/cargos.ts` ainda traz os cargos da origem (Diretor Geral, Diretor Administrativo, Gestor Financeiro, Coordenador, Solicitante, Estagiário). Falta definir a lista do motor. Ela vai importar para "quem aprova" na fase 1.

## Para fazer, sem decisão pendente

### 8. Dados para criar a empresa de teste e ligar o login

- Nome da empresa e domínio dos e-mails internos, para `infra/seeds/0001_empresa.sql` e para a variável `INTERNAL_EMAIL_DOMAIN`.
- Login com Google configurado no painel do Supabase do projeto de teste.
- As três chaves do projeto em `apps/web/.env.local`.

### 9. Nenhuma tela foi aberta

O que foi conferido: os tipos de todo o código e os 51 testes do núcleo. O que **não** foi conferido: nenhuma tela, nenhum clique. Abrir o sistema depende do item 8. O `next build` também não foi concluído no ambiente de extração, porque ele bloqueia o endereço das fontes do Google; isso não indica erro no código, mas o build segue sem prova.

Critérios da passagem ainda sem prova: criar empresa e quadros pelos modelos; criar, mover, renomear e arquivar cartão; histórico, comentários e checklists; Kanban, Lista e "apenas os meus" no computador e no celular; um usuário de uma empresa não abrir cartão de outra.

### 10. Medição de velocidade

`docs/MEDICAO.md` não existe ainda. Depende do sistema rodando com banco (itens 3 e 8).

### 11. Restos de texto da origem

- A tela de usuários ainda explica o telefone como "o número pelo qual o assistente do WhatsApp reconhece a pessoa".
- A tela de usuários diz que o cargo "define quem aprova as demandas em cada faixa".
- O núcleo ainda descreve o cartão como "matéria × série × bimestre" em comentários e em tipos que a aplicação não usa (`packages/core/src/domain/index.ts`).
- Os nomes de rota continuam em português da origem: `/board`, `/canais`, `/avisos`, `/configuracoes/alcadas`.

### 12. Coisas que ficaram sem botão

- **Liberação pela gestão** (`board.release_required`): a regra existe no código; a tela que a ligava era a do WhatsApp.
- **Acessos pontuais por pessoa** (`user_grant`): o mecanismo ficou, sem nenhuma chave definida. As duas da origem eram de módulos que não vieram.
- **Servidor MCP:** a tela de Integrações ainda gera tokens, mas não há servidor para usá-los.

### 13. Itens provisórios

- Ícones do aplicativo: desenhados por código, só para não usar a marca da origem.
- Política de privacidade: a página da origem era da central de anamneses e não veio. O sistema está sem uma.
- Hospedagem: `apps/web/wrangler.jsonc` foi reescrito do zero, sem publicar. Falta criar o Worker e cadastrar as variáveis.

## Três riscos que foram evitados na cópia

Vale saber, porque dizem respeito ao sistema de origem:

- O `next.config.ts` da origem tinha o endereço e a chave pública do banco de **produção** como valor padrão. Rodar o código novo sem configurar nada falaria com o banco da origem. Os padrões foram removidos; sem as variáveis, o sistema novo não sobe.
- O `wrangler.jsonc` da origem tinha o nome do Worker de produção. Um deploy do código novo com ele substituiria o sistema no ar. O nome foi trocado.
- O `vercel.json` redirecionava tudo para o domínio de produção. Foi removido.
