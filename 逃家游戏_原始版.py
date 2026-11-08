# -*- coding: utf-8 -*-
# 逃家游戏（原始版）
# Copyright (c) 2026 Sobsh562u
# SPDX-License-Identifier: MIT
# 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。

import random

血条 = 100
天 = 0

# ===== 存档包：导入 / 导出（和网页版通用）=====
# 网页版导出的 zip 在这里输入「导入」就能接着玩；
# 这里导出的 zip 拖进网页版「导入存档」也能恢复。
import json
import os
import zipfile
import datetime

难度ID = "orig"
难度名 = "原始版"
血条上限 = 100
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


print("你被关在家里写作业，想逃出去！")
print("只要撑过 5 天，就是你 18 岁生日，而且你名下有套房，就能逃了。")
print()
print("提示：每天按回车考试。但如果实在忍不了，可以输入 110……")
print("      偷偷告诉你：输入 12345678 可以跳天数。")
print("      输入「导出」存档打包，输入「导入」读存档包（网页版的包也能读）。")
print()

while True:
    print("———— 第", 天, "天 ————")
    操作 = input("妈妈发卷子，按回车考试；想报警就输入 110；跳天数输入 12345678：")

    # 存档包
    if 操作 in ("导入", "导入存档"):
        结果 = 导入存档()
        if 结果:
            天, 血条, 经历 = 结果
        continue
    if 操作 in ("导出", "导出存档"):
        导出存档(天, 血条, 经历)
        continue

    # 作者模式
    if 操作 == "12345678":
        天 = int(input("跳到第几天？（可以填负数！）："))
        continue

    # 报警结局
    if 操作 == "110":
        print()
        print("你拨通了 110……")
        input("警察：你好，请问发生什么事？")
        print("你：我妈家暴我，把我关在家里天天逼我考试！")
        input("警察：你现在的具体位置在哪？")
        print("你：就我家，我把地址发给你们。")
        input("警察：她有没有动手打你？")
        print("你：有！考 0 分就要打我，我血条都快掉光了！")
        input("警察：收到，我们马上出警。")
        print()
        print("==============================")
        print("几分钟后，警车停在你家楼下。")
        print("警察把你妈妈带走了。")
        print("你名下有房，明天 18 岁生日——自由了！")
        print("隐藏结局达成：正义の报警！🚔")
        print("==============================")
        break

    # ===== 负天数彩蛋 =====
    if 天 < 0:
        print()
        if 天 <= -100:
            print("==============================")
            print("你穿越到了", -天, "年前……")
            print("那时候你妈妈都还没出生！")
            print("谁在逼你考试？？？")
            print("你连你自己都还没出生！")
            print()
            print("祖父悖论触发：你穿越回去把自己搞没了，")
            print("那现在的你又是谁？")
            print("结局达成：祖父悖论💥")
            print("==============================")
        else:
            if 操作 == "跑":
                print("你是个受精卵，你居然想跑？！")
                print("你从妈妈肚子里跑出去了……")
                print("没有营养，没有羊水，你直接干死了。")
                print()
                print("结局达成：受精卵体外干死🦠💀")
            else:
                print("你还是个受精卵，在妈妈肚子里。")
                print("没有卷子可以考，也没有血条可以掉。")
                print("结局达成：受精卵体外死亡🦠")
            print("==============================")
        break

    # 撑过5天通关
    if 天 >= 5:
        print()
        print("==============================")
        print("第 5 天结束了！你还活着！")
        print("明天就是你 18 岁生日，你掏出钥匙……")
        print("打开那套写着你名字的房子。")
        print("你终于逃出这个家！结局达成！🏃‍♂️")
        print("==============================")
        break

    # 正常考试
    分数 = random.randint(0, 100)
    print("你这次考了", 分数, "分")

    if 分数 == 0:
        print("妈妈：你怎么考了鸭蛋？！？")
        血条 = 血条 - 40
    elif 分数 < 60:
        print("妈妈：你怎么又考砸了？！")
        血条 = 血条 - 15
    else:
        print("妈妈：这次考得不错，奖励你！")
        血条 = 血条 + 10

    if 血条 > 100:
        血条 = 100
    print("你现在的血条：", 血条, "/ 100")
    经历.append("第 %d 天：考了 %d 分，血条 %d / 100" % (天, 分数, 血条))

    if 血条 <= 0:
        print()
        print("你的血条归零……你死了。")
        print("GAME OVER —— 没撑到 18 岁。")
        break

    天 = 天 + 1
    print()
