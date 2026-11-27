-- Motor de quadros — cria a empresa e os papéis iniciais.
--
-- ANTES DE RODAR: troque o nome e o domínio de e-mail nas duas linhas marcadas.
-- Pode rodar de novo sem duplicar nada.
--
-- Importante: nesta fase o sistema atende UMA empresa por banco (ele usa a
-- primeira empresa cadastrada). Ver docs/PENDENCIAS.md, item 1.
--
-- Depois de rodar: o primeiro usuário interno que entrar vira Gestor.

do $$
declare
  v_nome    text := 'Empresa de teste';      -- << TROCAR
  v_dominio text := 'exemplo.com.br';         -- << TROCAR (domínio dos e-mails internos)
  v_org     uuid;
  r         record;
begin
  select id into v_org from organization where email_domain = v_dominio limit 1;
  if v_org is null then
    insert into organization (name, email_domain) values (v_nome, v_dominio) returning id into v_org;
  end if;

  for r in
    select * from (values
      ('Externo', 'externo', array['card:read','card:update','comment:create']),
      ('Membro interno', 'interno', array['board:read','card:read','card:create','card:update','card:move',
        'comment:create','channel:read','channel:post','card:read_all']),
      ('Gestor de área', 'area', array['board:read','card:read','card:create','card:update','card:move',
        'card:assign','comment:create','channel:read','channel:post','channel:manage','stage:manage',
        'time:read','card:read_all']),
      ('Gestor', 'gestor', array['board:read','board:configure','card:read','card:create','card:update',
        'card:move','card:assign','comment:create','channel:read','channel:post','channel:manage',
        'field:manage','stage:manage','user:manage','workflow:manage','report:read','time:read','card:read_all']),
      ('Gestor Master', 'master', array['board:read','board:configure','card:read','card:create','card:update',
        'card:move','card:assign','card:transfer','comment:create','channel:read','channel:post','channel:manage',
        'field:manage','stage:manage','workflow:manage','user:manage','role:manage','report:read',
        'time:read','card:read_all'])
    ) as t(nome, slug, perms)
  loop
    if not exists (select 1 from role where organization_id = v_org and slug = r.slug) then
      insert into role (organization_id, name, slug, permissions)
      values (v_org, r.nome, r.slug, to_jsonb(r.perms));
    end if;
  end loop;

  raise notice 'Empresa pronta: % (%)', v_nome, v_org;
end $$;
