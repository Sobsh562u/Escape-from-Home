#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
逃家游戏 · 模组终端工具（无第三方依赖，只要 Python 3.8+）

第一次用：  python 逃家模组.py login
之后就能：  python 逃家模组.py new        # 交互式选位置、写内容，生成 mod.json
            python 逃家模组.py submit mod.json
            python 逃家模组.py list       # 看模组市场（带 001 这种官方编号）
            python 逃家模组.py whoami     # 看当前授权的账号
直接双击或 python 逃家模组.py        # 进菜单

token 存在 ~/.逃家游戏/dev.json，想换账号就 logout 或直接删这个文件。
"""

import json
import os
import random
import string
import sys
import time
import webbrowser
import urllib.request
import urllib.error

SB = "https://spvouajdnckiyihhccux.supabase.co/rest/v1/rpc/"
KEY = "sb_publishable_gOcJXjEu8wVL7tDFNCL5yw_7Y7Zy7ET"
SITE = "https://sobsh562u.github.io/Escape-from-Home/模组编辑器.html"
HOME = os.path.join(os.path.expanduser("~"), ".逃家游戏")
CONF = os.path.join(HOME, "dev.json")

MODES = [
    ("orig", "原始版"), ("revert", "反转版"), ("hard", "困难版"), ("limit", "极限版"),
    ("run", "跑路版"), ("school", "校园版"), ("phone", "手机版"), ("storm", "停电版"),
    ("summer", "暑假版"), ("newyear", "过年版"), ("winter", "寒假版"),
    ("checkup", "体检版"), ("endless", "无尽版"),
]
EVENTS = [
    ("e1", "妈妈接了个电话，出门半小时。你趴在桌上，喘了口气。"),
    ("e2", "邻居阿姨敲门，塞给你一包饼干。你没敢说谢谢。"),
    ("e3", "妈妈翻你的书包，翻出一张皱巴巴的测验卷，又数落了你一顿。"),
    ("e4", "楼下有人放歌，你趴在窗台上听完了整首。这一刻没人管你。"),
    ("e5", "半夜停电，你摸黑找手电筒，膝盖磕在桌角上。"),
    ("e6", "你在作业本背面偷偷画了一扇门，画完心里松了一点。"),
    ("e7", "妈妈突然问你：你是不是想离开这个家？你没敢回答。"),
    ("e8", "雨下了一整天，妈妈没来查作业，你睡了个囫囵觉。"),
]
ENDINGS = [
    ("orig_win", "逃出这个家"), ("orig_call", "正义报警"), ("revert_early", "小小年纪成功逃家"),
    ("revert_caught", "门口被抓"), ("revert_call", "报警反被抓"), ("revert_cheat", "被当成作弊打死"),
    ("revert_repeat", "考上本科却失去自由"), ("revert_college", "考上大专反而自由"),
    ("revert_free", "考砸反而没人管"), ("endless_die", "无尽里撑不住"), ("school_drop", "辍学"),
]


def say(msg=""):
    print(msg)


def rule():
    print("-" * 52)


def rpc(fn, body=None, timeout=30):
    data = json.dumps(body or {}).encode("utf-8")
    req = urllib.request.Request(
        SB + fn, data=data,
        headers={"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"ok": False, "msg": "服务器返回 %s" % e.code}
    except Exception as e:
        return {"ok": False, "msg": "连不上服务器：%s" % e}


def load_conf():
    try:
        with open(CONF, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_conf(d):
    os.makedirs(HOME, exist_ok=True)
    with open(CONF, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def new_code():
    chars = string.ascii_uppercase + string.digits
    return "".join(random.choice(chars) for _ in range(4)) + "-" + "".join(random.choice(chars) for _ in range(4))


def cmd_login(_args=None):
    code = new_code()
    r = rpc("dev_pair_start", {"p_code": code})
    if not r.get("ok"):
        say("发起授权失败：%s" % r.get("msg"))
        return 1
    url = SITE + "?pair=" + code
    rule()
    say("设备码： %s" % code)
    say("正在打开浏览器…… 没反应就手动打开这个地址：")
    say(url)
    rule()
    try:
        webbrowser.open(url)
    except Exception:
        pass
    say("在网页里登录 → 确认授权。这里等 10 分钟，别关窗口。")
    deadline = time.time() + 600
    dots = 0
    while time.time() < deadline:
        time.sleep(2.5)
        p = rpc("dev_pair_poll", {"p_code": code})
        st = p.get("status")
        if st == "confirmed" and p.get("token"):
            save_conf({"token": p["token"], "name": p.get("name"), "player_id": p.get("player_id"),
                       "site": SITE})
            rule()
            say("授权成功：%s（ID %s）" % (p.get("name"), p.get("player_id")))
            say("这台终端以后可以直接 submit 了。")
            return 0
        if st in ("expired", "none", "consumed"):
            say("设备码失效：%s" % p.get("msg"))
            return 1
        dots += 1
        sys.stdout.write("\r等待授权" + "." * (dots % 4) + "   ")
        sys.stdout.flush()
    say("\n超时了，重新跑一次 login。")
    return 1


def need_token():
    c = load_conf()
    tok = c.get("token")
    if not tok:
        say("还没授权，先跑： python 逃家模组.py login")
        return None, c
    v = rpc("dev_token_check", {"p_token": tok})
    if not v.get("ok"):
        say("token 失效了（%s），重新 login。" % v.get("msg"))
        return None, c
    return tok, c


def cmd_whoami(_args=None):
    tok, c = need_token()
    if not tok:
        return 1
    v = rpc("dev_token_check", {"p_token": tok})
    rule()
    say("当前账号：%s（玩家 ID %s）" % (v.get("name"), v.get("player_id")))
    say("token 存在：%s" % CONF)
    return 0


def pick_index(items, hint):
    for i, it in enumerate(items, 1):
        extra = ""
        if len(it) > 2:
            extra = "  " + it[2][:26] + ("…" if len(it[2]) > 26 else "")
        say("  %2d) %s %s%s" % (i, it[0], it[1], extra))
    raw = input(hint).strip()
    if not raw.isdigit():
        return None
    i = int(raw)
    return items[i - 1] if 1 <= i <= len(items) else None


def cmd_new(args=None):
    out_path = args[0] if args else "mod.json"
    patches = []
    say("")
    rule()
    say("新建模组：一次一条，回车空着就结束。")
    while True:
        rule()
        say("位置类型：  1) 改已有事件   2) 新增事件   3) 难度   4) 结局   0) 结束")
        t = input("选：").strip()
        if t in ("0", ""):
            break
        if t == "1":
            ev = pick_index([(a, b, c) for (a, b), c in [(x, EVENTS[i][1]) for i, x in enumerate(EVENTS)]],
                            "选事件编号 1–8：")
            if not ev:
                continue
            target = "event:%s.text" % ev[0]
        elif t == "2":
            n = input("新增第几条（1–5）：").strip()
            if n not in list("12345"):
                continue
            target = "event:add.%s.text" % n
        elif t == "3":
            m = pick_index(MODES, "选难度：")
            if not m:
                continue
            say("  1) 页签名  2) 开场白  3) 规则说明")
            f = {"1": "name", "2": "text", "3": "desc"}.get(input("选字段：").strip())
            if not f:
                continue
            target = "mode:%s.%s" % (m[0], f)
        elif t == "4":
            e = pick_index(ENDINGS, "选结局：")
            if not e:
                continue
            say("  1) 结局名  2) 副标题")
            f = {"1": "title", "2": "desc"}.get(input("选字段：").strip())
            if not f:
                continue
            target = "ending:%s.%s" % (e[0], f)
        else:
            continue
        say("位置：%s" % target)
        val = input("改成什么：").strip()
        if not val:
            continue
        patches.append({"target": target, "value": val})
        say("已加 %d 条。" % len(patches))

    if not patches:
        say("没有改动，放弃。")
        return 1

    title = input("模组名字（2–24 字）：").strip()
    summary = input("一句话说明（可空）：").strip()
    pack = {"title": title, "summary": summary, "patches": patches}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, indent=2)
    rule()
    say("已写入 %s（%d 条改动）" % (out_path, len(patches)))
    say("下一步： python 逃家模组.py submit %s" % out_path)
    return 0


def cmd_submit(args):
    path = args[0] if args else "mod.json"
    if not os.path.exists(path):
        say("找不到 %s" % path)
        return 1
    try:
        with open(path, "r", encoding="utf-8") as f:
            pack = json.load(f)
    except Exception as e:
        say("这个文件不是合法 JSON：%s" % e)
        return 1
    tok, _ = need_token()
    if not tok:
        return 1
    say("提交中……")
    r = rpc("dev_submit", {
        "p_token": tok,
        "p_title": pack.get("title", ""),
        "p_summary": pack.get("summary", ""),
        "p_patches": pack.get("patches", []),
    })
    rule()
    if r.get("ok"):
        say("已提交，等作者审核。通过后市场里会有三位编号，用 ?mod=编号 就能加载。")
        return 0
    say("被退回了：%s" % r.get("msg"))
    return 1


def cmd_list(_args=None):
    r = rpc("list_mods", {})
    rows = r.get("rows") or []
    rule()
    if not rows:
        say("市场现在是空的。")
        return 0
    for m in rows:
        say("%s  %s  —— %s（%s 处改动）" % (m.get("code") or "—", m.get("title"), m.get("author_name") or "匿名",
                                          m.get("patches", 0)))
    rule()
    say("加载方式：游戏地址后面加 ?mod=001")
    return 0


def cmd_logout(_args=None):
    if os.path.exists(CONF):
        os.remove(CONF)
        say("本地 token 已删除。想连带作废服务器上的，去网页「授权终端 → 断开我所有已授权设备」。")
    else:
        say("本来就没登录。")
    return 0


MENU = [
    ("login", "授权这台终端（打开浏览器）", cmd_login),
    ("new", "新建模组（交互选位置）", cmd_new),
    ("submit", "提交 mod.json", cmd_submit),
    ("list", "看模组市场", cmd_list),
    ("whoami", "看当前账号", cmd_whoami),
    ("logout", "退出登录", cmd_logout),
]


def menu():
    while True:
        c = load_conf()
        rule()
        say("逃家游戏 · 模组终端   %s" % ("已授权：" + str(c.get("name")) if c.get("token") else "未授权"))
        rule()
        for i, (_, label, _f) in enumerate(MENU, 1):
            say("  %d) %s" % (i, label))
        say("  0) 退出")
        k = input("选：").strip()
        if k == "0" or not k:
            return 0
        if k.isdigit() and 1 <= int(k) <= len(MENU):
            name, _, fn = MENU[int(k) - 1]
            try:
                if name == "submit":
                    p = input("文件路径（回车用 mod.json）：").strip() or "mod.json"
                    fn([p])
                else:
                    fn()
            except KeyboardInterrupt:
                say("\n中断。")
            print()


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    cmds = {"login": cmd_login, "new": cmd_new, "submit": cmd_submit,
            "list": cmd_list, "whoami": cmd_whoami, "logout": cmd_logout}
    if not argv:
        return menu()
    name, rest = argv[0], argv[1:]
    if name in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    fn = cmds.get(name)
    if not fn:
        say("不认识的命令：%s" % name)
        print(__doc__)
        return 1
    return fn(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
