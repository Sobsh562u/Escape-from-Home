# -*- coding: utf-8 -*-
# 逃家游戏（困难版）
# Copyright (c) 2026 Sobsh562u
# SPDX-License-Identifier: MIT
# 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。

import random

血条 = 50
最大血条 = 50
天 = 0
目标天数 = 10          # 要比原版多撑 5 天


# ===== 存档包：导入 / 导出（和网页版通用）=====
# 网页版导出的 zip 在这里输入「导入」就能接着玩；
# 这里导出的 zip 拖进网页版「导入存档」也能恢复。
import json
import os
import zipfile
import datetime

难度ID = "hard"
难度名 = "困难版"
血条上限 = 最大血条
经历 = []


def 导出存档(天数, 血量, 记录):
    if 血量 <= 0:
        print("这局已经结束了，重新开一局再导出吧。")
        return
    数据 = {
        "game": "逃家游戏 Escape from Home",
        "packVersion": 2,
        "mode": 难度ID,
        "modeLabel": 难度名,
        "day": 天数,
        "hp": 血量,
        "max": 血条上限,
        "savedAt": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log": [{"t": t, "c": ""} for t in 记录],
    }
    文本 = [
        "逃家游戏 · 存档包",
        "导出时间：" + 数据["savedAt"],
        "难度：" + 难度名,
        "进度：第 %d 天" % 天数,
        "血条：%d / %d" % (血量, 血条上限),
        "",
        "—— 这段时间你经历过 ——",
    ]
    for i, t in enumerate(记录, 1):
        文本.append("%d. %s" % (i, t))
    文件名 = "逃家游戏存档-%s-第%d天.zip" % (难度名, 天数)
    with zipfile.ZipFile(文件名, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("存档.json", json.dumps(数据, ensure_ascii=False, indent=2))
        z.writestr("存档说明.txt", "\n".join(文本))
    print("存档包已导出：" + os.path.abspath(文件名))
    print("想接着玩：网页版点「导入存档」选它，或者再开这个程序输入「导入」。")
    print()


def 导入存档():
    print("把存档包拖进来，或者直接填路径（.zip / .json）：")
    路径 = input("存档路径：").strip().strip('"').strip("'")
    if not 路径:
        print("没填路径，继续玩当前这一局。")
        return None
    if not os.path.exists(路径):
        print("找不到这个文件：" + 路径)
        return None
    try:
        if 路径.lower().endswith(".zip"):
            with zipfile.ZipFile(路径) as z:
                名单 = [n for n in z.namelist() if n.lower().endswith(".json")]
                if not 名单:
                    print("这个压缩包里没有存档.json，不是存档包。")
                    return None
                原始 = z.read(名单[0]).decode("utf-8")
        else:
            with open(路径, "r", encoding="utf-8") as f:
                原始 = f.read()
        数据 = json.loads(原始)
    except Exception:
        print("这个文件读不出来，可能损坏了。")
        return None
    if isinstance(数据, dict) and 数据.get("encrypted"):
        print("这是带密码的加密存档，终端版解不开。")
        print("去网页版导入它，或者导出时密码留空再来。")
        return None
    if not isinstance(数据, dict) or "day" not in 数据 or "hp" not in 数据:
        print("存档内容不对（缺天数或血条），导入失败。")
        return None
    if 数据.get("mode") and 数据["mode"] != 难度ID:
        print("注意：这份存档是「%s」，这里是「%s」。"
              % (数据.get("modeLabel") or 数据["mode"], 难度名))
        print("天数和血条照搬，但接着按这边的规则玩。")
    天数 = int(数据["day"])
    血量 = max(1, min(血条上限, int(数据["hp"])))
    记录 = [it.get("t", "") for it in (数据.get("log") or [])
             if isinstance(it, dict) and it.get("t")]
    print("已导入：第 %d 天，血条 %d / %d" % (天数, 血量, 血条上限))
    if 记录:
        print("—— 之前经历过 ——")
        for t in 记录[-6:]:
            print("·", t)
    print()
    return (天数, 血量, 记录)


print("====逃家游戏（困难版）====")
print("输入「导出」存档打包，输入「导入」读存档包（网页版的包也能读）。")
print("血条只有 50，妈妈更暴躁，要撑 10 天。")
print("提示：考 0 分直接掉一半血；逃跑有风险。")
print()

while 天 < 目标天数:
    print("———— 第", 天, "天 ————")
    操作 = input("按回车考试 / 跑 / 110 / 12345678：")
    # 存档包
    if 操作 in ("导入", "导入存档"):
        结果 = 导入存档()
        if 结果:
            天, 血条, 经历 = 结果
        continue
    if 操作 in ("导出", "导出存档"):
        导出存档(天, 血条, 经历)
        continue


    if 操作 == "12345678":
        天 = int(input("跳到第几天："))
        continue

    if 操作 == "110":
        print("你拨通了 110……")
        print("警察：小孩子别乱打电话！")
        print("结局达成：被当成恶作剧，没人来救你")
        break

    if 操作 == "跑":
        运气 = random.randint(1, 100)
        if 运气 <= 20:
            print("天没黑你不敢跑，被妈妈抓个正着，扣 10 血！")
            血条 = 血条 - 10
        else:
            print("黑灯瞎火跑出门，又冷又饿，扣 5 血")
            血条 = 血条 - 5
        if 血条 <= 0:
            print("你倒在了楼道里……")
            print("结局达成：逃跑失败")
            break
        print("血条:", 血条, "/", 最大血条)
        天 = 天 + 1
        print()
        continue

    # 考试
    分数 = random.randint(0, 100)
    print("你考了", 分数, "分")

    if 分数 == 0:
        print("妈妈：鸭蛋？！跪墙角！")
        血条 = 血条 - 25
    elif 分数 < 60:
        print("妈妈：又不及格！")
        血条 = 血条 - 15
    elif 分数 < 90:
        print("妈妈：还行，别骄傲。")
        血条 = 血条 + 5
    else:
        print("妈妈：不错。")
        血条 = 血条 + 8

    if 血条 > 最大血条:
        血条 = 最大血条
    print("血条:", 血条, "/", 最大血条)

    if 血条 <= 0:
        print("血条归零，你撑不住了。")
        print("结局达成：倒在第十天之前")
        break

    天 = 天 + 1
    print()

if 天 >= 目标天数 and 血条 > 0:
    print("你撑过了 10 天！18 岁生日，名下有房。")
    print("结局达成：困难模式通关🏃‍♂️🏠")

try:
    input("\n按回车键退出...")
except EOFError:
    pass
