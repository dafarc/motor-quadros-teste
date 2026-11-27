import { FieldEditorsForm } from "@/components/configuracoes/FieldEditorsForm";
import { IntakeForm } from "@/components/configuracoes/IntakeForm";
import { PipelinePicker } from "@/components/configuracoes/PipelinePicker";
import { canManageAlcadas, provisionAndGetActor } from "@/lib/actor";
import { loadBoardIntake, loadFields, loadMembers } from "@/lib/board/actions";
import { loadBoards } from "@/lib/board/queries";

export const dynamic = "force-dynamic";

export default async function AlcadasPage({
  searchParams,
}: {
  searchParams: Promise<{ board?: string }>;
}) {
  const actor = await provisionAndGetActor();
  if (!canManageAlcadas(actor)) {
    return (
      <div className="mt-6">
        <h1 className="text-2xl">Alçadas</h1>
        <p className="mt-2 text-sm text-secondary">
          Só a Direção Geral ou um Gestor pode alterar as alçadas.
        </p>
      </div>
    );
  }

  const { board: requested } = await searchParams;
  const boards = (await loadBoards()).filter((b) => !b.archived);
  const selected = boards.find((b) => b.id === requested) ?? boards[0];

  if (!selected) {
    return (
      <div className="mt-6">
        <h1 className="text-2xl">Alçadas</h1>
        <p className="mt-2 text-sm text-secondary">Nenhum pipeline disponível.</p>
      </div>
    );
  }

  const [fields, members, intake] = await Promise.all([
    loadFields(selected.id),
    loadMembers(),
    loadBoardIntake(selected.id),
  ]);

  return (
    <div className="mt-6">
      <h1 className="text-2xl">Alçadas</h1>
      <p className="mt-2 text-sm text-secondary">
        Quem tem autoridade para quê neste pipeline.
      </p>

      <label className="mt-6 grid max-w-sm gap-1">
        <span className="text-xs font-medium text-neutral-600">Pipeline</span>
        <PipelinePicker
          boards={boards.map((b) => ({ id: b.id, name: b.name }))}
          boardId={selected.id}
        />
      </label>

      <section className="mt-8">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-neutral-600">
          Quem pode abrir cartões
        </h2>
        <p className="mt-0.5 text-xs text-neutral-400">
          Quem consegue acessar o formulário de criação deste pipeline — inclusive quem não
          participa dele.
        </p>
        <div className="mt-3">
          <IntakeForm
            boardId={selected.id}
            initial={intake.intake}
            initialUserIds={intake.userIds}
            members={members}
          />
        </div>
      </section>

      <section className="mt-8">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-neutral-600">
          Permissão por propriedade
        </h2>
        <p className="mt-0.5 text-xs text-neutral-400">
          Restrinja quem pode marcar ou alterar cada propriedade — por exemplo, só a coordenação
          marca o checkbox de aprovação. Combine com uma trava de etapa para exigir a marcação
          antes de avançar.
        </p>
        <div className="mt-3">
          <FieldEditorsForm fields={fields} members={members} />
        </div>
      </section>
    </div>
  );
}
