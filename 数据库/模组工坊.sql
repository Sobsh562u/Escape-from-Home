-- 模组工坊：玩家编写「某处改成某样」→ 登录提交 → 审核中 → 通过后进市场
-- 2026-11-28

create table if not exists public.mods (
  id bigserial primary key,
  title text not null,
  summary text not null default '',
  author_name text not null default '',
  author_pid text not null default '',
  client_id text not null,
  data jsonb not null,                 -- { patches: [ {target, value}, ... ] }
  status text not null default 'pending',   -- pending / approved / rejected
  review_note text not null default '',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists mods_status_idx on public.mods (status, created_at desc);

-- 提交：必须是注册玩家（普通账号即可），不允许管理员特权
-- 可改：难度页签名/开场白/规则说明、结局名/副标题、事件文案、新增事件文案
-- 不可改：血量等数值参数（hp/max/goal/money/day 一律拒）、游戏自带角色（妈妈等，char/role/npc 前缀一律拒）
create or replace function public.submit_mod(
  p_client_id text, p_name text, p_pid text,
  p_title text, p_summary text, p_patches jsonb
) returns jsonb
language plpgsql security definer
as $fn$
declare
  recent int; n int; item jsonb; tgt text; kind text; rest text; base text; field text; v text;
begin
  if length(coalesce(p_client_id, '')) < 8 then
    return jsonb_build_object('ok', false, 'msg', '先登录再提交');
  end if;
  if not exists(select 1 from public.players where client_id = p_client_id) then
    return jsonb_build_object('ok', false, 'msg', '这个账号没注册过，先注册再提交');
  end if;

  p_title := btrim(coalesce(p_title, ''));
  if char_length(p_title) < 2 or char_length(p_title) > 24 then
    return jsonb_build_object('ok', false, 'msg', '标题要 2 到 24 个字');
  end if;
  if jsonb_typeof(p_patches) <> 'array' then
    return jsonb_build_object('ok', false, 'msg', '内容格式不对');
  end if;
  n := jsonb_array_length(p_patches);
  if n < 1 then return jsonb_build_object('ok', false, 'msg', '至少要改一处'); end if;
  if n > 50 then return jsonb_build_object('ok', false, 'msg', '一次最多改 50 处'); end if;
  if length(p_patches::text) > 8192 then
    return jsonb_build_object('ok', false, 'msg', '内容太大了，压缩成 8KB 以内');
  end if;

  for item in select * from jsonb_array_elements(p_patches) loop
    if jsonb_typeof(item) <> 'object' then
      return jsonb_build_object('ok', false, 'msg', '每条都要是 { target, value }');
    end if;
    tgt := btrim(coalesce(item->>'target', ''));
    v := coalesce(item->>'value', '');

    if tgt = '' or position(':' in tgt) = 0 then
      return jsonb_build_object('ok', false, 'msg', '位置写法不对：' || coalesce(tgt, '空') || '（要写成 类型:键.字段）');
    end if;

    kind := lower(split_part(tgt, ':', 1));
    rest := substr(tgt, position(':' in tgt) + 1);

    -- 角色、数值：直接拒绝
    if kind in ('char', 'role', 'npc', 'player', 'actor', 'person', 'mom', 'dad') then
      return jsonb_build_object('ok', false, 'msg', '游戏自带的角色（妈妈这些）不能改，模组只能改文字');
    end if;
    if tgt ~* '(^|[.:])(hp|max|maxhp|goal|money|day|days|blood|life|power|atk|def|coin|coins|score|stage|loop)([.:]|$)'
       or tgt ~* '(加血|扣血|血池|血量|天数|金币|分数)' then
      return jsonb_build_object('ok', false, 'msg', '血量、天数、金币这类数值参数不能改，事件和结局的数值由游戏定死');
    end if;

    if kind not in ('mode', 'ending', 'event', 'text') then
      return jsonb_build_object('ok', false, 'msg', '位置写法不对：' || tgt || '（类型只能是 mode/ending/event/text）');
    end if;

    if kind in ('mode', 'ending') then
      if position('.' in rest) = 0 then
        return jsonb_build_object('ok', false, 'msg', '要写字段：' || tgt || '（比如 mode:orig.name / ending:orig_win.title）');
      end if;
      base  := split_part(rest, '.', 1);
      field := split_part(rest, '.', 2);
      if base = '' then return jsonb_build_object('ok', false, 'msg', '键不能空：' || tgt); end if;
      if kind = 'mode' and field not in ('name', 'text', 'desc') then
        return jsonb_build_object('ok', false, 'msg', '难度的字段只能是 name / text / desc：' || tgt);
      end if;
      if kind = 'ending' and field not in ('title', 'desc') then
        return jsonb_build_object('ok', false, 'msg', '结局的字段只能是 title / desc：' || tgt);
      end if;

    elsif kind = 'event' then
      -- event:e1.text 改已有事件；event:add.1.text 新增事件（血量固定 0）
      base := split_part(rest, '.', 1);
      if base = 'add' then
        field := split_part(rest, '.', 2);
        if field !~ '^[1-5]$' then
          return jsonb_build_object('ok', false, 'msg', '新增事件写法是 event:add.1.text 到 event:add.5.text');
        end if;
        if split_part(rest, '.', 3) <> 'text' then
          return jsonb_build_object('ok', false, 'msg', '新增事件只能写文案：event:add.' || field || '.text');
        end if;
      else
        if base !~ '^e[1-9]$' then
          return jsonb_build_object('ok', false, 'msg', '事件编号要写 e1、e2 这种：' || tgt);
        end if;
        field := nullif(split_part(rest, '.', 2), '');
        if field is not null and field <> 'text' then
          return jsonb_build_object('ok', false, 'msg', '事件只能改文案（.text）：' || tgt);
        end if;
      end if;

    else  -- text: 自由文本
      if rest !~ '^[A-Za-z0-9_\u4e00-\u9fa5]+$' then
        return jsonb_build_object('ok', false, 'msg', '位置写法不对：' || tgt);
      end if;
    end if;

    if char_length(v) > 500 then
      return jsonb_build_object('ok', false, 'msg', '单条内容最多 500 字');
    end if;
    if btrim(v) = '' then
      return jsonb_build_object('ok', false, 'msg', '改成什么不能空：' || tgt);
    end if;
  end loop;

  select count(*) into recent from public.mods
   where client_id = p_client_id and created_at > now() - interval '1 day';
  if recent >= 3 then
    return jsonb_build_object('ok', false, 'msg', '一天最多提交 3 个，明天再来');
  end if;

  insert into public.mods(title, summary, author_name, author_pid, client_id, data)
  values (p_title, left(coalesce(p_summary, ''), 200), left(coalesce(p_name, ''), 12),
          left(coalesce(p_pid, ''), 12), p_client_id, jsonb_build_object('patches', p_patches));

  return jsonb_build_object('ok', true, 'msg', '已提交，等作者审核；通过后会出现在模组市场');
end $fn$;

-- 作者查自己的提交
create or replace function public.my_mods(p_client_id text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if length(coalesce(p_client_id, '')) < 8 then
    return jsonb_build_object('ok', false, 'msg', '先登录');
  end if;
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select id, title, summary, status, review_note, created_at, reviewed_at,
             jsonb_array_length(data->'patches') as patches
        from public.mods where client_id = p_client_id
       order by id desc limit 20
    ) x
  ));
