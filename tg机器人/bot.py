# -*- coding: utf-8 -*-
"""
逃家游戏 · Telegram 发码机器人

用法（在你自己那台"能上 Telegram"的电脑上跑）：
  1) pip install requests
  2) 设置环境变量：
       TG_BOT_TOKEN=你的机器人token
       HTTPS_PROXY=http://127.0.0.1:7890     # 换成你代理的端口，走代理才能连上 Telegram
       ADMIN_IDS=你的telegram数字ID,另一个ID   # 能发码的人；留空=只有你自己(私聊里发)
  3) 可选：把激活码一行一个放进 codes.txt（不填就自动生成 EFH-XXXX-XXXX-XXXX）
  4) python bot.py

命令：
  /start   欢迎语 + 玩法链接
  /test    领一枚测试激活码（每人每天限 DAILY_LIMIT 次）
  /help    命令说明
  /stats   发码统计（仅管理员）
"""

import json
import os
import random
import string
import time
from datetime import date
from pathlib import Path

import requests

TOKEN = os.environ.get("TG_BOT_TOKEN", "").strip()
ADMIN_IDS = {int(x) for x in os.environ.get("ADMIN_IDS", "").replace("，", ",").split(",") if x.strip().isdigit()}
DAILY_LIMIT = int(os.environ.get("DAILY_LIMIT", "2"))
GAME_URL = os.environ.get("GAME_URL", "https://sobsh562u.github.io/Escape-from-Home/")

API = "https://api.telegram.org/bot%s/" % TOKEN
HERE = Path(__file__).resolve().parent
CODES = HERE / "codes.txt"
USED = HERE / "used.txt"
STATE = HERE / "state.json"

if not TOKEN:
    raise SystemExit("没设 TG_BOT_TOKEN，先在环境变量里填机器人 token")


def proxy_kw():
    """requests 会自动读 HTTPS_PROXY；这里显式兜一层，方便调试。"""
    p = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    return {"proxies": {"https": p, "http": p}} if p else {}


def call(method, **params):
    r = requests.post(API + method, json=params, timeout=40, **proxy_kw())
    return r.json()


def send(chat_id, text, markdown=False):
    return call("sendMessage", chat_id=chat_id, text=text,
                parse_mode="Markdown" if markdown else None,
                disable_web_page_preview=True)


def gen_code():
    body = "".join(random.choice(string.ascii_uppercase + string.digits) for _ in range(12))
    return "EFH-%s-%s-%s" % (body[0:4], body[4:8], body[8:12])


def load_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")


def take_code():
    """先从 codes.txt 取一枚没用过的；取完了就现生成一枚。"""
    used = set(x.strip() for x in USED.read_text(encoding="utf-8").splitlines()) if USED.exists() else set()
    if CODES.exists():
        for line in CODES.read_text(encoding="utf-8").splitlines():
            c = line.strip()
            if c and c not in used:
                used.add(c)
                USED.write_text("\n".join(sorted(used)) + "\n", encoding="utf-8")
                return c
    c = gen_code()
    used.add(c)
    USED.write_text("\n".join(sorted(used)) + "\n", encoding="utf-8")
    return c


def quota_ok(uid):
    st = load_json(STATE, {})
    today = date.today().isoformat()
    rec = st.get(str(uid)) or {}
    if rec.get("day") != today:
        rec = {"day": today, "n": 0}
    if rec["n"] >= DAILY_LIMIT:
        return False, DAILY_LIMIT - rec["n"]
    rec["n"] += 1
    st[str(uid)] = rec
    save_json(STATE, st)
    return True, DAILY_LIMIT - rec["n"]


WELCOME = (
    "*逃家游戏* Escape from Home\n"
    "一个中文文字生存游戏：撑到 18 岁，从这个家里逃出去。\n"
    "13 个难度、38 个结局，免下载，手机能玩：\n" + GAME_URL + "\n\n"
    "发 /test 领测试激活码。"
)

HELP = (
    "*可用命令*\n"
    "/test — 领测试激活码（每人每天 %d 枚）\n"
    "/help — 看这份说明\n"
    "/stats — 发码统计（仅管理员）" % DAILY_LIMIT
)


def handle(update):
    msg = update.get("message") or update.get("edited_message")
    if not msg:
        return
    chat_id = msg.get("chat", {}).get("id")
    uid = (msg.get("from") or {}).get("id")
    text = (msg.get("text") or "").strip()
    name = (msg.get("from") or {}).get("first_name") or "玩家"

    if not text.startswith("/"):
        if msg.get("chat", {}).get("type") == "private":
            send(chat_id, "发 /test 领码，发 /help 看说明。")
        return

    cmd = text.split()[0].split("@")[0].lower()

    # 群里的发码只给管理员，避免被刷
    is_admin = (not ADMIN_IDS) or uid in ADMIN_IDS
    in_group = msg.get("chat", {}).get("type") != "private"

    if cmd == "/start":
        send(chat_id, WELCOME, markdown=True)
    elif cmd == "/help":
        send(chat_id, HELP, markdown=True)
    elif cmd == "/test":
        if in_group and not is_admin:
            send(chat_id, "领码请私聊我，群里只给管理员发。")
            return
        ok, left = quota_ok(uid)
        if not ok:
            send(chat_id, "今天已经领满了（每天 %d 枚），明天再来。" % DAILY_LIMIT)
            return
        code = take_code()
        send(chat_id, "%s，这是你的测试激活码：\n`%s`\n\n进游戏后点“激活码”那一栏填进去。今天还能领 %d 枚。"
             % ("%s，" % name, code, left), markdown=True)
    elif cmd == "/stats":
        if ADMIN_IDS and uid not in ADMIN_IDS:
            send(chat_id, "这个命令只有管理员能用。")
            return
        n_used = len(USED.read_text(encoding="utf-8").splitlines()) if USED.exists() else 0
        st = load_json(STATE, {})
        today = date.today().isoformat()
        n_today = sum(v.get("n", 0) for v in st.values() if v.get("day") == today)
        send(chat_id, "累计发出 %d 枚，今天发出 %d 枚。" % (n_used, n_today))
    else:
        send(chat_id, "没这个命令，发 /help 看看。")


def main():
    print("机器人启动，代理：%s" % (os.environ.get("HTTPS_PROXY") or "未设置"))
    me = call("getMe")
    if not me.get("ok"):
        raise SystemExit("连不上 Telegram：%s" % me)
    print("已登录：@%s" % me["result"].get("username"))
    offset = 0
    while True:
        try:
            r = call("getUpdates", offset=offset, timeout=30,
                     allowed_updates=["message", "edited_message"])
            for up in r.get("result", []):
                offset = up["update_id"] + 1
                try:
                    handle(up)
                except Exception as e:
                    print("处理出错：", e)
            if not r.get("ok"):
                print("getUpdates 失败：", r)
                time.sleep(5)
        except Exception as e:
            print("网络错误，5 秒后重试：", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
