-- 手机短信：玩家之间真实收发 + 附件 + 容量上限
-- 在 Supabase 控制台 → SQL Editor 里整段执行一次。

create table if not exists ehq_msgs (
  id          bigserial primary key,
  sender_id   text not null,
  sender_name text,
  receiver_id text not null,
  body        text not null default '',
  attach_name text,
  attach_type text,
  attach_data text,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);

create index if not exists ehq_msgs_to_idx on ehq_msgs (receiver_id, created_at desc);
create index if not exists ehq_msgs_from_idx on ehq_msgs (sender_id, created_at desc);

-- 设备校验：玩家 ID 必须和当前设备的 client_id 对得上
create or replace function ehq_sms_ok(p_me text, p_cid text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from players
     where player_id = p_me
       and client_id = p_cid
  );
$$;
revoke all on function ehq_sms_ok(text, text) from public;

-- 发短信（含附件）
create or replace function ehq_sms_send(
  p_from text, p_cid text, p_to text,
  p_body text, p_aname text default null, p_adata text default null, p_atype text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_cnt  int;
begin
  if not ehq_sms_ok(p_from, p_cid) then
    return json_build_object('ok', false, 'msg', '先登录账号才能发短信');
  end if;
  if p_to is null or length(btrim(p_to)) = 0 then
    return json_build_object('ok', false, 'msg', '收件人空着');
  end if;
  if not exists (select 1 from players where player_id = btrim(p_to)) then
    return json_build_object('ok', false, 'msg', '这个玩家 ID 不存在');
  end if;
  if btrim(p_to) = p_from then
    return json_build_object('ok', false, 'msg', '别给自己发');
  end if;
  if length(v_body) = 0 and (p_adata is null or length(p_adata) = 0) then
    return json_build_object('ok', false, 'msg', '什么都没写');
  end if;
  if length(v_body) > 500 then
    return json_build_object('ok', false, 'msg', '一条最多 500 字');
  end if;
  if p_adata is not null and length(p_adata) > 300000 then
    return json_build_object('ok', false, 'msg', '附件太大，单条最多 200KB');
  end if;

  select count(*) into v_cnt
    from ehq_msgs
   where sender_id = p_from or receiver_id = p_from;
  if v_cnt >= 60 then
    return json_build_object('ok', false, 'msg', '聊得太火热了，先删几条旧消息吧');
  end if;

  insert into ehq_msgs (sender_id, sender_name, receiver_id, body, attach_name, attach_type, attach_data)
  values (p_from,
          (select name from players where player_id = p_from),
          btrim(p_to), v_body,
          nullif(btrim(coalesce(p_aname, '')), ''),
          nullif(btrim(coalesce(p_atype, '')), ''),
          nullif(coalesce(p_adata, ''), '')
  );

  return json_build_object('ok', true, 'msg', '发出去了');
end $$;

-- 收件箱（读一次就标记已读）
create or replace function ehq_sms_inbox(p_me text, p_cid text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_cnt int; v_rows json;
begin
  if not ehq_sms_ok(p_me, p_cid) then
    return json_build_object('ok', false, 'msg', '先登录账号');
  end if;
  select count(*) into v_cnt from ehq_msgs where sender_id = p_me or receiver_id = p_me;
  select coalesce(json_agg(t), '[]'::json) into v_rows
    from (select id, sender_id, sender_name, body, attach_name, attach_type,
                 case when attach_data is null then null else length(attach_data) end as attach_len,
                 created_at, read_at
            from ehq_msgs
           where receiver_id = p_me
           order by created_at desc
           limit 30) t;
  update ehq_msgs set read_at = coalesce(read_at, now()) where receiver_id = p_me and read_at is null;
  return json_build_object('ok', true, 'rows', v_rows, 'used', v_cnt, 'cap', 60);
end $$;

-- 发件箱
create or replace function ehq_sms_outbox(p_me text, p_cid text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_cnt int; v_rows json;
begin
  if not ehq_sms_ok(p_me, p_cid) then
    return json_build_object('ok', false, 'msg', '先登录账号');
  end if;
  select count(*) into v_cnt from ehq_msgs where sender_id = p_me or receiver_id = p_me;
  select coalesce(json_agg(t), '[]'::json) into v_rows
    from (select id, receiver_id, body, attach_name, attach_type,
                 case when attach_data is null then null else length(attach_data) end as attach_len,
                 created_at
            from ehq_msgs
           where sender_id = p_me
           order by created_at desc
           limit 30) t;
  return json_build_object('ok', true, 'rows', v_rows, 'used', v_cnt, 'cap', 60);
end $$;

-- 取附件内容（只有收发双方能取）
create or replace function ehq_sms_attach(p_me text, p_cid text, p_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  if not ehq_sms_ok(p_me, p_cid) then
    return json_build_object('ok', false, 'msg', '先登录账号');
  end if;
  select json_build_object('ok', true, 'name', attach_name, 'type', attach_type, 'data', attach_data)
    into v
    from ehq_msgs
   where id = p_id and (sender_id = p_me or receiver_id = p_me);
  return coalesce(v, json_build_object('ok', false, 'msg', '找不到这条'));
end $$;

-- 删一条（收发双方都能删自己这边的）
create or replace function ehq_sms_del(p_me text, p_cid text, p_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not ehq_sms_ok(p_me, p_cid) then
    return json_build_object('ok', false, 'msg', '先登录账号');
  end if;
  delete from ehq_msgs where id = p_id and (sender_id = p_me or receiver_id = p_me);
  return json_build_object('ok', true, 'msg', '删掉了');
end $$;

revoke all on function ehq_sms_send(text, text, text, text, text, text, text) from public;
revoke all on function ehq_sms_inbox(text, text) from public;
revoke all on function ehq_sms_outbox(text, text) from public;
revoke all on function ehq_sms_attach(text, text, bigint) from public;
revoke all on function ehq_sms_del(text, text, bigint) from public;

grant execute on function ehq_sms_send(text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function ehq_sms_inbox(text, text) to anon, authenticated;
grant execute on function ehq_sms_outbox(text, text) to anon, authenticated;
grant execute on function ehq_sms_attach(text, text, bigint) to anon, authenticated;
grant execute on function ehq_sms_del(text, text, bigint) to anon, authenticated;