end $fn$;

-- 市场：所有已通过
create or replace function public.list_mods()
returns jsonb
language sql security definer
as $fn$
  select jsonb_build_object('ok', true, 'rows', coalesce(jsonb_agg(x), '[]'::jsonb))
    from (
      select id, title, summary, author_name, status, created_at,
             jsonb_array_length(data->'patches') as patches
        from public.mods
       where status = 'approved'
       order by id desc limit 100
    ) x;
$fn$;

-- 取单个模组的补丁内容（给游戏加载用，只给已通过的）
create or replace function public.mod_get(p_id bigint)
returns jsonb
language sql security definer
as $fn$
  select case when m.id is null then jsonb_build_object('ok', false, 'msg', '没有这个模组')
              else jsonb_build_object('ok', true, 'id', m.id, 'title', m.title,
                                       'author', m.author_name, 'data', m.data) end
    from (select * from public.mods where id = p_id and status = 'approved') m
   union all
  select jsonb_build_object('ok', false, 'msg', '没有这个模组')
   where not exists (select 1 from public.mods where id = p_id and status = 'approved')
   limit 1;
$fn$;

-- 管理：审核列表 / 通过 / 驳回
create or replace function public.ehq_admin_mods(p_key text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select id, title, summary, author_name, author_pid, status, review_note,
             data, jsonb_array_length(data->'patches') as patches, created_at
        from public.mods
       order by case when status = 'pending' then 0 else 1 end, id desc
       limit 100
    ) x
  ));
end $fn$;

create or replace function public.ehq_admin_mod_approve(p_key text, p_id bigint, p_note text default '')
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  update public.mods set status = 'approved', reviewed_at = now(), review_note = left(coalesce(p_note,''), 100)
   where id = p_id and status = 'pending';
  if not found then return jsonb_build_object('ok', false, 'msg', '没有待审的这条'); end if;
  return jsonb_build_object('ok', true);
end $fn$;

create or replace function public.ehq_admin_mod_reject(p_key text, p_id bigint, p_note text default '')
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  update public.mods set status = 'rejected', reviewed_at = now(), review_note = left(coalesce(p_note,''), 100)
   where id = p_id and status = 'pending';
  if not found then return jsonb_build_object('ok', false, 'msg', '没有待审的这条'); end if;
  return jsonb_build_object('ok', true);
end $fn$;
