import type { FieldType, StageCategory } from "./types";

/**
 * Modelos de pipeline: etapas, propriedades e opções já prontas ao criar.
 * O pipeline criado é um pipeline comum; tudo pode ser mudado depois.
 */
export interface BoardTemplate {
  id: string;
  label: string;
  description: string;
  stages: { name: string; category: StageCategory }[];
  fields: {
    name: string;
    type: FieldType;
    options?: string[];
    showOnCard?: boolean;
    showOnCreate?: boolean;
    required?: boolean;
  }[];
  options: { myTasks?: boolean; timeTracking?: boolean };
}

/**
 * Os modelos da primeira versão (decisão do David, 27/11/2026). Com o "Quadro
 * em branco", que é criar sem modelo, são quatro opções.
 * As etapas e propriedades de "Acompanhamento de demandas" e "Registro de
 * reclamação" são PROPOSTA: o David ainda precisa ver e confirmar.
 * Nenhum modelo nasce com o cronômetro ligado.
 */
export const BOARD_TEMPLATES: BoardTemplate[] = [
  {
    id: "processo_simples",
    label: "Processo simples",
    description: "A fazer → Fazendo → Feito.",
    stages: [
      { name: "A fazer", category: "backlog" },
      { name: "Fazendo", category: "in_progress" },
      { name: "Feito", category: "done" },
    ],
    fields: [],
    options: { myTasks: true },
  },
  {
    id: "acompanhamento_demandas",
    label: "Acompanhamento de demandas",
    description:
      "Pedidos de uma área para outra: Recebida → Em análise → Em andamento → Aguardando retorno → Concluída.",
    stages: [
      { name: "Recebida", category: "backlog" },
      { name: "Em análise", category: "review" },
      { name: "Em andamento", category: "in_progress" },
      { name: "Aguardando retorno", category: "in_progress" },
      { name: "Concluída", category: "done" },
    ],
    fields: [
      { name: "Área solicitante", type: "select", options: [], showOnCard: true, showOnCreate: true },
      {
        name: "Urgência",
        type: "select",
        options: ["Baixa", "Média", "Alta"],
        showOnCard: true,
        showOnCreate: true,
      },
      { name: "O que precisa", type: "long_text", showOnCreate: true, required: true },
    ],
    options: { myTasks: true },
  },
  {
    id: "registro_reclamacao",
    label: "Registro de reclamação",
    description:
      "Reclamações de clientes: Registrada → Em apuração → Resposta ao cliente → Resolvida.",
    stages: [
      { name: "Registrada", category: "backlog" },
      { name: "Em apuração", category: "in_progress" },
      { name: "Resposta ao cliente", category: "in_progress" },
      { name: "Resolvida", category: "done" },
    ],
    fields: [
      { name: "Cliente", type: "text", showOnCard: true, showOnCreate: true, required: true },
      {
        name: "Canal",
        type: "select",
        options: ["WhatsApp", "Telefone", "E-mail", "Presencial"],
        showOnCreate: true,
      },
      {
        name: "Gravidade",
        type: "select",
        options: ["Baixa", "Média", "Alta"],
        showOnCard: true,
        showOnCreate: true,
      },
      { name: "O que aconteceu", type: "long_text", showOnCreate: true, required: true },
      { name: "Solução dada", type: "long_text" },
    ],
    options: { myTasks: true },
  },
];

const OPTION_COLORS = ["#1d4ed8", "#047857", "#b45309", "#ba1a1a", "#7c3aed", "#0891b2"];
export function templateOptions(labels: string[]) {
  return labels.map((label, i) => ({ id: `opt${i}`, label, color: OPTION_COLORS[i % OPTION_COLORS.length]! }));
}
