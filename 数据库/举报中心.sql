-- 举报中心 · 数据库部分（在 Supabase SQL Editor 里整段跑一次即可）
-- 设计原则：列结构不确定的表用 to_jsonb 整体返回，避免字段名对不上。

-- 1) 封禁表
create table if not exists ehq_bans (
  id bigserial primary key,
  target_name text not null,
  target_pid text default '',
  days int not null,              -- 0 = 永久
  reason text default '',
  by_admin text default '',
  created_at timestamptz default now(),
  until timestamptz,              -- days>0 时写入到期时间，0 为 null
  lifted boolean default false
);
create index if not exists ehq_bans_name_idx on ehq_bans (lower(target_name));

-- 2) 管理口令校验（明文口令只活在函数体里，前端拿不到）
create or replace function ehq_admin_ok(p_key text)
returns boolean language sql immutable as $$
  select coalesce(p_key, '') = '<口令>';
$$;

-- 3) 列出举报（表名未知：按候选自动探测，仍兼容 to_jsonb 整行返回）
create or replace function ehq_admin_reports(p_key text, p_limit int default 60)
returns json language plpgsql security definer as $$
declare
  r json;
  tname text;
  cand text[] := array['reports','report','ehq_reports','player_reports','complaints','ehq_feedback','feedback','tips'];
begin
  if not ehq_admin_ok(p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  foreach tname in array cand loop
    if to_regclass('public.' || tname) is not null then
      execute format(
        'select coalesce(json_agg(to_jsonb(x) order by 1 desc), ''[]''::json)
           from (select * from public.%I limit %s) x', tname, greatest(1, least(p_limit, 200)))
        into r;
      return json_build_object('ok', true, 'rows', r, 'table', tname);
    end if;
  end loop;
  return json_build_object('ok', false, 'msg', '没找到举报表，候选都试过了：' || array_to_string(cand, '、'));
exception when others then
  return json_build_object('ok', false, 'msg', SQLERRM);
end $$;

-- 3b) 诊断：列出这个库里所有表名（跑了这一段，我就知道举报落在哪张表）
create or replace function ehq_admin_list_tables(p_key text)
returns json language sql security definer as $$
  select case when not ehq_admin_ok(p_key) then json_build_object('ok', false, 'msg', '口令不对')
  else json_build_object('ok', true, 'tables', coalesce((
    select json_agg(table_name order by table_name)
      from information_schema.tables
     where table_schema = 'public'), '[]'::json)) end;
$$;

-- 4) 封禁（写 ehq_bans）
create or replace function ehq_admin_ban(p_key text, p_name text, p_pid text default '', p_days int default 1, p_reason text default '', p_admin text default '作者')
returns json language plpgsql security definer as $$
declare uid bigint;
begin
  if not ehq_admin_ok(p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return json_build_object('ok', false, 'msg', '对象为空');
  end if;
  insert into ehq_bans (target_name, target_pid, days, reason, by_admin, until)
  values (p_name, coalesce(p_pid, ''), p_days, coalesce(p_reason, ''), p_admin,
          case when p_days > 0 then now() + (p_days || ' days')::interval else null end)
  returning id into uid;
  return json_build_object('ok', true, 'id', uid,
    'until', case when p_days > 0 then (now() + (p_days || ' days')::interval)::text else '永久' end);
end $$;

-- 5) 解封
create or replace function ehq_admin_unban(p_key text, p_name text)
returns json language plpgsql security definer as $$
begin
  if not ehq_admin_ok(p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  update ehq_bans set lifted = true where lower(target_name) = lower(p_name) and lifted = false and (until is null or until > now());
  return json_build_object('ok', true);
end $$;

-- 6) 查某人是否在封禁中（登录前调用，任何人可调，只返回状态不返回细节）
create or replace function ehq_ban_check(p_name text)
returns json language plpgsql security definer as $$
declare b record;
begin
  select * into b from ehq_bans
   where lower(target_name) = lower(coalesce(p_name,'')) and lifted = false
     and (until is null or until > now())
   order by created_at desc limit 1;
  if not found then
    return json_build_object('banned', false);
  end if;
  return json_build_object('banned', true, 'days', b.days, 'until', b.until, 'reason', b.reason);
end $$;

-- 7) 权限：只允许 anon 调这几个函数，不允许直接读写表
revoke all on ehq_bans from anon, authenticated;
grant execute on function ehq_admin_ok(text) to anon, authenticated;
grant execute on function ehq_admin_list_tables(text) to anon, authenticated;
grant execute on function ehq_admin_reports(text, int) to anon, authenticated;
grant execute on function ehq_admin_ban(text, text, text, int, text, text) to anon, authenticated;
grant execute on function ehq_admin_unban(text, text) to anon, authenticated;
grant execute on function ehq_ban_check(text) to anon, authenticated;
