-- 投诉中心：旧接口作废 + 新接口走数据库校验
-- 在 Supabase 控制台 → SQL Editor 里整段执行一次。执行后旧口令立刻失效。
-- 客户端只发送你输入的口令，源码里没有任何密钥。

create extension if not exists pgcrypto with schema extensions;

-- 1) 口令哈希表
create table if not exists admin_keys (
  name    text primary key,
  pw_hash text not null
);

-- 2) 写入新口令的哈希（明文 EHQ-562u-4mQ9，区分大小写）
insert into admin_keys (name, pw_hash)
values ('inbox', encode(extensions.digest('EHQ-562u-4mQ9', 'sha256'), 'hex'))
on conflict (name) do update set pw_hash = excluded.pw_hash;

-- 3) 把所有旧名字的函数连同重载一起删掉，旧口令再也调不动
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('list_feedback', 'reply_feedback', 'clear_reply')
  loop
    execute 'drop function ' || r.sig || ' cascade';
  end loop;
end $$;

-- 4) 校验函数
create or replace function ehq_admin_ok(p_name text, p_key text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from admin_keys
     where name = p_name
       and pw_hash = encode(digest(coalesce(p_key, ''), 'sha256'), 'hex')
  );
$$;
revoke all on function ehq_admin_ok(text, text) from public;

-- 5) 读取最近 30 条
create or replace function ehq_fb_list(p_key text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not ehq_admin_ok('inbox', p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  return json_build_object('ok', true, 'rows', (
    select coalesce(json_agg(t), '[]'::json)
      from (select id, name, link, content, reply, created_at
              from feedback
             order by created_at desc
             limit 30) t
  ));
end $$;

-- 6) 回复
create or replace function ehq_fb_reply(p_key text, p_id bigint, p_reply text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v text := btrim(coalesce(p_reply, ''));
begin
  if not ehq_admin_ok('inbox', p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  if length(v) = 0 then
    return json_build_object('ok', false, 'msg', '回复不能为空');
  end if;
  if length(v) > 300 then
    return json_build_object('ok', false, 'msg', '回复最多 300 字');
  end if;
  update feedback set reply = v where id = p_id;
  return json_build_object('ok', true, 'msg', '回复已保存');
end $$;

-- 7) 清空别人冒名的回复
create or replace function ehq_fb_clear(p_key text, p_id bigint)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not ehq_admin_ok('inbox', p_key) then
    return json_build_object('ok', false, 'msg', '口令不对');
  end if;
  update feedback set reply = '' where id = p_id;
  return json_build_object('ok', true, 'msg', '回复已清空');
end $$;

revoke all on function ehq_fb_list(text) from public;
revoke all on function ehq_fb_reply(text, bigint, text) from public;
revoke all on function ehq_fb_clear(text, bigint) from public;

grant execute on function ehq_fb_list(text) to anon, authenticated;
grant execute on function ehq_fb_reply(text, bigint, text) to anon, authenticated;
grant execute on function ehq_fb_clear(text, bigint) to anon, authenticated;
