-- 访问记录：每次访问落 IP + UA，用来判人机
-- 2026-11-28

alter table public.visit_log add column if not exists ip text;
alter table public.visit_log add column if not exists bot boolean not null default false;
create index if not exists visit_log_created_idx on public.visit_log (created_at desc);
create index if not exists visit_log_ip_idx on public.visit_log (ip);

create or replace function public.log_visit(
  p_client_id text, p_ua text default '', p_ref text default '', p_path text default ''
) returns json
language plpgsql security definer
set search_path to 'public'
as $fn$
declare v_ip text; v_hdr json; v_ua text;
begin
  if coalesce(btrim(p_client_id), '') = '' then
    return json_build_object('ok', false, 'msg', '缺少 client_id');
  end if;

  -- 客户端真实 IP：PostgREST 会把转发头塞进 request.headers
  begin
    v_hdr := current_setting('request.headers', true)::json;
    v_ip := nullif(btrim(split_part(coalesce(v_hdr->>'x-forwarded-for', ''), ',', 1)), '');
    if v_ip is null then
      v_ip := nullif(btrim(coalesce(v_hdr->>'cf-connecting-ip', '')), '');
    end if;
  exception when others then
    v_ip := null;
  end;

  v_ua := left(coalesce(p_ua, ''), 300);

  insert into public.visit_log (client_id, ua, referrer, path, ip, bot)
  values (
    left(p_client_id, 64), v_ua,
    left(coalesce(p_ref, ''), 300),
    left(coalesce(p_path, ''), 200),
    v_ip,
    v_ua ~* '(bot|spider|crawler|headless|curl|wget|python-requests|scrapy|go-http|okhttp|libwww|httpclient)'
  );
  return json_build_object('ok', true);
end $fn$;

create or replace function public.ehq_admin_visits(p_key text, p_limit integer default 50)
returns jsonb
language plpgsql security definer
as $fn$
begin
  if not ehq_admin_ok(p_key) then
    return jsonb_build_object('ok', false, 'msg', '口令不对');
  end if;
  return jsonb_build_object(
    'ok', true,
    'rows', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select id, ip, ua, path, referrer, bot, created_at
          from public.visit_log
         order by id desc
         limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) x
    ),
    'hot', (
      select coalesce(jsonb_agg(h), '[]'::jsonb) from (
        select ip,
               count(*) as n,
               min(created_at) as first_seen,
               max(created_at) as last_seen,
               bool_or(bot) as has_bot
          from public.visit_log
         where created_at > now() - interval '24 hours' and ip is not null
         group by ip
        having count(*) >= 3
         order by n desc
         limit 20
      ) h
    ),
    'total24', (select count(*) from public.visit_log where created_at > now() - interval '24 hours')
  );
end $fn$;
