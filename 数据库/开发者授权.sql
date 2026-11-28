-- 开发者授权：设备码 → 网页确认 → 发 token → 终端用 token 提交模组
-- 2026-11-28

create table if not exists public.dev_pairs (
  code       text primary key,
  status     text not null default 'pending',   -- pending / confirmed / consumed
  token      text not null default '',          -- 只暂存一次，被终端取走后清空
  client_id  text not null default '',
  p_name     text not null default '',
  p_pid      text not null default '',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes'
);

create table if not exists public.dev_tokens (
  hash       text primary key,
  client_id  text not null,
  p_name     text not null default '',
  p_pid      text not null default '',
  label      text not null default '',
  created_at timestamptz not null default now(),
  last_used  timestamptz,
  revoked    boolean not null default false
);

-- 1) 终端发起：生成/刷新设备码，10 分钟内有效
create or replace function public.dev_pair_start(p_code text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  p_code := upper(btrim(coalesce(p_code, '')));
  if p_code !~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$' then
    return jsonb_build_object('ok', false, 'msg', '设备码格式不对');
  end if;
  delete from public.dev_pairs where expires_at < now() - interval '1 day';
  insert into public.dev_pairs (code, status)
  values (p_code, 'pending')
  on conflict (code) do update
    set status = 'pending', token = '', client_id = '', p_name = '', p_pid = '',
        created_at = now(), expires_at = now() + interval '10 minutes';
  return jsonb_build_object('ok', true, 'expires_in', 600);
end $fn$;

-- 2) 网页确认：玩家点了「授权这台设备」才发 token
create or replace function public.dev_pair_confirm(p_code text, p_client_id text)
returns jsonb
language plpgsql security definer
as $fn$
declare v_name text; v_pid text; v_token text; v_hash text;
begin
  p_code := upper(btrim(coalesce(p_code, '')));
  if length(coalesce(p_client_id, '')) < 8 then
    return jsonb_build_object('ok', false, 'msg', '先登录再授权');
  end if;
  select name, player_id into v_name, v_pid from public.players where client_id = p_client_id;
  if v_name is null then
    return jsonb_build_object('ok', false, 'msg', '这个账号没注册过');
  end if;
  if not exists (select 1 from public.dev_pairs where code = p_code and status = 'pending' and expires_at > now()) then
    return jsonb_build_object('ok', false, 'msg', '设备码不存在或已过期，回终端重新打开');
  end if;

  v_token := 'ehq_' || md5(random()::text || clock_timestamp()::text || p_client_id)
                    || substr(md5(random()::text || now()::text), 1, 8);
  v_hash  := md5(v_token);

  insert into public.dev_tokens (hash, client_id, p_name, p_pid, label)
  values (v_hash, p_client_id, left(v_name, 12), left(coalesce(v_pid, ''), 12), 'Terminal');

  update public.dev_pairs
     set status = 'confirmed', token = v_token, client_id = p_client_id,
         p_name = left(v_name, 12), p_pid = left(coalesce(v_pid, ''), 12)
   where code = p_code;

  return jsonb_build_object('ok', true, 'name', v_name, 'player_id', v_pid);
end $fn$;

-- 3) 终端轮询：拿到 token 后立刻作废这次设备码
create or replace function public.dev_pair_poll(p_code text)
returns jsonb
language plpgsql security definer
as $fn$
declare v_row record;
begin
  p_code := upper(btrim(coalesce(p_code, '')));
  select * into v_row from public.dev_pairs where code = p_code;
  if v_row.code is null then return jsonb_build_object('ok', false, 'status', 'none', 'msg', '设备码不存在'); end if;
  if v_row.status = 'pending' then
    if v_row.expires_at < now() then return jsonb_build_object('ok', false, 'status', 'expired', 'msg', '设备码过期了'); end if;
    return jsonb_build_object('ok', true, 'status', 'pending');
  end if;
  if v_row.status = 'confirmed' and v_row.token <> '' then
    update public.dev_pairs set status = 'consumed', token = '' where code = p_code;
    return jsonb_build_object('ok', true, 'status', 'confirmed', 'token', v_row.token,
                              'name', v_row.p_name, 'player_id', v_row.p_pid);
  end if;
  return jsonb_build_object('ok', false, 'status', 'consumed', 'msg', '这个设备码已经用过了');
end $fn$;

-- 4) 校验 token（终端每次提交前调）
create or replace function public.dev_token_check(p_token text)
returns jsonb
language plpgsql security definer
as $fn$
declare v_row record;
begin
  select * into v_row from public.dev_tokens where hash = md5(btrim(coalesce(p_token, ''))) and not revoked;
  if v_row.hash is null then return jsonb_build_object('ok', false, 'msg', 'token 无效或已撤销，重新登录'); end if;
  update public.dev_tokens set last_used = now() where hash = v_row.hash;
  return jsonb_build_object('ok', true, 'name', v_row.p_name, 'player_id', v_row.p_pid, 'client_id', v_row.client_id);
end $fn$;

-- 5) 终端提交模组：走和网页同一套校验（数值、角色一样拒）
create or replace function public.dev_submit(p_token text, p_title text, p_summary text, p_patches jsonb)
returns jsonb
language plpgsql security definer
as $fn$
declare v_row record;
begin
  select * into v_row from public.dev_tokens where hash = md5(btrim(coalesce(p_token, ''))) and not revoked;
  if v_row.hash is null then return jsonb_build_object('ok', false, 'msg', 'token 无效或已撤销，重新登录'); end if;
  update public.dev_tokens set last_used = now() where hash = v_row.hash;
  return public.submit_mod(v_row.client_id, v_row.p_name, v_row.p_pid, p_title, p_summary, p_patches);
end $fn$;

-- 6) 撤销本人所有 token（网页里点「断开所有设备」）
create or replace function public.dev_token_revoke_all(p_client_id text)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if length(coalesce(p_client_id, '')) < 8 then return jsonb_build_object('ok', false, 'msg', '先登录'); end if;
  update public.dev_tokens set revoked = true where client_id = p_client_id and not revoked;
  return jsonb_build_object('ok', true);
end $fn$;
