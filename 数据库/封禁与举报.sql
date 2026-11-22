-- 逃家游戏 · 封禁与举报（在 Supabase SQL Editor 里执行）
-- 原则：举报只入库排队，绝不自动封；封禁必须人工确认后手动执行。
-- 执行位置：Supabase 控制台 → SQL Editor → 粘贴运行。

-- 1) 玩家表加封禁字段（不动现有数据）
alter table public.players
  add column if not exists banned_at   timestamptz,
  add column if not exists banned_until timestamptz,
  add column if not exists ban_reason  text;

comment on column public.players.banned_until is '封禁到期时间，NULL 表示未封；到期后自动可登录';
comment on column public.players.ban_reason  is '封禁理由，仅后台可见';

-- 2) 举报表：只记录，不触发任何封禁
create table if not exists public.reports (
  id            bigserial primary key,
  target_name   text not null,
  target_pid    text,
  reason        text not null,
  reporter_name text,
  reporter_pid  text,
  reporter_cid  text,
  status        text not null default 'pending',   -- pending / rejected / actioned
  handled_at    timestamptz,
  handler_note  text,
  created_at    timestamptz not null default now()
);

create index if not exists reports_status_idx on public.reports (status, created_at desc);
create index if not exists reports_target_idx on public.reports (target_name);

comment on table public.reports is '玩家举报队列，人工审核后才可能封禁';

-- 3) 提交举报（任何访客可调用，包括没注册的游客）
create or replace function public.report_player(
  p_target_name text,
  p_target_pid  text,
  p_reason      text,
  p_reporter_name text default '',
  p_reporter_pid  text default '',
  p_reporter_client_id text default ''
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent int;
begin
  if coalesce(trim(p_target_name), '') = '' then
    return jsonb_build_object('ok', false, 'msg', '目标名字为空');
  end if;
  if coalesce(trim(p_reason), '') = '' then
    return jsonb_build_object('ok', false, 'msg', '写一句理由再提交');
  end if;

  -- 同一设备 24 小时内最多 5 条，挡刷举报
  select count(*) into v_recent
  from reports
  where reporter_cid = coalesce(p_reporter_client_id, '')
    and created_at > now() - interval '24 hours';

  if coalesce(p_reporter_client_id, '') <> '' and v_recent >= 5 then
    return jsonb_build_object('ok', false, 'msg', '今天举报太多了，明天再说');
  end if;

  insert into reports (target_name, target_pid, reason, reporter_name, reporter_pid, reporter_cid)
  values (trim(p_target_name), coalesce(p_target_pid, ''), left(trim(p_reason), 200),
          coalesce(p_reporter_name, ''), coalesce(p_reporter_pid, ''), coalesce(p_reporter_client_id, ''));

  return jsonb_build_object('ok', true, 'msg', '举报已入库，等人工审核（不会自动封）');
end;
$$;

grant execute on function public.report_player(text, text, text, text, text, text) to anon, authenticated;

-- 4) 查某人是否在封禁期（登录/提交前调用；到期自动解）
create or replace function public.is_banned(p_name text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'banned', (banned_until is not null and banned_until > now()),
    'until',  banned_until,
    'reason', ban_reason
  )
  from players
  where name = p_name
  limit 1;
$$;

grant execute on function public.is_banned(text) to anon, authenticated;

-- 5) 人工封禁（只在后台/控制台由你手动调用，前端不暴露）
--    用法示例：select public.ban_player('深度求索', 30, '脚本刷分，经人工核实');
create or replace function public.ban_player(
  p_name   text,
  p_days   int,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pid text;
begin
  select player_id into v_pid from players where name = p_name;
  if v_pid is null then
    return jsonb_build_object('ok', false, 'msg', '没有这个玩家');
  end if;

  update players
     set banned_at = now(),
         banned_until = now() + make_interval(days => greatest(p_days, 1)),
         ban_reason = coalesce(p_reason, '')
   where name = p_name;

  -- 封禁期间下架他在榜上的成绩
  update scores set deleted_at = now()
   where name = p_name and deleted_at is null;

  update reports
     set status = 'actioned', handled_at = now(), handler_note = coalesce(p_reason, '')
   where target_name = p_name and status = 'pending';

  return jsonb_build_object('ok', true, 'player_id', v_pid, 'until', now() + make_interval(days => greatest(p_days, 1)));
end;
$$;

-- 6) 人工解封
create or replace function public.unban_player(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update players
     set banned_at = null, banned_until = null, ban_reason = null
   where name = p_name;
  return jsonb_build_object('ok', true);
end;
$$;

-- 7) 看举报队列（人工审核用；建议只在控制台里跑）
--    select * from reports where status = 'pending' order by created_at;
--    核实后：update reports set status='rejected', handled_at=now(), handler_note='理由' where id = ...;

-- 8) 还有两处必须手动补（SQL Editor 里先取原定义再改）
--    执行：select pg_get_functiondef('login_player'::regprocedure);
--    在函数体开头加：
--      if exists (select 1 from players p where p.name = p_name
--                 and p.banned_until is not null and p.banned_until > now()) then
--        return jsonb_build_object('ok', false, 'msg', '账号被封禁，到期后自动恢复');
--      end if;
--    同理对 submit_score：先取原定义，再在开头加同样的判断，封禁期间拒绝提交成绩。
