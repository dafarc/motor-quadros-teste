-- Motor de quadros — esquema inicial (fase 0).
--
-- Gerado em 27/11/2026 a partir do sistema_gestao (commit e6938ff): as 58
-- migrations da origem foram aplicadas num Postgres de rascunho, os objetos
-- que não vieram foram removidos e o resultado foi exportado.
--
-- Ficaram de fora: ano letivo, séries, segmentos, matérias, volumes, emendas
-- (tabela), salas, priorização, planejamento de gastos, pasta do Drive,
-- WhatsApp, relatórios (funções report_*) e o registro de chamadas do MCP.
-- Detalhes em docs/ORIGEM.md.
--
-- Para um projeto Supabase NOVO e vazio. Não reaplicar sobre um banco em uso.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: assign_card_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_card_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.number is null or new.number = 0 then
    select coalesce(max(number), 0) + 1 into new.number
      from card where board_id = new.board_id;
  end if;
  return new;
end;
$$;


--
-- Name: can_see_board(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_see_board(p_board_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case
    when public.is_internal() then
      case
        when public.has_permission('board:configure') then
          exists (select 1 from board b
                  where b.id = p_board_id and b.organization_id = public.current_org())
        else
          exists (select 1 from board_member m
                  where m.board_id = p_board_id and m.user_id = auth.uid())
      end
    else
      exists (select 1 from assignment a
              join card c on c.id = a.card_id
              where c.board_id = p_board_id and a.user_id = auth.uid()
                and a.archived_at is null)
  end
$$;


--
-- Name: can_see_card(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_see_card(p_card_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case
    when public.is_internal() then
      exists (
        select 1 from card c
        where c.id = p_card_id
          and c.organization_id = public.current_org()
          and (
            -- O que a própria pessoa pediu, mesmo fora dos pipelines dela (0028).
            c.requester_id = auth.uid()
            or (
              public.can_see_board(c.board_id)
              and (
                public.has_permission('card:read_all')
                -- Sem "ver todos": só os cards em que é responsável.
                or exists (
                  select 1 from assignment a
                  where a.card_id = c.id and a.user_id = auth.uid()
                    and a.archived_at is null
                )
              )
            )
          )
      )
    else
      exists (
        select 1 from assignment a
        where a.card_id = p_card_id and a.user_id = auth.uid()
          and a.archived_at is null
      )
  end
$$;


--
-- Name: card_count_rework(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_count_rework() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.stage_id is distinct from old.stage_id
     and exists (select 1 from stage s where s.id = new.stage_id and s.counts_rework) then
    new.rework_count := coalesce(old.rework_count, 0) + 1;
  end if;
  return new;
end$$;


--
-- Name: card_set_completed_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_set_completed_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  cat text;
begin
  if tg_op = 'UPDATE' and new.stage_id is not distinct from old.stage_id then
    return new;
  end if;
  select category into cat from stage where id = new.stage_id;
  if cat = 'done' then
    new.completed_at := coalesce(new.completed_at, now());
  else
    new.completed_at := null;
  end if;
  return new;
end$$;


--
-- Name: conversation_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.conversation_list(p_user uuid) RETURNS TABLE(channel_id uuid, kind text, name text, other_user_id uuid, other_name text, other_email text, last_body text, last_at timestamp with time zone, unread bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    c.id,
    c.kind,
    c.name,
    dm.other_id,
    ou.name,
    ou.email,
    lm.body,
    lm.created_at,
    coalesce(uc.cnt, 0)
  from channel c
  join channel_member me on me.channel_id = c.id and me.user_id = p_user
  left join lateral (
    select cm2.user_id as other_id
    from channel_member cm2
    where cm2.channel_id = c.id and cm2.user_id <> p_user
    limit 1
  ) dm on c.kind = 'dm'
  left join app_user ou on ou.id = dm.other_id
  left join lateral (
    select m.body, m.created_at
    from message m
    where m.channel_id = c.id and m.archived_at is null
    order by m.created_at desc
    limit 1
  ) lm on true
  left join lateral (
    select count(*) as cnt
    from message m
    where m.channel_id = c.id and m.archived_at is null
      and m.author_id <> p_user
      and (me.last_read_at is null or m.created_at > me.last_read_at)
  ) uc on true
  where c.archived_at is null
  order by coalesce(lm.created_at, c.created_at) desc;
$$;


--
-- Name: current_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_org() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select organization_id from app_user where id = auth.uid()
$$;


--
-- Name: has_access(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_access(p_key text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case p_key
           when 'salas' then public.has_permission('salas:manage')
           when 'novos' then public.has_permission('novos:access') or public.has_permission('novos:manage')
           else false
         end
      or exists (select 1 from user_grant g where g.user_id = auth.uid() and g.key = p_key)
$$;


--
-- Name: has_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(p_action text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from user_role ur
    join role r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.permissions ? p_action
  )
$$;


--
-- Name: is_channel_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_channel_member(p_channel_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from channel_member m
    where m.channel_id = p_channel_id and m.user_id = auth.uid()
  )
$$;


--
-- Name: is_internal(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_internal() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((select is_internal from app_user where id = auth.uid()), false)
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


--
-- Name: time_start(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.time_start(p_user uuid, p_card uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  c        card%rowtype;
  v_now    timestamptz := now();
  v_paused uuid;
  v_id     uuid;
begin
  select * into c from card where id = p_card and archived_at is null;
  if not found then raise exception 'card_not_found'; end if;

  -- Já está ligado neste card: nada a fazer.
  select id into v_id from time_entry
   where user_id = p_user and ended_at is null and card_id = p_card;
  if found then
    return jsonb_build_object('entryId', v_id, 'pausedCardId', null);
  end if;

  update time_entry set ended_at = v_now
   where user_id = p_user and ended_at is null
   returning card_id into v_paused;

  insert into time_entry (organization_id, card_id, user_id, board_id, started_at)
  values (c.organization_id, p_card, p_user, c.board_id, v_now)
  returning id into v_id;

  return jsonb_build_object('entryId', v_id, 'pausedCardId', v_paused);
end$$;


--
-- Name: time_stop(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.time_stop(p_user uuid, p_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  e   time_entry%rowtype;
  v_at timestamptz := coalesce(p_at, now());
begin
  select * into e from time_entry where user_id = p_user and ended_at is null for update;
  if not found then return jsonb_build_object('stopped', false); end if;
  if v_at > now() then raise exception 'end_in_future'; end if;
  if v_at <= e.started_at then raise exception 'end_before_start'; end if;
  update time_entry
     set ended_at = v_at,
         edited_at = case when p_at is null then edited_at else now() end
   where id = e.id;
  return jsonb_build_object('stopped', true, 'cardId', e.card_id,
                            'seconds', extract(epoch from v_at - e.started_at));
end$$;


--
-- Name: transfer_card(uuid, uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transfer_card(p_card uuid, p_target_board uuid, p_actor uuid, p_map jsonb DEFAULT '[]'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  c          card%rowtype;
  src_name   text;
  tgt        board%rowtype;
  v_stage    uuid;
  v_number   bigint;
  v_pos      numeric;
  v_prev     uuid;
  r          record;
  v_to       uuid;
  tf         field_definition%rowtype;
  v_display  text;
  v_option   text;
  v_ok       boolean;
  v_left     text := '';
  v_moved    integer := 0;
begin
  select * into c from card where id = p_card for update;
  if not found then raise exception 'card_not_found'; end if;
  if c.board_id = p_target_board then raise exception 'same_board'; end if;

  select * into tgt from board
   where id = p_target_board and archived_at is null and organization_id = c.organization_id;
  if not found then raise exception 'target_not_found'; end if;
  select name into src_name from board where id = c.board_id;

  select id into v_stage from stage
   where board_id = tgt.id and archived_at is null
   order by position, name limit 1;
  if v_stage is null then raise exception 'target_without_stages'; end if;

  -- Dois envios simultâneos para o mesmo pipeline não podem pegar o mesmo número.
  perform pg_advisory_xact_lock(hashtext('card_number:' || tgt.id::text));
  select coalesce(max(number), 0) + 1 into v_number from card where board_id = tgt.id;
  select coalesce(max(position), 0) + 1000 into v_pos from card where stage_id = v_stage;

  select a.user_id into v_prev from assignment a
   where a.card_id = p_card and a.stage_id is null limit 1;

  -- Campos PRÓPRIOS do pipeline de origem (os globais, board_id nulo, ficam).
  for r in
    select v.*, f.name as fname, f.type as ftype, f.config as fconfig
      from field_value v
      join field_definition f on f.id = v.field_definition_id
     where v.card_id = p_card and f.board_id = c.board_id
     order by f.position
  loop
    v_display := case r.ftype
      when 'checkbox' then case when r.value_bool then 'sim' else null end
      when 'number'   then r.value_number::text
      when 'date'     then to_char(r.value_date, 'DD/MM/YYYY')
      when 'member'   then (select coalesce(nullif(u.name, ''), u.email) from app_user u where u.id = r.value_member_id)
      when 'select'   then coalesce((select o->>'label' from jsonb_array_elements(coalesce(r.fconfig->'options', '[]'::jsonb)) o
                                      where o->>'id' = r.value_text limit 1), r.value_text)
      when 'status'   then coalesce((select o->>'label' from jsonb_array_elements(coalesce(r.fconfig->'options', '[]'::jsonb)) o
                                      where o->>'id' = r.value_text limit 1), r.value_text)
      else r.value_text
    end;

    v_ok := false;
    if v_display is not null and v_display <> '' then
      select nullif(m->>'to', '')::uuid into v_to
        from jsonb_array_elements(coalesce(p_map, '[]'::jsonb)) m
       where m->>'from' = r.field_definition_id::text
       limit 1;

      if v_to is not null then
        select * into tf from field_definition
         where id = v_to and board_id = tgt.id and archived_at is null;
        if found and (
             tf.type = r.ftype
          or (tf.type in ('text', 'long_text') and r.ftype in ('text', 'long_text'))
          or (tf.type in ('select', 'status') and r.ftype in ('select', 'status'))
        ) then
          if tf.type in ('select', 'status') then
            -- A opção é reconhecida pelo NOME (os ids são de cada campo).
            select o->>'id' into v_option
              from jsonb_array_elements(coalesce(tf.config->'options', '[]'::jsonb)) o
             where lower(trim(o->>'label')) = lower(trim(v_display)) limit 1;
            if v_option is not null then
              insert into field_value (field_definition_id, card_id, organization_id, value_text)
              values (tf.id, p_card, c.organization_id, v_option)
              on conflict (field_definition_id, card_id) do update set value_text = excluded.value_text;
              v_ok := true;
            end if;
          else
            insert into field_value (field_definition_id, card_id, organization_id,
                                     value_text, value_number, value_date, value_bool, value_member_id, value_json)
            values (tf.id, p_card, c.organization_id,
                    r.value_text, r.value_number, r.value_date, r.value_bool, r.value_member_id, r.value_json)
            on conflict (field_definition_id, card_id) do update set
              value_text = excluded.value_text, value_number = excluded.value_number,
              value_date = excluded.value_date, value_bool = excluded.value_bool,
              value_member_id = excluded.value_member_id, value_json = excluded.value_json;
            v_ok := true;
          end if;
        end if;
      end if;

      if v_ok then v_moved := v_moved + 1;
      else v_left := v_left || '• ' || r.fname || ': ' || left(v_display, 500) || E'\n';
      end if;
    end if;

    delete from field_value
     where field_definition_id = r.field_definition_id and card_id = p_card;
  end loop;

  delete from assignment where card_id = p_card;

  update card
     set board_id = tgt.id, stage_id = v_stage, stage_entered_at = now(),
         number = v_number, position = v_pos
   where id = p_card;

  insert into activity (organization_id, card_id, actor_id, kind, payload)
  values (c.organization_id, p_card, p_actor, 'card_transferred', jsonb_build_object(
    'fromBoardId', c.board_id, 'fromBoardName', src_name,
    'toBoardId', tgt.id, 'toBoardName', tgt.name,
    'fromStageId', c.stage_id, 'toStageId', v_stage,
    'oldNumber', c.number, 'newNumber', v_number,
    'fieldsMoved', v_moved, 'previousResponsibleId', v_prev));

  if v_left <> '' then
    insert into comment (organization_id, card_id, author_id, body)
    values (c.organization_id, p_card, p_actor,
      format(E'Veio do pipeline “%s” (era #%s). Campos de lá que não têm correspondente aqui:\n%s',
             src_name, c.number, rtrim(v_left, E'\n')));
  end if;

  return jsonb_build_object('boardId', tgt.id, 'boardName', tgt.name, 'stageId', v_stage,
                            'number', v_number, 'fieldsMoved', v_moved, 'fieldsKept', v_left <> '');
end$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid,
    actor_id uuid NOT NULL,
    kind text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.activity FORCE ROW LEVEL SECURITY;


--
-- Name: api_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_token (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    token_hash text NOT NULL,
    token_prefix text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone
);


--
-- Name: app_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_user (
    id uuid NOT NULL,
    organization_id uuid NOT NULL,
    email text NOT NULL,
    name text DEFAULT ''::text NOT NULL,
    is_internal boolean DEFAULT false NOT NULL,
    avatar_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    cargo text
);

ALTER TABLE ONLY public.app_user FORCE ROW LEVEL SECURITY;


--
-- Name: approval; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    stage_id uuid,
    approver_id uuid NOT NULL,
    approved boolean DEFAULT true NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.approval FORCE ROW LEVEL SECURITY;


--
-- Name: assignment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assignment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    user_id uuid NOT NULL,
    stage_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.assignment FORCE ROW LEVEL SECURITY;


--
-- Name: attachment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attachment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    kind text DEFAULT 'link'::text NOT NULL,
    label text DEFAULT ''::text NOT NULL,
    url text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.attachment FORCE ROW LEVEL SECURITY;


--
-- Name: board; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    card_face_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    creation_form text DEFAULT 'simple'::text NOT NULL,
    intake text DEFAULT 'members'::text NOT NULL,
    intake_user_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    my_tasks boolean DEFAULT false NOT NULL,
    time_tracking boolean DEFAULT false NOT NULL,
    release_required boolean DEFAULT false NOT NULL,
    CONSTRAINT board_intake_check CHECK ((intake = ANY (ARRAY['members'::text, 'org'::text, 'users'::text])))
);

ALTER TABLE ONLY public.board FORCE ROW LEVEL SECURITY;


--
-- Name: board_member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_member (
    board_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.board_member FORCE ROW LEVEL SECURITY;


--
-- Name: card; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    board_id uuid NOT NULL,
    number bigint DEFAULT 0 NOT NULL,
    code text,
    title text NOT NULL,
    stage_id uuid NOT NULL,
    stage_entered_at timestamp with time zone DEFAULT now() NOT NULL,
    "position" numeric DEFAULT 1000 NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    due_date date,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    description text,
    requester_id uuid,
    completed_at timestamp with time zone,
    rework_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT card_status_check CHECK ((status = ANY (ARRAY['active'::text, 'blocked'::text, 'done'::text, 'archived'::text])))
);

ALTER TABLE ONLY public.card FORCE ROW LEVEL SECURITY;


--
-- Name: channel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    team_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    kind text DEFAULT 'group'::text NOT NULL,
    dm_key text,
    CONSTRAINT channel_kind_check CHECK ((kind = ANY (ARRAY['group'::text, 'dm'::text])))
);

ALTER TABLE ONLY public.channel REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.channel FORCE ROW LEVEL SECURITY;


--
-- Name: channel_member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_member (
    channel_id uuid NOT NULL,
    user_id uuid NOT NULL,
    last_read_at timestamp with time zone
);

ALTER TABLE ONLY public.channel_member REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.channel_member FORCE ROW LEVEL SECURITY;


--
-- Name: checklist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    name text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.checklist FORCE ROW LEVEL SECURITY;


--
-- Name: checklist_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    checklist_id uuid NOT NULL,
    text text NOT NULL,
    done boolean DEFAULT false NOT NULL,
    assignee_id uuid,
    "position" integer DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.checklist_item FORCE ROW LEVEL SECURITY;


--
-- Name: checklist_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist_template (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    board_id uuid NOT NULL,
    name text NOT NULL,
    items jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT checklist_template_items_check CHECK ((jsonb_typeof(items) = 'array'::text))
);

ALTER TABLE ONLY public.checklist_template FORCE ROW LEVEL SECURITY;


--
-- Name: comment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    author_id uuid NOT NULL,
    body text NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    parent_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.comment FORCE ROW LEVEL SECURITY;


--
-- Name: field_definition; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.field_definition (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    board_id uuid,
    name text NOT NULL,
    type text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    show_on_card_face boolean DEFAULT false NOT NULL,
    is_filterable boolean DEFAULT true NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    show_on_create boolean DEFAULT false NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    allowed_editors uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    CONSTRAINT field_definition_type_check CHECK ((type = ANY (ARRAY['text'::text, 'long_text'::text, 'number'::text, 'date'::text, 'select'::text, 'multi_select'::text, 'checkbox'::text, 'member'::text, 'link'::text, 'status'::text])))
);

ALTER TABLE ONLY public.field_definition FORCE ROW LEVEL SECURITY;


--
-- Name: field_value; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.field_value (
    field_definition_id uuid NOT NULL,
    card_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    value_text text,
    value_number numeric,
    value_date date,
    value_bool boolean,
    value_member_id uuid,
    value_json jsonb
);

ALTER TABLE ONLY public.field_value FORCE ROW LEVEL SECURITY;


--
-- Name: message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    author_id uuid NOT NULL,
    body text NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.message REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.message FORCE ROW LEVEL SECURITY;


--
-- Name: notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notification REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.notification FORCE ROW LEVEL SECURITY;


--
-- Name: organization; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email_domain text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.organization FORCE ROW LEVEL SECURITY;


--
-- Name: push_subscription; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscription (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_success_at timestamp with time zone
);


--
-- Name: role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    permissions jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    slug text
);

ALTER TABLE ONLY public.role FORCE ROW LEVEL SECURITY;


--
-- Name: shortcut; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shortcut (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    label text NOT NULL,
    description text,
    href text NOT NULL,
    icon text,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.shortcut FORCE ROW LEVEL SECURITY;


--
-- Name: stage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    board_id uuid NOT NULL,
    name text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    category text DEFAULT 'in_progress'::text NOT NULL,
    wip_limit integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    counts_rework boolean DEFAULT false NOT NULL,
    CONSTRAINT stage_category_check CHECK ((category = ANY (ARRAY['backlog'::text, 'in_progress'::text, 'review'::text, 'done'::text])))
);

ALTER TABLE ONLY public.stage FORCE ROW LEVEL SECURITY;


--
-- Name: team; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone
);

ALTER TABLE ONLY public.team FORCE ROW LEVEL SECURITY;


--
-- Name: time_entry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_entry (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    card_id uuid NOT NULL,
    user_id uuid NOT NULL,
    board_id uuid NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    edited_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT time_entry_check CHECK (((ended_at IS NULL) OR (ended_at > started_at)))
);


--
-- Name: user_grant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_grant (
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_grant_key_check CHECK ((key = ANY (ARRAY['salas'::text, 'novos'::text])))
);

ALTER TABLE ONLY public.user_grant FORCE ROW LEVEL SECURITY;


--
-- Name: user_phone; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_phone (
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    phone text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_phone_phone_check CHECK ((phone ~ '^\+[1-9][0-9]{7,14}$'::text))
);

ALTER TABLE ONLY public.user_phone FORCE ROW LEVEL SECURITY;


--
-- Name: user_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_role (
    user_id uuid NOT NULL,
    role_id uuid NOT NULL
);

ALTER TABLE ONLY public.user_role FORCE ROW LEVEL SECURITY;


--
-- Name: user_team; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_team (
    user_id uuid NOT NULL,
    team_id uuid NOT NULL
);

ALTER TABLE ONLY public.user_team FORCE ROW LEVEL SECURITY;


--
-- Name: workflow_rule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_rule (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    board_id uuid NOT NULL,
    from_stage_id uuid,
    to_stage_id uuid,
    requirement text NOT NULL,
    requirement_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    enforcement text DEFAULT 'block'::text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT workflow_rule_enforcement_check CHECK ((enforcement = ANY (ARRAY['block'::text, 'warn'::text]))),
    CONSTRAINT workflow_rule_requirement_check CHECK ((requirement = ANY (ARRAY['checklist_complete'::text, 'attachment_present'::text, 'field_filled'::text, 'approval'::text, 'role'::text])))
);

ALTER TABLE ONLY public.workflow_rule FORCE ROW LEVEL SECURITY;


--
-- Name: activity activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_pkey PRIMARY KEY (id);


--
-- Name: api_token api_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_token
    ADD CONSTRAINT api_token_pkey PRIMARY KEY (id);


--
-- Name: api_token api_token_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_token
    ADD CONSTRAINT api_token_token_hash_key UNIQUE (token_hash);


--
-- Name: app_user app_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);


--
-- Name: approval approval_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval
    ADD CONSTRAINT approval_pkey PRIMARY KEY (id);


--
-- Name: assignment assignment_card_id_user_id_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_card_id_user_id_stage_id_key UNIQUE (card_id, user_id, stage_id);


--
-- Name: assignment assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_pkey PRIMARY KEY (id);


--
-- Name: attachment attachment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_pkey PRIMARY KEY (id);


--
-- Name: board_member board_member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_member
    ADD CONSTRAINT board_member_pkey PRIMARY KEY (board_id, user_id);


--
-- Name: board board_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board
    ADD CONSTRAINT board_pkey PRIMARY KEY (id);


--
-- Name: card card_board_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_board_id_code_key UNIQUE (board_id, code);


--
-- Name: card card_board_id_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_board_id_number_key UNIQUE (board_id, number);


--
-- Name: card card_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_pkey PRIMARY KEY (id);


--
-- Name: channel_member channel_member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_member
    ADD CONSTRAINT channel_member_pkey PRIMARY KEY (channel_id, user_id);


--
-- Name: channel channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_pkey PRIMARY KEY (id);


--
-- Name: checklist_item checklist_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_pkey PRIMARY KEY (id);


--
-- Name: checklist checklist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_pkey PRIMARY KEY (id);


--
-- Name: checklist_template checklist_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_template
    ADD CONSTRAINT checklist_template_pkey PRIMARY KEY (id);


--
-- Name: comment comment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);


--
-- Name: field_definition field_definition_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_definition
    ADD CONSTRAINT field_definition_pkey PRIMARY KEY (id);


--
-- Name: field_value field_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_value
    ADD CONSTRAINT field_value_pkey PRIMARY KEY (field_definition_id, card_id);


--
-- Name: message message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id);


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: push_subscription push_subscription_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscription
    ADD CONSTRAINT push_subscription_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscription push_subscription_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscription
    ADD CONSTRAINT push_subscription_pkey PRIMARY KEY (id);


--
-- Name: role role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_pkey PRIMARY KEY (id);


--
-- Name: shortcut shortcut_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shortcut
    ADD CONSTRAINT shortcut_pkey PRIMARY KEY (id);


--
-- Name: stage stage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage
    ADD CONSTRAINT stage_pkey PRIMARY KEY (id);


--
-- Name: team team_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (id);


--
-- Name: time_entry time_entry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entry
    ADD CONSTRAINT time_entry_pkey PRIMARY KEY (id);


--
-- Name: user_grant user_grant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_grant
    ADD CONSTRAINT user_grant_pkey PRIMARY KEY (user_id, key);


--
-- Name: user_phone user_phone_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phone
    ADD CONSTRAINT user_phone_pkey PRIMARY KEY (user_id);


--
-- Name: user_role user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_role
    ADD CONSTRAINT user_role_pkey PRIMARY KEY (user_id, role_id);


--
-- Name: user_team user_team_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_team
    ADD CONSTRAINT user_team_pkey PRIMARY KEY (user_id, team_id);


--
-- Name: workflow_rule workflow_rule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_pkey PRIMARY KEY (id);


--
-- Name: activity_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activity_card_idx ON public.activity USING btree (card_id, created_at DESC);


--
-- Name: activity_org_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activity_org_idx ON public.activity USING btree (organization_id, created_at DESC);


--
-- Name: api_token_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_token_user_idx ON public.api_token USING btree (user_id);


--
-- Name: app_user_org_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_user_org_idx ON public.app_user USING btree (organization_id);


--
-- Name: approval_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX approval_card_idx ON public.approval USING btree (card_id);


--
-- Name: assignment_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assignment_card_idx ON public.assignment USING btree (card_id);


--
-- Name: assignment_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assignment_user_idx ON public.assignment USING btree (user_id);


--
-- Name: attachment_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attachment_card_idx ON public.attachment USING btree (card_id);


--
-- Name: board_member_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX board_member_user_idx ON public.board_member USING btree (user_id);


--
-- Name: card_board_stage_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_board_stage_idx ON public.card USING btree (board_id, stage_id, "position");


--
-- Name: card_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_code_idx ON public.card USING btree (organization_id, code);


--
-- Name: card_completed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_completed_idx ON public.card USING btree (board_id, completed_at) WHERE (completed_at IS NOT NULL);


--
-- Name: card_requester_board_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_requester_board_idx ON public.card USING btree (requester_id, board_id) WHERE (archived_at IS NULL);


--
-- Name: card_requester_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_requester_idx ON public.card USING btree (requester_id);


--
-- Name: card_stage_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX card_stage_idx ON public.card USING btree (stage_id);


--
-- Name: channel_dm_key_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX channel_dm_key_uidx ON public.channel USING btree (organization_id, dm_key) WHERE (dm_key IS NOT NULL);


--
-- Name: checklist_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checklist_card_idx ON public.checklist USING btree (card_id);


--
-- Name: checklist_item_checklist_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checklist_item_checklist_idx ON public.checklist_item USING btree (checklist_id, "position");


--
-- Name: checklist_template_board_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX checklist_template_board_idx ON public.checklist_template USING btree (board_id, name);


--
-- Name: comment_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comment_card_idx ON public.comment USING btree (card_id, created_at);


--
-- Name: field_definition_board_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_definition_board_idx ON public.field_definition USING btree (board_id, "position");


--
-- Name: field_value_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_value_card_idx ON public.field_value USING btree (card_id);


--
-- Name: field_value_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_value_date_idx ON public.field_value USING btree (field_definition_id, value_date) WHERE (value_date IS NOT NULL);


--
-- Name: field_value_member_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_value_member_idx ON public.field_value USING btree (field_definition_id, value_member_id) WHERE (value_member_id IS NOT NULL);


--
-- Name: field_value_num_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_value_num_idx ON public.field_value USING btree (field_definition_id, value_number) WHERE (value_number IS NOT NULL);


--
-- Name: field_value_text_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX field_value_text_idx ON public.field_value USING btree (field_definition_id, value_text) WHERE (value_text IS NOT NULL);


--
-- Name: message_channel_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_channel_idx ON public.message USING btree (channel_id, created_at);


--
-- Name: notification_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_user_idx ON public.notification USING btree (user_id, created_at DESC) WHERE (read_at IS NULL);


--
-- Name: push_subscription_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX push_subscription_user_idx ON public.push_subscription USING btree (user_id);


--
-- Name: role_org_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX role_org_slug_idx ON public.role USING btree (organization_id, slug) WHERE (slug IS NOT NULL);


--
-- Name: shortcut_org_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shortcut_org_idx ON public.shortcut USING btree (organization_id, "position");


--
-- Name: stage_board_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stage_board_idx ON public.stage USING btree (board_id, "position");


--
-- Name: time_entry_card_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX time_entry_card_idx ON public.time_entry USING btree (card_id, started_at);


--
-- Name: time_entry_one_running_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX time_entry_one_running_idx ON public.time_entry USING btree (user_id) WHERE (ended_at IS NULL);


--
-- Name: time_entry_org_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX time_entry_org_period_idx ON public.time_entry USING btree (organization_id, started_at);


--
-- Name: time_entry_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX time_entry_user_idx ON public.time_entry USING btree (user_id, started_at DESC);


--
-- Name: user_phone_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_phone_phone_idx ON public.user_phone USING btree (phone);


--
-- Name: workflow_rule_board_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workflow_rule_board_idx ON public.workflow_rule USING btree (board_id, to_stage_id) WHERE is_active;


--
-- Name: app_user app_user_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER app_user_set_updated_at BEFORE UPDATE ON public.app_user FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: assignment assignment_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER assignment_set_updated_at BEFORE UPDATE ON public.assignment FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attachment attachment_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attachment_set_updated_at BEFORE UPDATE ON public.attachment FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: board board_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER board_set_updated_at BEFORE UPDATE ON public.board FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: card card_assign_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER card_assign_number BEFORE INSERT ON public.card FOR EACH ROW EXECUTE FUNCTION public.assign_card_number();


--
-- Name: card card_completed_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER card_completed_at BEFORE INSERT OR UPDATE OF stage_id ON public.card FOR EACH ROW EXECUTE FUNCTION public.card_set_completed_at();


--
-- Name: card card_count_rework; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER card_count_rework BEFORE UPDATE OF stage_id ON public.card FOR EACH ROW EXECUTE FUNCTION public.card_count_rework();


--
-- Name: card card_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER card_set_updated_at BEFORE UPDATE ON public.card FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: channel channel_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER channel_set_updated_at BEFORE UPDATE ON public.channel FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: checklist checklist_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER checklist_set_updated_at BEFORE UPDATE ON public.checklist FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: comment comment_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER comment_set_updated_at BEFORE UPDATE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: field_definition field_definition_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER field_definition_set_updated_at BEFORE UPDATE ON public.field_definition FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: message message_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER message_set_updated_at BEFORE UPDATE ON public.message FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: organization organization_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organization_set_updated_at BEFORE UPDATE ON public.organization FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: role role_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER role_set_updated_at BEFORE UPDATE ON public.role FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shortcut shortcut_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER shortcut_set_updated_at BEFORE UPDATE ON public.shortcut FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stage stage_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stage_set_updated_at BEFORE UPDATE ON public.stage FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: team team_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER team_set_updated_at BEFORE UPDATE ON public.team FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: workflow_rule workflow_rule_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER workflow_rule_set_updated_at BEFORE UPDATE ON public.workflow_rule FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: activity activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.app_user(id);


--
-- Name: activity activity_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE SET NULL;


--
-- Name: activity activity_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: api_token api_token_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_token
    ADD CONSTRAINT api_token_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: api_token api_token_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_token
    ADD CONSTRAINT api_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: app_user app_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: app_user app_user_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: approval approval_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval
    ADD CONSTRAINT approval_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.app_user(id);


--
-- Name: approval approval_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval
    ADD CONSTRAINT approval_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: approval approval_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval
    ADD CONSTRAINT approval_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: approval approval_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval
    ADD CONSTRAINT approval_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stage(id);


--
-- Name: assignment assignment_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: assignment assignment_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: assignment assignment_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stage(id);


--
-- Name: assignment assignment_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment
    ADD CONSTRAINT assignment_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: board_member board_member_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_member
    ADD CONSTRAINT board_member_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: board_member board_member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_member
    ADD CONSTRAINT board_member_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: board board_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board
    ADD CONSTRAINT board_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: card card_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: card card_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: card card_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.app_user(id);


--
-- Name: card card_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card
    ADD CONSTRAINT card_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stage(id);


--
-- Name: channel_member channel_member_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_member
    ADD CONSTRAINT channel_member_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channel(id) ON DELETE CASCADE;


--
-- Name: channel_member channel_member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_member
    ADD CONSTRAINT channel_member_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: channel channel_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: channel channel_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.team(id);


--
-- Name: checklist checklist_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: checklist_item checklist_item_assignee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES public.app_user(id);


--
-- Name: checklist_item checklist_item_checklist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_checklist_id_fkey FOREIGN KEY (checklist_id) REFERENCES public.checklist(id) ON DELETE CASCADE;


--
-- Name: checklist checklist_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: checklist_template checklist_template_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_template
    ADD CONSTRAINT checklist_template_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: checklist_template checklist_template_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_template
    ADD CONSTRAINT checklist_template_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: comment comment_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.app_user(id);


--
-- Name: comment comment_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: comment comment_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: comment comment_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comment(id) ON DELETE CASCADE;


--
-- Name: field_definition field_definition_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_definition
    ADD CONSTRAINT field_definition_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: field_definition field_definition_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_definition
    ADD CONSTRAINT field_definition_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: field_value field_value_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_value
    ADD CONSTRAINT field_value_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: field_value field_value_field_definition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_value
    ADD CONSTRAINT field_value_field_definition_id_fkey FOREIGN KEY (field_definition_id) REFERENCES public.field_definition(id) ON DELETE CASCADE;


--
-- Name: field_value field_value_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_value
    ADD CONSTRAINT field_value_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: field_value field_value_value_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_value
    ADD CONSTRAINT field_value_value_member_id_fkey FOREIGN KEY (value_member_id) REFERENCES public.app_user(id);


--
-- Name: message message_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.app_user(id);


--
-- Name: message message_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channel(id) ON DELETE CASCADE;


--
-- Name: message message_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: notification notification_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: notification notification_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: push_subscription push_subscription_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscription
    ADD CONSTRAINT push_subscription_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: push_subscription push_subscription_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscription
    ADD CONSTRAINT push_subscription_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: role role_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: shortcut shortcut_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shortcut
    ADD CONSTRAINT shortcut_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: stage stage_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage
    ADD CONSTRAINT stage_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: stage stage_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage
    ADD CONSTRAINT stage_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: team team_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: time_entry time_entry_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entry
    ADD CONSTRAINT time_entry_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: time_entry time_entry_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entry
    ADD CONSTRAINT time_entry_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card(id) ON DELETE CASCADE;


--
-- Name: time_entry time_entry_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entry
    ADD CONSTRAINT time_entry_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: time_entry time_entry_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entry
    ADD CONSTRAINT time_entry_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: user_grant user_grant_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_grant
    ADD CONSTRAINT user_grant_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: user_grant user_grant_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_grant
    ADD CONSTRAINT user_grant_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: user_phone user_phone_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phone
    ADD CONSTRAINT user_phone_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: user_phone user_phone_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_phone
    ADD CONSTRAINT user_phone_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: user_role user_role_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_role
    ADD CONSTRAINT user_role_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.role(id) ON DELETE CASCADE;


--
-- Name: user_role user_role_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_role
    ADD CONSTRAINT user_role_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: user_team user_team_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_team
    ADD CONSTRAINT user_team_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.team(id) ON DELETE CASCADE;


--
-- Name: user_team user_team_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_team
    ADD CONSTRAINT user_team_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;


--
-- Name: workflow_rule workflow_rule_board_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_board_id_fkey FOREIGN KEY (board_id) REFERENCES public.board(id) ON DELETE CASCADE;


--
-- Name: workflow_rule workflow_rule_from_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_from_stage_id_fkey FOREIGN KEY (from_stage_id) REFERENCES public.stage(id);


--
-- Name: workflow_rule workflow_rule_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- Name: workflow_rule workflow_rule_to_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_rule
    ADD CONSTRAINT workflow_rule_to_stage_id_fkey FOREIGN KEY (to_stage_id) REFERENCES public.stage(id);


--
-- Name: activity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;

--
-- Name: activity activity_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_read ON public.activity FOR SELECT TO authenticated USING (((card_id IS NOT NULL) AND public.can_see_card(card_id)));


--
-- Name: api_token; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_token ENABLE ROW LEVEL SECURITY;

--
-- Name: api_token api_token_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY api_token_read ON public.api_token FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: app_user; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_user ENABLE ROW LEVEL SECURITY;

--
-- Name: app_user app_user_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY app_user_read ON public.app_user FOR SELECT TO authenticated USING ((organization_id = public.current_org()));


--
-- Name: approval; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval ENABLE ROW LEVEL SECURITY;

--
-- Name: approval approval_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY approval_read ON public.approval FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: assignment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assignment ENABLE ROW LEVEL SECURITY;

--
-- Name: assignment assignment_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assignment_read ON public.assignment FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: attachment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attachment ENABLE ROW LEVEL SECURITY;

--
-- Name: attachment attachment_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attachment_read ON public.attachment FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: board; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.board ENABLE ROW LEVEL SECURITY;

--
-- Name: board_member; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.board_member ENABLE ROW LEVEL SECURITY;

--
-- Name: board_member board_member_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY board_member_read ON public.board_member FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.has_permission('board:configure'::text)));


--
-- Name: board board_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY board_read ON public.board FOR SELECT TO authenticated USING (public.can_see_board(id));


--
-- Name: card; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card ENABLE ROW LEVEL SECURITY;

--
-- Name: card card_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY card_read ON public.card FOR SELECT TO authenticated USING (public.can_see_card(id));


--
-- Name: channel; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channel ENABLE ROW LEVEL SECURITY;

--
-- Name: channel_member; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channel_member ENABLE ROW LEVEL SECURITY;

--
-- Name: channel_member channel_member_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY channel_member_read ON public.channel_member FOR SELECT TO authenticated USING (public.is_channel_member(channel_id));


--
-- Name: channel channel_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY channel_read ON public.channel FOR SELECT TO authenticated USING (public.is_channel_member(id));


--
-- Name: checklist; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.checklist ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.checklist_item ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item checklist_item_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY checklist_item_read ON public.checklist_item FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.checklist c
  WHERE ((c.id = checklist_item.checklist_id) AND public.can_see_card(c.card_id)))));


--
-- Name: checklist checklist_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY checklist_read ON public.checklist FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: checklist_template; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.checklist_template ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_template checklist_template_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY checklist_template_read ON public.checklist_template FOR SELECT TO authenticated USING (public.can_see_board(board_id));


--
-- Name: comment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comment ENABLE ROW LEVEL SECURITY;

--
-- Name: comment comment_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY comment_read ON public.comment FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: field_definition; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.field_definition ENABLE ROW LEVEL SECURITY;

--
-- Name: field_definition field_definition_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY field_definition_read ON public.field_definition FOR SELECT TO authenticated USING ((((board_id IS NULL) AND (organization_id = public.current_org())) OR public.can_see_board(board_id) OR (EXISTS ( SELECT 1
   FROM public.card c
  WHERE ((c.board_id = field_definition.board_id) AND (c.requester_id = auth.uid()) AND (c.archived_at IS NULL))))));


--
-- Name: field_value; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.field_value ENABLE ROW LEVEL SECURITY;

--
-- Name: field_value field_value_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY field_value_read ON public.field_value FOR SELECT TO authenticated USING (public.can_see_card(card_id));


--
-- Name: message; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message ENABLE ROW LEVEL SECURITY;

--
-- Name: message message_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY message_read ON public.message FOR SELECT TO authenticated USING (public.is_channel_member(channel_id));


--
-- Name: notification; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;

--
-- Name: notification notification_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_read ON public.notification FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: organization org_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_read ON public.organization FOR SELECT TO authenticated USING ((id = public.current_org()));


--
-- Name: organization; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organization ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscription; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_subscription ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscription push_subscription_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_subscription_read ON public.push_subscription FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: role; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role ENABLE ROW LEVEL SECURITY;

--
-- Name: role role_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_read ON public.role FOR SELECT TO authenticated USING ((organization_id = public.current_org()));


--
-- Name: shortcut; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shortcut ENABLE ROW LEVEL SECURITY;

--
-- Name: shortcut shortcut_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shortcut_read ON public.shortcut FOR SELECT TO authenticated USING ((organization_id = public.current_org()));


--
-- Name: stage; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stage ENABLE ROW LEVEL SECURITY;

--
-- Name: stage stage_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stage_read ON public.stage FOR SELECT TO authenticated USING ((public.can_see_board(board_id) OR (EXISTS ( SELECT 1
   FROM public.card c
  WHERE ((c.board_id = stage.board_id) AND (c.requester_id = auth.uid()) AND (c.archived_at IS NULL))))));


--
-- Name: team; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.team ENABLE ROW LEVEL SECURITY;

--
-- Name: team team_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY team_read ON public.team FOR SELECT TO authenticated USING ((organization_id = public.current_org()));


--
-- Name: time_entry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.time_entry ENABLE ROW LEVEL SECURITY;

--
-- Name: time_entry time_entry_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY time_entry_read ON public.time_entry FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (public.has_permission('time:read'::text) AND public.can_see_card(card_id))));


--
-- Name: user_grant; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_grant ENABLE ROW LEVEL SECURITY;

--
-- Name: user_grant user_grant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_grant_read ON public.user_grant FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR ((organization_id = public.current_org()) AND public.has_permission('user:manage'::text))));


