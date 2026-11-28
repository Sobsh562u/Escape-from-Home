-- 模组编号与官方推荐栏：编号只由审核通过时分配，玩家提交时带不进来
-- 2026-11-28

-- 1) mods 加编号（三位：001、002……），唯一
alter table public.mods add column if not exists code text;
create unique index if not exists mods_code_uidx on public.mods (code) where code is not null;

-- 2) 审核通过时分配编号；已分配过的保持不变
create or replace function public.ehq_admin_mod_approve(p_key text, p_id bigint, p_note text default '')
returns jsonb
language plpgsql security definer
as $fn$
declare v_next int; v_code text;
begin
  if not public.ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;

  -- 编号只能在这里生成：全局锁一下，防止两个人同时通过时撞号
  perform pg_advisory_xact_lock(hashtext('ehq_mod_code'));
  select coalesce(max(nullif(code, '')::int), 0) + 1 into v_next from public.mods;
  v_code := lpad(v_next::text, 3, '0');

  update public.mods
     set status = 'approved', reviewed_at = now(), review_note = left(coalesce(p_note, ''), 100),
         code = coalesce(nullif(code, ''), v_code)
   where id = p_id and status = 'pending';
  if not found then return jsonb_build_object('ok', false, 'msg', '没有待审的这条'); end if;

  return jsonb_build_object('ok', true, 'code', (select code from public.mods where id = p_id));
end $fn$;

-- 3) 市场带编号
create or replace function public.list_mods()
returns jsonb
language sql security definer
as $fn$
  select jsonb_build_object('ok', true, 'rows', coalesce(jsonb_agg(x), '[]'::jsonb))
    from (
      select id, code, title, summary, author_name, status, created_at,
             jsonb_array_length(data->'patches') as patches
        from public.mods
       where status = 'approved'
       order by code nulls last, id desc limit 100
    ) x;
$fn$;

-- 4) 按编号读模组（?mod=001）
create or replace function public.mod_get_by_code(p_code text)
returns jsonb
language sql security definer
as $fn$
  select case when m.id is null then jsonb_build_object('ok', false, 'msg', '没有这个编号的模组')
              else jsonb_build_object('ok', true, 'id', m.id, 'code', m.code, 'title', m.title,
                                       'author', m.author_name, 'data', m.data) end
    from (select * from public.mods where code = p_code and status = 'approved') m
   union all
  select jsonb_build_object('ok', false, 'msg', '没有这个编号的模组')
   where not exists (select 1 from public.mods where code = p_code and status = 'approved')
   limit 1;
$fn$;

-- 5) 成绩带模组编号：只有官方推荐（审核通过）的模组才允许把编号写进榜单
alter table public.scores add column if not exists mod_code text not null default '';

-- 旧版是 7 个参数，create or replace 不会覆盖它，两个重载同时存在会让接口返回
-- 300 PGRST203（"挑不出该调哪个"），所以必须先删旧签名
drop function if exists public.submit_score(text, text, text, text, integer, integer, integer);

create or replace function public.submit_score(
  p_name text, p_client_id text, p_mode text, p_ending text,
  p_days integer, p_stations integer, p_money integer, p_mod_code text default ''
) returns json
language plpgsql security definer
set search_path to 'public'
as $fn$
declare v_pid text; v_best record; v_recent int; v_day int; v_code text;
begin
  select player_id into v_pid from public.players where name = p_name and client_id = p_client_id;
  if v_pid is null then
    return json_build_object('ok', false, 'msg', '账号对不上，请重新登录');
  end if;

  -- 推荐栏只代表好玩，模组局一律不上榜：这里直接忽略编号，不写进成绩
  v_code := '';

  delete from public.score_submit_log where created_at < now() - interval '2 days';
  select count(*) into v_recent from public.score_submit_log
   where client_id = p_client_id and created_at > now() - interval '1 minute';
  if v_recent >= 3 then
    return json_build_object('ok', false, 'msg', '提交太快了，歇一分钟再试');
  end if;
  select count(*) into v_day from public.score_submit_log
   where client_id = p_client_id and created_at > now() - interval '1 day';
  if v_day >= 30 then
    return json_build_object('ok', false, 'msg', '今天提交得够多了，明天再来');
  end if;
  insert into public.score_submit_log(client_id) values (p_client_id);

  p_days := greatest(0, least(coalesce(p_days, 0), 20000));
  p_stations := greatest(0, least(coalesce(p_stations, 0), 20000));
  p_money := greatest(0, least(coalesce(p_money, 0), 1000000));
  perform public.last_score_cleanup();
  select id, days, stations into v_best from public.scores
    where player_id = v_pid and deleted_at is null
    order by days desc, stations desc limit 1;
  if v_best.id is not null and (v_best.days > p_days or (v_best.days = p_days and v_best.stations > p_stations)) then
    return json_build_object('ok', true, 'updated', false, 'days', v_best.days, 'stations', v_best.stations);
  end if;
  delete from public.scores where player_id = v_pid and deleted_at is null;
  insert into public.scores(mode, ending, days, stations, money, name, client_id, player_id, mod_code)
  values (left(coalesce(p_mode, 'endless'), 20), left(coalesce(p_ending, 'died'), 20), p_days, p_stations,
          p_money, p_name, p_client_id, v_pid, v_code);
  return json_build_object('ok', true, 'updated', true, 'days', p_days, 'stations', p_stations, 'mod_code', v_code);
end $fn$;

-- 6) 我的提交、审核列表也带编号
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
      select id, code, title, summary, status, review_note, created_at, reviewed_at,
             jsonb_array_length(data->'patches') as patches
        from public.mods where client_id = p_client_id
       order by id desc limit 20
    ) x
  ));
end $fn$;

create or replace function public.ehq_admin_mods(p_key text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select id, code, title, summary, author_name, author_pid, status, review_note,
             data, jsonb_array_length(data->'patches') as patches, created_at
        from public.mods
       order by case when status = 'pending' then 0 else 1 end, id desc
       limit 100
    ) x
  ));
end $fn$;
