/**
 * 逃家游戏 · Telegram 发码机器人（Cloudflare Workers 版）
 *
 * 为什么用这个：Workers 跑在 Cloudflare 的网络上，出口本来就不在墙内，
 * 所以它自己就能连 api.telegram.org —— 你不需要 VPN，也不需要买服务器，7 块钱一分不用花。
 *
 * 部署步骤见同目录《部署说明.md》。
 */

const API = (t) => `https://api.telegram.org/bot${t}/`;

async function tg(env, method, payload) {
  const r = await fetch(API(env.BOT_TOKEN) + method, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  return r.json();
}

const send = (env, chat_id, text, md) =>
  tg(env, "sendMessage", { chat_id, text, parse_mode: md ? "Markdown" : undefined, disable_web_page_preview: true });

const today = () => new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);

function codeList(env) {
  return (env.CODES || "").split(/[\s,，]+/).filter(Boolean);
}

// 取一枚没发过的码：靠 KV 记一个指针，指针走到头就现生成一枚
async function nextCode(env) {
  const list = codeList(env);
  const kv = env.KV;
  let i = kv ? parseInt(await kv.get("idx") || "0", 10) : 0;
  if (list.length && i < list.length) {
    if (kv) await kv.put("idx", String(i + 1));
    return list[i];
  }
  const body = Array.from({ length: 12 }, () =>
    "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[Math.floor(Math.random() * 32)]).join("");
  return `EFH-${body.slice(0, 4)}-${body.slice(4, 8)}-${body.slice(8)}`;
}

async function quota(env, uid) {
  const limit = parseInt(env.DAILY_LIMIT || "2", 10);
  const kv = env.KV;
  if (!kv) return { ok: true, left: limit - 1 };
  const k = `d:${uid}:${today()}`;
  const n = parseInt(await kv.get(k) || "0", 10);
  if (n >= limit) return { ok: false, left: 0 };
  await kv.put(k, String(n + 1), { expirationTtl: 172800 });
  return { ok: true, left: limit - n - 1 };
}

const GAME = (env) => env.GAME_URL || "https://sobsh562u.github.io/Escape-from-Home/";

function welcome(env) {
  return `*逃家游戏* Escape from Home\n一个中文文字生存游戏：撑到 18 岁，从这个家里逃出去。\n13 个难度、38 个结局，免下载，手机能玩：\n${GAME(env)}\n\n发 /test 领测试激活码。`;
}

function help(env) {
  return `*可用命令*\n/test — 领测试激活码（每人每天 ${env.DAILY_LIMIT || 2} 枚）\n/help — 看这份说明\n/stats — 发码统计（仅管理员）`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 首次访问 ?init=1：让 Worker 自己把 webhook 挂到自己身上（你不需要打开 Telegram）
    if (url.searchParams.get("init") === "1") {
      const hook = `${url.origin}/`;
      const r = await tg(env, "setWebhook", { url: hook, allowed_updates: ["message", "edited_message"], drop_pending_updates: true });
      const me = await tg(env, "getMe", {});
      return new Response(
        `webhook 设置结果：${JSON.stringify(r)}\n机器人：${JSON.stringify(me.result || me)}\nworker 地址：${hook}`,
        { headers: { "content-type": "text/plain; charset=utf-8" } });
    }

    if (request.method === "GET") {
      return new Response("bot alive", { headers: { "content-type": "text/plain; charset=utf-8" } });
    }

    let update;
    try { update = await request.json(); } catch { return new Response("ok"); }
    const msg = update.message || update.edited_message;
    if (!msg || !msg.text) return new Response("ok");

    const chat_id = msg.chat.id;
    const uid = msg.from && msg.from.id;
    const name = (msg.from && msg.from.first_name) || "玩家";
    const inGroup = msg.chat.type !== "private";
    const admins = (env.ADMIN_IDS || "").split(/[\s,，]+/).filter(Boolean);
    const isAdmin = admins.length === 0 || admins.includes(String(uid));
    const cmd = msg.text.trim().split(/\s+/)[0].split("@")[0].toLowerCase();

    if (cmd === "/start") {
      await send(env, chat_id, welcome(env), true);
    } else if (cmd === "/help") {
      await send(env, chat_id, help(env), true);
    } else if (cmd === "/test") {
      if (inGroup && !isAdmin) {
        await send(env, chat_id, "领码请私聊我，群里只给管理员发。");
      } else {
        const q = await quota(env, uid);
        if (!q.ok) {
          await send(env, chat_id, `今天已经领满了（每天 ${env.DAILY_LIMIT || 2} 枚），明天再来。`);
        } else {
          const code = await nextCode(env);
          await send(env, chat_id,
            `${name}，这是你的测试激活码：\n\`${code}\`\n\n进游戏点“激活码”那一栏填进去。今天还能领 ${q.left} 枚。`, true);
        }
      }
    } else if (cmd === "/stats") {
      if (!isAdmin) {
        await send(env, chat_id, "这个命令只有管理员能用。");
      } else {
        const idx = env.KV ? parseInt(await env.KV.get("idx") || "0", 10) : 0;
        await send(env, chat_id, `已按顺序发出 ${idx} 枚（码池共 ${codeList(env).length} 枚）。`);
      }
    } else if (inGroup) {
      // 群里不认识的命令就当没看见
    } else {
      await send(env, chat_id, "没这个命令，发 /help 看看。");
    }
    return new Response("ok");
  },
};
