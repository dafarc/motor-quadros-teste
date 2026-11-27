import { redirect } from "next/navigation";
import type { ReactNode } from "react";

import { BottomNav } from "@/components/shell/BottomNav";
import { MainContainer } from "@/components/shell/MainContainer";
import { Sidebar } from "@/components/shell/Sidebar";
import { SidebarProvider } from "@/components/shell/SidebarContext";
import { provisionAndGetActor } from "@/lib/actor";
import { getSessionUser, isInternalEmail } from "@/lib/auth";
import { PhonePrompt } from "@/components/profile/PhonePrompt";

/** Shell das páginas autenticadas: sidebar + conteúdo. /login e /auth ficam fora. */
export default async function AppLayout({ children }: { children: ReactNode }) {
  const actor = await provisionAndGetActor(); // garante o app_user do usuário logado
  // Autenticado no Google mas sem acesso (domínio não autorizado, sem convite,
  // ou acesso revogado). Sem isso a pessoa veria telas vazias sem explicação.
  if (!actor) redirect("/sem-acesso");
  const sessionUser = await getSessionUser();
  const user = sessionUser?.email
    ? {
        email: sessionUser.email,
        name:
          (sessionUser.user_metadata.full_name as string | undefined) ||
          (sessionUser.user_metadata.name as string | undefined) ||
          null,
        internal: isInternalEmail(sessionUser.email),
      }
    : null;

  // O convite para cadastrar o telefone existia para o atendimento pelo WhatsApp,
  // que não veio na fase 0. Fica desligado até o WhatsApp voltar (fase 2); o
  // telefone continua editável no perfil e na tela de usuários.
  const askPhone = false;

  return (
    <SidebarProvider>
      <Sidebar user={user} />
      <MainContainer>{children}</MainContainer>
      <BottomNav />
      {askPhone && <PhonePrompt />}
    </SidebarProvider>
  );
}