--
-- Name: user_phone; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_phone ENABLE ROW LEVEL SECURITY;

--
-- Name: user_phone user_phone_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_phone_read ON public.user_phone FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR ((organization_id = public.current_org()) AND public.has_permission('user:manage'::text))));


--
-- Name: user_role; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_role ENABLE ROW LEVEL SECURITY;

--
-- Name: user_role user_role_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_role_read ON public.user_role FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.app_user u
  WHERE ((u.id = user_role.user_id) AND (u.organization_id = public.current_org())))));


--
-- Name: user_team; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_team ENABLE ROW LEVEL SECURITY;

--
-- Name: user_team user_team_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_team_read ON public.user_team FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.app_user u
  WHERE ((u.id = user_team.user_id) AND (u.organization_id = public.current_org())))));


--
-- Name: workflow_rule; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workflow_rule ENABLE ROW LEVEL SECURITY;

--
-- Name: workflow_rule workflow_rule_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY workflow_rule_read ON public.workflow_rule FOR SELECT TO authenticated USING (public.can_see_board(board_id));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION card_count_rework(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_count_rework() FROM PUBLIC;


--
-- Name: FUNCTION conversation_list(p_user uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.conversation_list(p_user uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.conversation_list(p_user uuid) TO service_role;


--
-- Name: FUNCTION has_access(p_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.has_access(p_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_access(p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.has_access(p_key text) TO service_role;


--
-- Name: FUNCTION time_start(p_user uuid, p_card uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.time_start(p_user uuid, p_card uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.time_start(p_user uuid, p_card uuid) TO service_role;


--
-- Name: FUNCTION time_stop(p_user uuid, p_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.time_stop(p_user uuid, p_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.time_stop(p_user uuid, p_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION transfer_card(p_card uuid, p_target_board uuid, p_actor uuid, p_map jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.transfer_card(p_card uuid, p_target_board uuid, p_actor uuid, p_map jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.transfer_card(p_card uuid, p_target_board uuid, p_actor uuid, p_map jsonb) TO service_role;


--
-- Name: TABLE activity; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activity TO authenticated;


--
-- Name: TABLE app_user; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.app_user TO authenticated;


--
-- Name: TABLE approval; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.approval TO authenticated;


--
-- Name: TABLE assignment; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.assignment TO authenticated;


--
-- Name: TABLE attachment; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.attachment TO authenticated;


--
-- Name: TABLE board; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.board TO authenticated;


--
-- Name: TABLE board_member; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.board_member TO authenticated;


--
-- Name: TABLE card; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.card TO authenticated;


--
-- Name: TABLE channel; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.channel TO authenticated;


--
-- Name: TABLE channel_member; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.channel_member TO authenticated;


--
-- Name: TABLE checklist; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.checklist TO authenticated;


--
-- Name: TABLE checklist_item; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.checklist_item TO authenticated;


--
-- Name: TABLE checklist_template; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.checklist_template TO authenticated;


--
-- Name: TABLE comment; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.comment TO authenticated;


--
-- Name: TABLE field_definition; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.field_definition TO authenticated;


--
-- Name: TABLE field_value; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.field_value TO authenticated;


--
-- Name: TABLE message; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.message TO authenticated;


--
-- Name: TABLE notification; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.notification TO authenticated;


--
-- Name: TABLE organization; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.organization TO authenticated;


--
-- Name: TABLE role; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.role TO authenticated;


--
-- Name: TABLE shortcut; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.shortcut TO authenticated;


--
-- Name: TABLE stage; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.stage TO authenticated;


--
-- Name: TABLE team; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.team TO authenticated;


--
-- Name: TABLE user_grant; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.user_grant TO authenticated;


--
-- Name: TABLE user_phone; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.user_phone TO authenticated;


--
-- Name: TABLE user_role; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.user_role TO authenticated;


--
-- Name: TABLE user_team; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.user_team TO authenticated;


--
-- Name: TABLE workflow_rule; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.workflow_rule TO authenticated;


--
-- PostgreSQL database dump complete
--




-- ── Tempo real: tabelas que avisam as telas abertas ─────────────────────────
alter publication supabase_realtime add table public.stage, public.card, public.channel, public.channel_member, public.message, public.notification;

-- ── Imagens coladas na descrição do cartão ──────────────────────────────────
-- ATENÇÃO (herdado da origem): o balde é PÚBLICO. Quem tiver o endereço de uma
-- imagem consegue abri-la sem login. Ver docs/PENDENCIAS.md.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('card-images', 'card-images', true, 10485760, array['image/png','image/jpeg','image/jpg','image/gif','image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "card_images_public_read" on storage.objects;
create policy "card_images_public_read" on storage.objects
  for select using (bucket_id = 'card-images');
