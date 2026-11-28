-- 修 300 Multiple Choices（PGRST203）
-- 现象：结算提交成绩时返回 300，游戏里提示"这局没上榜：网络问题"
-- 原因：submit_score 在库里有两个同名函数，旧版 7 参数 + 新版 8 参数（带 p_mod_code）
--       create or replace 只按参数签名替换，8 参数的建起来，7 参数那个还躺着
-- 处理：删掉旧签名。8 参数版里 p_mod_code 自带 DEFAULT ''，7 个参数照旧能调
-- 影响：这段可重复执行，删不到就跳过

drop function if exists public.submit_score(text, text, text, text, integer, integer, integer);

-- 核对：正常应该只剩一条，即 submit_score(text,text,text,text,integer,integer,integer,text)
select p.oid::regprocedure::text as 签名
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'submit_score';
