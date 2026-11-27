-- Motor de quadros — endurecimento para o Supabase.
--
-- O rascunho local não tinha as permissões padrão do Supabase, que dão acesso
-- total a anon e authenticated em toda tabela e função nova. Este arquivo
-- fecha isso. Aplicado no projeto motor-quadros-teste em 27/11/2026, logo
-- depois do 0001.
--
-- Regra: tudo o que grava passa pelo servidor (service_role); o navegador só lê,
-- e só o que as regras de acesso deixam.

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated;

-- Funções que agem em nome de outra pessoa: só o servidor chama.
REVOKE ALL ON FUNCTION public.card_count_rework() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.conversation_list(p_user uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.time_start(p_user uuid, p_card uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.time_stop(p_user uuid, p_at timestamp with time zone) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.transfer_card(p_card uuid, p_target_board uuid, p_actor uuid, p_map jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.has_access(p_key text) FROM anon;

-- Funções de gatilho com caminho de busca fixo (aviso do Supabase).
ALTER FUNCTION public.set_updated_at() SET search_path = public;
ALTER FUNCTION public.card_set_completed_at() SET search_path = public;
ALTER FUNCTION public.assign_card_number() SET search_path = public;

-- Funções auxiliares das regras de acesso: quem não está logado não chama.
-- Usuários logados continuam podendo, porque as próprias regras de acesso as
-- usam. Elas só respondem sobre a própria pessoa (o Supabase ainda mostra 7
-- avisos sobre isso; são esperados).
REVOKE EXECUTE ON FUNCTION public.can_see_board(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.can_see_card(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.current_org() FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.has_permission(text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.is_channel_member(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.is_internal() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.can_see_board(uuid), public.can_see_card(uuid), public.current_org(),
  public.has_permission(text), public.is_channel_member(uuid), public.is_internal() TO authenticated, service_role;
