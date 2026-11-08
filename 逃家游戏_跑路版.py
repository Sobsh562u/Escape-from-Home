# -*- coding: utf-8 -*-
# 逃家游戏（跑路版 / 攒钱版）
# Copyright (c) 2026 Sobsh562u
# SPDX-License-Identifier: MIT
# 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。

import random
import json
import os
import zipfile
import datetime

难度ID = "run"
难度名 = "跑路版"
血条上限 = 100
血条 = 100
天 = 0
钱 = 0
阶段 = 0          # 0=在家，1=幼儿园站，2=学校站，3=大学站
经历 = []

站名 = {1: "幼儿园站", 2: "学校站", 3: "大学站"}
站扣血 = {1: 20, 2: 30, 3: 40}
站安全 = {1: 25, 2: 20, 3: 15}   # 等车时平安过去的概率（%）


def 读取整数(提示, 默认=None):
    """只收整数；乱填就重新问，不会把程序搞崩。"""
    while True:
        try:
            文本 = input(提示).strip()
        except EOFError:
            raise
        if not 文本:
            if 默认 is not None:
                return 默认
            print("这里要填一个整数。")
            continue
        try:
            return int(文本)
        except ValueError:
            print("这不是整数，重新填一个。")


# ===== 存档包：导入 / 导出（和网页版、C 版通用）=====
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
        "money": 钱,
        "stage": 阶段,
        "savedAt": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "log": [{"t": t, "c": ""} for t in 记录],
    }
    文本 = [
        "逃家游戏 · 存档包",
        "导出时间：" + 数据["savedAt"],
        "难度：" + 难度名,
        "进度：第 %d 天" % 天数,
        "血条：%d / %d" % (血量, 血条上限),
        "手上的钱：%d 块" % 钱,
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
    血量 = max(1, min(血条上限, int(数据["hp"])))
    记录 = [it.get("t", "") for it in (数据.get("log") or [])
             if isinstance(it, dict) and it.get("t")]
    新钱 = int(数据.get("money", 0) or 0)
    新阶段 = int(数据.get("stage", 0) or 0)
    print("已导入：第 %d 天，血条 %d / %d，钱 %d 块"
          % (int(数据["day"]), 血量, 血条上限, 新钱))
    print()
    return (int(数据["day"]), 血量, 记录, 新钱, 新阶段)


def 过站(打车):
    """返回 True 表示整局结束（出城或死在站台）。"""
    global 血条, 阶段
    站 = 站名[阶段]
    if 打车:
        print("你招手拦了辆出租，塞过去 10 块，司机一脚油门直接把你送过这一站。")
    elif 阶段 == 1:
        print("站台边上蹲着一群小孩，尖叫着绕着你跑，声音直接钻进脑子里。")
        if random.randint(1, 100) <= 站安全[1]:
            print("你从孩子堆里挤了过去，衣服被拽歪了，人没事。")
        else:
            print("被一群小孩缠住，吵得头都要裂了，扣 %d 血。" % 站扣血[1])
            血条 -= 站扣血[1]
    elif 阶段 == 2:
        print("你小学的班主任正站在站牌底下，一眼就认出你了。")
        if random.randint(1, 100) <= 站安全[2]:
            print("你把帽檐压得很低贴着墙走，班主任正忙着训别的学生，没追上来。")
        else:
            print("老师一把揪住你：逃学？跟我回办公室！扣 %d 血。" % 站扣血[2])
            血条 -= 站扣血[2]
    else:
        print("你哥在站台上抽烟，看见你，把烟一扔就冲过来。")
        if random.randint(1, 100) <= 站安全[3]:
            print("公交刚好进站，你混在人堆里挤上去，你哥扑了个空。")
        else:
            print("被你哥一把按住，扣 %d 血。" % 站扣血[3])
            血条 -= 站扣血[3]

    if 血条 <= 0:
        print()
        print("==============================")
        print("你倒在%s的地上，血条归零。" % 站)
        print("结局达成：倒在路上")
        print("==============================")
        return True

    阶段 += 1
    if 阶段 >= 4:
        print()
        print("==============================")
        print("你过了最后一站。出城的公路在眼前展开，")
        print("天亮的时候你已经不在这个城市了。")
        print("结局达成：终点站")
        print("==============================")
        return True
    print("过了这一站，下一站：%s。" % 站名[阶段])
    print("血条 %d / %d，钱 %d 块" % (血条, 血条上限, 钱))
    print()
    return False


print("==== 逃家游戏 · 跑路版 ====")
print("你被关在家里天天考试。想走？得先攒钱。")
print("每天考试：60 分以上才有钱（60-89 分 1-3 块，90 分以上 3-5 块）；60 分以下不给钱还扣血。")
print("车票 50 块 + 买通弟弟 10 块 = 60 块，才能出门。")
print("出门后过三站：幼儿园（吵）、学校（老师）、大学（哥哥）。")
print("每站可以「等」公交（免费，但会被熟人逮住），或者「打车」花 10 块直接过站。")
print("钱够了也可以一直待在家里，不走。")
print()
print("提示：输入 导出 / 导入 存档；输入 12345678 作者模式改钱。")
print()

while True:
    if 阶段 > 0:
        print("———— 第 %d 天 · %s · 钱 %d 块 ————" % (天, 站名[阶段], 钱))
        操作 = input("等（等车，不要钱）/ 打车（10 块，直接过站）：").strip()
        if 操作 == "打车":
            if 钱 < 10:
                print("司机看了看你手里的钱，摆摆手开走了。这一站只能等公交。")
                print()
                continue
            钱 -= 10
            if 过站(True):
                break
            continue
        if 操作 in ("等", ""):
            if 过站(False):
                break
            continue
        print("站台上只有两个选择：等（等车）或者 打车。")
        print()
        continue

    print("———— 第 %d 天 · 钱 %d 块 ————" % (天, 钱))
    操作 = input("按回车考试 / 跑（出门坐车）/ 110 / 12345678 / 导出 / 导入：").strip()

    if 操作 in ("导入", "导入存档"):
        结果 = 导入存档()
        if 结果:
            天, 血条, 经历, 钱, 阶段 = 结果
        continue
    if 操作 in ("导出", "导出存档"):
        导出存档(天, 血条, 经历)
        continue

    if 操作 == "12345678":
        钱 = 读取整数("设置你现在有多少钱：", 0)
        if 钱 < 0:
            钱 = 0
        print("作者模式：你有 %d 块。（60 块才够车票加买通弟弟）" % 钱)
        print()
        continue

    if 操作 == "110":
        print()
        print("你拨通 110，接电话的是派出所。")
        print("警察：你妈又打你了？这个月第几次了。")
        print("你：……第三次。")
        print("警察：我们过去一趟，但你要不要考虑先离开那个家？")
        print("==============================")
        print("结局达成：报警了，但这次没人送你走")
        print("==============================")
        break

    if 操作 == "跑":
        if 钱 >= 60:
            钱 -= 60
            print("你把 50 块塞进售票窗口，又给了弟弟 10 块。")
            print("弟弟数了数，没吭声，把门开了一条缝。")
            print("你走出家门，夜风灌进领口，公交站牌就在街口。")
            print("第一站：幼儿园站。")
            print()
            阶段 = 1
            continue
        if 钱 >= 50:
            血条 -= 10
            print("你攥着 50 块去买票，弟弟横在门口：没好处费，别想走。扣 10 血。")
        else:
            血条 -= 20
            print("你想走出这个家门，刚把门拉开一条缝，妈妈一把把你拽回来，抄起拖鞋就打——扣 20 血。")
        print("血条 %d / %d，钱 %d 块" % (血条, 血条上限, 钱))
        print()
        if 血条 <= 0:
            print("你的血条归零……你死了。")
            print("GAME OVER —— 没走出这个家。")
            break
        continue

    # ===== 考试 =====
    分数 = random.randint(0, 100)
    print("你这次考了 %d 分" % 分数)
    if 分数 == 0:
        print("妈妈：鸭蛋？跪下！")
        血条 -= 40
    elif 分数 < 60:
        print("妈妈：又不及格，一分钱都别想要。")
        血条 -= 15
    else:
        给 = random.randint(3, 5) if 分数 >= 90 else random.randint(1, 3)
        钱 += 给
        print("妈妈：考得还行，赏你 %d 块。" % 给)

    if 血条 > 血条上限:
        血条 = 血条上限
    print("血条 %d / %d，钱 %d 块" % (血条, 血条上限, 钱))
    经历.append("第 %d 天：考了 %d 分，血条 %d / %d，钱 %d 块"
                % (天, 分数, 血条, 血条上限, 钱))

    if 血条 <= 0:
        print()
        print("你的血条归零……你死了。")
        print("GAME OVER —— 没撑到能走的那天。")
        break

    天 += 1
    print()
