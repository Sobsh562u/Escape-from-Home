-- 官方推荐位：名额有限（最多 9 个），只奖励“好玩”，不影响榜单
-- 2026-11-28

alter table public.mods add column if not exists featured boolean not null default false;
alter table public.mods add column if not exists featured_at timestamptz;

-- 市场：推荐的排前面，带 featured 标记
create or replace function public.list_mods()
returns jsonb
language sql security definer
as $fn$
  select jsonb_build_object('ok', true, 'rows', coalesce(jsonb_agg(x), '[]'::jsonb))
    from (
      select id, code, title, summary, author_name, status, featured, created_at,
             jsonb_array_length(data->'patches') as patches
        from public.mods
       where status = 'approved'
       order by featured desc, code nulls last, id desc limit 100
    ) x;
$fn$;

-- 设置/撤销推荐位，最多 9 个
create or replace function public.ehq_admin_mod_feature(p_key text, p_id bigint, p_on boolean default true)
returns jsonb
language plpgsql security definer
as $fn$
declare v_cnt int;
begin
  if not public.ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  if not exists (select 1 from public.mods where id = p_id and status = 'approved') then
    return jsonb_build_object('ok', false, 'msg', '只有已经通过的模组能进推荐位');
  end if;
  if coalesce(p_on, true) then
    select count(*) into v_cnt from public.mods where featured and status = 'approved';
    if exists (select 1 from public.mods where id = p_id and featured) then
      return jsonb_build_object('ok', true, 'msg', '它已经在推荐位了');
    end if;
    if v_cnt >= 9 then
      return jsonb_build_object('ok', false, 'msg', '推荐位满了（最多 9 个），先撤一个再加');
    end if;
    update public.mods set featured = true, featured_at = now() where id = p_id;
    return jsonb_build_object('ok', true, 'msg', '已挂上推荐位');
  else
    update public.mods set featured = false, featured_at = null where id = p_id;
    return jsonb_build_object('ok', true, 'msg', '已撤下推荐位');
  end if;
end $fn$;

-- 审核列表也带推荐状态
create or replace function public.ehq_admin_mods(p_key text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then return jsonb_build_object('ok', false, 'msg', '口令不对'); end if;
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select id, code, title, summary, author_name, author_pid, status, review_note, featured,
             data, jsonb_array_length(data->'patches') as patches, created_at
        from public.mods
       order by case when status = 'pending' then 0 else 1 end, featured desc, id desc
       limit 100
    ) x
  ));
end $fn$;
