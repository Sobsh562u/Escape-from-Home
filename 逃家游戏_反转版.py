# -*- coding: utf-8 -*-
# 逃家游戏（反转版·修正）
# Copyright (c) 2026 Sobsh562u
# SPDX-License-Identifier: MIT
# 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。
#
# 【反转规则一览：原版 → 反转后】
#   1. 考试考砸(<60)    原版扣血 → 反转后加血
#   2. 考试考好(>=60)   原版加血 → 反转后扣血
#   3. 高考高分(>=700)  原版录取 → 反转后被当成作弊打死
#   4. 高考低分(<200)   原版被打死 → 反转后反而自由
#   5. 报警 110         原版抓妈妈 → 反转后抓你自己
#   6. 逃跑「跑」        原版越小越惨 → 反转后越小越容易跑掉
#   7. 血条             原版越多越好 → 反转后掉血才是好事，满血反而危险

import random

血条 = 100          # 初始血条
最大血条 = 100

天 = 0              # 从第 0 天开始，逐天 +1
总天数 = 6570       # 撑到 18 岁（6570 天）

强制分数 = None     # 作者模式用的强制分数

加血池 = [20, 40, 60, 80, 100]        # 名义“加血”，反转后实际是扣血
扣血池 = [20, 40, 60, 80, 10000]      # 名义“扣血”，反转后实际是加血


# ===== 存档包：导入 / 导出（和网页版通用）=====
# 网页版导出的 zip 在这里输入「导入」就能接着玩；
# 这里导出的 zip 拖进网页版「导入存档」也能恢复。
import json
import os
import zipfile
import datetime

难度ID = "revert"
难度名 = "反转版"
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


print("====逃家游戏（反转版）====")
print("输入「导出」存档打包，输入「导入」读存档包（网页版的包也能读）。")
print("平时考试 0-100 分；最后一天高考 0-750 分！")
print("提示：这一切是反向的")
print("提示：考砸会加血，考好会扣血")
print("提示：分数越高，结局越惨")
print("祝你不好运")
print()

while 天 <= 总天数:
    print("———— 第", 天, "天（", round(天 / 365), "岁）————")
    操作 = input("考试/跑/110/12345678：")
    # 存档包
    if 操作 in ("导入", "导入存档"):
        结果 = 导入存档()
        if 结果:
            天, 血条, 经历 = 结果
        continue
    if 操作 in ("导出", "导出存档"):
        导出存档(天, 血条, 经历)
        continue


    # —— 逃跑：反转后越小越容易跑掉 ——
    if 操作 == "跑":
        if 天 < 3650:
            print("你太小了，妈妈根本追不上，你跑掉了！🏃‍♂️💨")
            print("结局达成：小小年纪成功逃家")
        elif 天 < 6570:
            print("半大孩子，跑了又被抓回来🤣")
        else:
            print("都 18 岁了才跑？妈妈就在门口等着，当场抓回💀")
        break

    # —— 报警：反转后抓的是你自己 ——
    if 操作 == "110":
        print("警察来了，把你抓走了！🚔")
        print("结局达成：报警反被抓")
        break

    # —— 作者模式：改分 / 跳天 ——
    if 操作 == "12345678":
        print("✨作者模式✨ 1.改分 2.跳天")
        选择 = input("选:")
        if 选择 == "1":
            强制分数 = int(input("改成多少分？"))
        elif 选择 == "2":
            天 = int(input("跳到第几天？"))
            continue

    # —— 最后一天：高考 0-750 ——
    if 天 >= 总天数:
        if 强制分数 is not None:
            分数 = 强制分数
            强制分数 = None
        else:
            分数 = random.randint(0, 750)

        print("📢 高考！你考了", 分数, "分！")

        # 反转：分数越高越惨
        if 分数 >= 700:
            print("妈妈：考这么高？肯定作弊！")
            print("妈妈拿鸡毛掸子追着你打！🪶💀")
            print("结局达成：考太高被当成作弊打死了")
            break
        elif 分数 >= 400:
            print("📚 400 分以上，本科——但妈妈逼你复读，关在家里不许出门。")
            print("结局达成：考上本科却失去自由")
            break
        elif 分数 >= 200:
            print("📖 200 分，大专。")
            print("妈妈懒得管你了，你搬出去住了。🏠")
            print("结局达成：成绩一般反而自由了")
            break
        else:
            print("💀 0 分！妈妈气到晕倒，没人管你了。")
            print("结局达成：考砸反而没人管，自由了🏃‍♂️")
            break

    # —— 平时考试 0-100 ——
    if 强制分数 is not None:
        分数 = 强制分数
        强制分数 = None
    else:
        分数 = random.randint(0, 100)

    print("你考了", 分数, "分")

    if 分数 < 60:
        # 反转：考砸 → 加血
        加多少 = random.choice(加血池)
        print("妈妈大喜！你考砸了她反而放心，加了", 加多少, "血！")
        血条 = 血条 + 加多少
    else:
        # 反转：考好 → 扣血
        扣多少 = random.choice(扣血池)
        print("妈妈暴怒！你考好了她怕你太优秀，扣了", 扣多少, "血！")
        血条 = 血条 - 扣多少

    # 血条上下限
    if 血条 > 最大血条:
        血条 = 最大血条
    if 血条 <= 0:
        print("血条清零……你被打死了。💀")
        print("结局达成：反转世界里，血少了才是好事——你刚好反着来。")
        break

    print("血条:", 血条, "/", 最大血条)
    天 = 天 + 1
    print()

if 天 > 总天数 and 血条 > 0:
    print("你撑到了 18 岁！名下有房！自由了！🏃‍♂️🏠")

try:
    input("\n按回车键退出...")
except EOFError:
    pass
