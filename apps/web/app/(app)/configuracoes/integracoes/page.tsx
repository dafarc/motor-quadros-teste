import { TokensPanel } from "@/components/configuracoes/TokensPanel";
import { provisionAndGetActor } from "@/lib/actor";
import { listTokens } from "@/lib/integrations/actions";

export const dynamic = "force-dynamic";

/** Endereço do servidor MCP, quando existir (o servidor não veio na fase 0). */
const MCP_URL = process.env.MCP_URL || "";

export default async function IntegracoesPage() {
  const actor = await provisionAndGetActor();
  if (!actor?.permissions.has("report:read")) {
    return (
      <p className="mt-6 text-sm text-secondary">
        Sua conta não tem a permissão “Relatórios para assistentes de IA”. Peça à gestão do
        sistema, em Configurações → Papéis.
      </p>
    );
  }
  let tokens = null;
  try {
    tokens = await listTokens();
  } catch {
    tokens = null;
  }
  return <TokensPanel initialTokens={tokens} mcpUrl={MCP_URL} />;
}
