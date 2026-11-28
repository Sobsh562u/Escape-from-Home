-- ============================================================
-- 云端钱包（金币上服务器）
-- 目的：金币不再只存在浏览器 localStorage，改币要过密码校验，
--       商店扣款由服务端按自己的价格表扣，客户端不能自报价格。
-- 依赖：players 表（name 唯一、pass_hash = crypt(password, pass_hash)）
-- ============================================================

create table if not exists public.wallets (
  name        text primary key,
  coins       int  not null default 0 check (coins >= 0),
  bought      jsonb not null default '{}'::jsonb,   -- 永久道具购买记录 {phone:true}
  earn_day    date not null default current_date,   -- 今日收入统计日期
  earn_today  int  not null default 0 check (earn_today >= 0),
  updated_at  timestamptz not null default now()
);

-- 道具价格表：唯一权威在这里，客户端只管说"我要买哪个"
create or replace function public.wallet_price(p_item text)
returns int language sql immutable as $$
  select case p_item
    when 'lamp'      then 6
    when 'lucky'     then 8
    when 'phone'     then 25
    when 'phone_mid' then 45
    when 'phone_new' then 50
    when 'sim'       then 8
    when 'battery'   then 6
    when 'pbank_s'   then 4
    when 'pbank_l'   then 12
    when 'pc'        then 60
    when 'earbuds'   then 7
    when 'review'    then 6
  end
$$;

-- 永久道具（买了就一直在，服务端拒绝重复购买）
create or replace function public.wallet_perm(p_item text)
returns boolean language sql immutable as $$
  select p_item in ('phone','phone_mid','phone_new','sim','pc')
$$;

-- 内部鉴权：名字 + 密码，走和登录同一套 crypt 校验
create or replace function public.wallet_auth(p_name text, p_password text)
returns text language plpgsql security definer set search_path to 'public','extensions' as $$
declare r text;
begin
  select name into r from public.players
   where lower(name) = lower(btrim(coalesce(p_name,'')))
     and pass_hash = extensions.crypt(coalesce(p_password,''), pass_hash);
  return r;
end $$;

-- 读余额
create or replace function public.wallet_get(p_name text, p_password text)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare v text; w public.wallets;
begin
  v := public.wallet_auth(p_name, p_password);
  if v is null then return json_build_object('ok', false, 'msg', '名字或密码不对'); end if;

  insert into public.wallets(name) values (v) on conflict (name) do nothing;
  select * into w from public.wallets where name = v;

  return json_build_object('ok', true, 'name', v, 'coins', w.coins,
    'bought', w.bought, 'earn_today', case when w.earn_day = current_date then w.earn_today else 0 end);
end $$;

-- 赚金币：单次最多 8（一局结算的上限），每天最多 40
create or replace function public.wallet_earn(p_name text, p_password text, p_delta int)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare v text; w public.wallets; cap int := 40; d int;
begin
  v := public.wallet_auth(p_name, p_password);
  if v is null then return json_build_object('ok', false, 'msg', '名字或密码不对'); end if;

  d := coalesce(p_delta, 0);
  if d < 1 or d > 8 then return json_build_object('ok', false, 'msg', '单次收入只能是 1 到 8 个金币'); end if;

  insert into public.wallets(name) values (v) on conflict (name) do nothing;
  select * into w from public.wallets where name = v;

  if w.earn_day <> current_date then
    update public.wallets set earn_day = current_date, earn_today = 0 where name = v;
    w.earn_today := 0;
  end if;

  if w.earn_today + d > cap then
    return json_build_object('ok', false, 'msg', '今天的金币到上限了（' || cap || ' 个），明天再来',
      'coins', w.coins);
  end if;

  update public.wallets
     set coins = coins + d, earn_today = earn_today + d, updated_at = now()
   where name = v returning coins into w.coins;

  return json_build_object('ok', true, 'coins', w.coins);
end $$;

-- 买东西：价格由服务端定，余额不足或重复买永久道具一律拒
create or replace function public.wallet_spend(p_name text, p_password text, p_item text)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare v text; w public.wallets; pr int;
begin
  v := public.wallet_auth(p_name, p_password);
  if v is null then return json_build_object('ok', false, 'msg', '名字或密码不对'); end if;

  pr := public.wallet_price(p_item);
  if pr is null then return json_build_object('ok', false, 'msg', '没有这个道具'); end if;

  insert into public.wallets(name) values (v) on conflict (name) do nothing;
  select * into w from public.wallets where name = v;

  if public.wallet_perm(p_item) and (w.bought ? p_item) then
    return json_build_object('ok', false, 'already', true, 'msg', '这个永久道具你已经有了', 'coins', w.coins);
  end if;

  if w.coins < pr then
    return json_build_object('ok', false, 'msg', '金币不够，还差 ' || (pr - w.coins) || ' 个', 'coins', w.coins);
  end if;

  update public.wallets
     set coins = coins - pr,
         bought = case when public.wallet_perm(p_item)
                       then bought || jsonb_build_object(p_item, true)
                       else bought end,
         updated_at = now()
   where name = v
   returning coins, bought into w.coins, w.bought;

  return json_build_object('ok', true, 'coins', w.coins, 'item', p_item, 'price', pr, 'bought', w.bought);
end $$;

grant execute on function public.wallet_get(text, text) to anon, authenticated;
grant execute on function public.wallet_earn(text, text, int) to anon, authenticated;
grant execute on function public.wallet_spend(text, text, text) to anon, authenticated;
