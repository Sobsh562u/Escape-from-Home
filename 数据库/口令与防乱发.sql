-- 投诉中心：口令改到服务端校验 + 清理乱发回复
-- 在 Supabase 控制台 → SQL Editor 里整段执行一次即可。
-- 执行后，客户端只发送你输入的口令，源码里不再有任何密钥。

-- 1) 用 pgcrypto 算哈希（Supabase 自带，放在 extensions 架构里）
create extension if not exists pgcrypto with schema extensions;

-- 2) 口令哈希表：库里只存哈希，不存明文
create table if not exists admin_keys (
  name    text primary key,
  pw_hash text not null
);

-- 3) 写入投诉中心口令的哈希
--    口令原文是 wW（区分大小写）。想换口令，把下面字符串换成新口令，重新执行本段。
insert into admin_keys (name, pw_hash)
values ('inbox', encode(extensions.digest('wW', 'sha256'), 'hex'))
on conflict (name) do update set pw_hash = excluded.pw_hash;

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

-- 5) 读取最近 30 条：必须口令正确
create or replace function list_feedback(p_key text)
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

-- 6) 回复：必须口令正确，长度限制 1–300
create or replace function reply_feedback(p_key text, p_id bigint, p_reply text)
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

-- 7) 删掉别人冒名发的回复：必须口令正确
create or replace function clear_reply(p_key text, p_id bigint)
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
