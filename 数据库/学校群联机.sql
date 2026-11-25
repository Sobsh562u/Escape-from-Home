-- 学校群联机：一张群消息表 + 匿名可读写
create table if not exists public.ehq_group_msgs (
  id bigserial primary key,
  room text not null default 'school',
  pid text not null,
  name text not null,
  body text not null check (char_length(body) between 1 and 200),
  created_at timestamptz not null default now()
);

create index if not exists ehq_group_msgs_room_id_idx on public.ehq_group_msgs (room, id desc);

alter table public.ehq_group_msgs enable row level security;

drop policy if exists ehq_group_read on public.ehq_group_msgs;
create policy ehq_group_read on public.ehq_group_msgs
  for select to anon, authenticated using (true);

drop policy if exists ehq_group_write on public.ehq_group_msgs;
create policy ehq_group_write on public.ehq_group_msgs
  for insert to anon, authenticated with check (true);
