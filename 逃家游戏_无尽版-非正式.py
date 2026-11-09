# -*- coding: utf-8 -*-
# 【非正式草稿】逃家游戏（无尽版）
# Copyright (c) 2026 Sobsh562u
# SPDX-License-Identifier: MIT
# 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。
# 注意：这是新版本初稿，规则未最终定稿，文件名与文件头均标注「非正式」。

import random
import json
import os
import zipfile
import datetime
import urllib.request
import urllib.error

# ===== 联网排行榜（Supabase）=====
榜地址 = "https://spvouajdnckiyihhccux.supabase.co/rest/v1/scores"
玩家地址 = "https://spvouajdnckiyihhccux.supabase.co/rest/v1/players"
榜公钥 = "sb_publishable_gOcJXjEu8wVL7tDFNCL5yw_7Y7Zy7ET"
身份文件 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "逃家身份.json")


def 读身份():
    try:
        with open(身份文件, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def 写身份(数据):
    try:
        with open(身份文件, "w", encoding="utf-8") as f:
            json.dump(数据, f, ensure_ascii=False, indent=1)
    except Exception:
        pass


def 取身份():
    """返回 (client_id, 已登记的名字)，没登记就是空名字。"""
    数据 = 读身份()
    cid = 数据.get("client_id")
    if not cid:
        import uuid
        cid = "c" + uuid.uuid4().hex[:20]
        数据["client_id"] = cid
        写身份(数据)
    return cid, 数据.get("name", "")


def 登记名字(名字):
    """往服务器登记名字，名字全服唯一。返回 (成功?, 提示)。"""
    cid, 已有 = 取身份()
    if 已有:
        return False, "你已经登记过「%s」，名字登记后不能改。" % 已有
    req = urllib.request.Request(
        玩家地址,
        data=json.dumps([{"name": 名字, "client_id": cid}]).encode("utf-8"),
        headers={"apikey": 榜公钥, "Authorization": "Bearer " + 榜公钥,
                 "Content-Type": "application/json", "Prefer": "return=minimal"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            if r.status in (200, 201):
                数据 = 读身份()
                数据["name"] = 名字
                写身份(数据)
                return True, "名字「%s」登记成功。" % 名字
    except urllib.error.HTTPError as e:
        if e.code == 409:
            return False, "这个名字被占了，换一个。"
        return False, "登记失败（%s）。" % e.code
    except Exception:
        return False, "连不上服务器，稍后再试。"
    return False, "登记失败。"


def 上传成绩(天数, 站数, 剩余钱):
    """把这一局的成绩传到服务器榜单。失败也不影响游戏结束。"""
    cid, 名字 = 取身份()
    if not 名字:
        print("还没登记名字，先起一个（全服唯一，登记后不能改）。")
        try:
            名字 = input("名字（最多 4 个字）：").strip()[:4]
        except EOFError:
            名字 = ""
        if not 名字:
            print("没名字就不上榜了，这局成绩留在本机。")
            print()
            return
        成功, 提示 = 登记名字(名字)
        print(提示)
        if not 成功:
            print("这局先不上榜。")
            print()
            return
        _, 名字 = 取身份()
    数据 = [{
        "mode": 难度ID,
        "ending": "倒在路上",
        "days": int(天数),
        "stations": int(站数),
        "money": int(剩余钱),
        "name": 名字,
        "client_id": cid,
    }]
    try:
        req = urllib.request.Request(
            榜地址,
            data=json.dumps(数据).encode("utf-8"),
            headers={
                "apikey": 榜公钥,
                "Authorization": "Bearer " + 榜公钥,
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            print("成绩已上榜：%s · %d 天 · %d 站 · 剩 %d 块" % (名字, 天数, 站数, 剩余钱))
    except urllib.error.HTTPError as e:
        print("上传失败（%s），这局成绩先留在本机。" % e.code)
    except Exception:
        print("连不上榜单服务器，这局成绩先留在本机。")
    print()


def 查看榜单():
    """拉前 10 名，按天数、站数排序。"""
    try:
        url = 榜地址 + "?select=name,days,stations,money,created_at&order=days.desc,stations.desc&limit=10"
        req = urllib.request.Request(
            url,
            headers={"apikey": 榜公钥, "Authorization": "Bearer " + 榜公钥},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            榜 = json.loads(r.read().decode("utf-8"))
    except Exception:
        print("榜单暂时拉不下来，等会儿再试。")
        print()
        return
    if not 榜:
        print("还没有人上榜，你上第一个吧。")
        print()
        return
    print("———— 无尽榜 · 前 10 ————")
    for i, 项 in enumerate(榜, 1):
        print("%2d. %-4s %4d 天 · %4d 站 · 剩 %3d 块"
              % (i, 项.get("name") or "匿名", 项.get("days", 0),
                 项.get("stations", 0), 项.get("money", 0)))
    print("————————————————————")
    print()

难度ID = "endless"
难度名 = "无尽版（非正式）"
血条上限 = 100
血条 = 100
天 = 1
钱 = 0
阶段 = 0          # 0=在家；>=1 表示已经出门，值就是走过的站数
圈 = 1            # 第几圈（每走完四站算一圈）
经历 = []

基础站名 = {1: "幼儿园站", 2: "学校站", 3: "大学站", 4: "终点站"}


def 站名(第几站):
    return 基础站名[(第几站 - 1) % 4 + 1]


def 本站圈(第几站):
    return (第几站 - 1) // 4 + 1


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
        "log": [{"t": t} for t in 记录[-30:]],
    }
    目录 = os.path.dirname(os.path.abspath(__file__))
    文件名 = "逃家存档-无尽版-%s.json" % datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    路径 = os.path.join(目录, 文件名)
    try:
        with open(路径, "w", encoding="utf-8") as f:
            json.dump(数据, f, ensure_ascii=False, indent=2)
        print("存档已导出：%s" % 文件名)
    except Exception as e:
        print("导出失败：%s" % e)
    print()


def 导入存档():
    """返回 (天数, 血量, 记录, 钱, 阶段)；失败返回 None。"""
    路径 = input("把存档文件拖进来（或输入路径）：").strip().strip('"').strip("'")
    if not 路径:
        print("没填路径，取消导入。")
        return None
    if not os.path.exists(路径):
        print("这个路径找不到文件：%s" % 路径)
        return None
    try:
        if zipfile.is_zipfile(路径):
            with zipfile.ZipFile(路径) as z:
                名单 = [n for n in z.namelist() if n.lower().endswith(".json")]
                if not 名单:
                    print("这个压缩包里没有存档 json。")
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
    新阶段 = max(0, int(数据.get("stage", 0) or 0))
    print("已导入：第 %d 天，血条 %d / %d，钱 %d 块，已走过 %d 站"
          % (int(数据["day"]), 血量, 血条上限, 新钱, 新阶段))
    print()
    return (int(数据["day"]), 血量, 记录, 新钱, 新阶段)


def 打车费(第几站):
    """越往后越贵：第一圈 10 块，每进一圈加 5 块。"""
    return 10 + (本站圈(第几站) - 1) * 5


def 扣血值(第几站):
    """站台扣血：幼儿园 20 / 学校 30 / 大学 40 / 终点站 15，之后每圈各加 10。"""
    基数 = [20, 30, 40, 15][(第几站 - 1) % 4]
    return 基数 + (本站圈(第几站) - 1) * 10


def 安全率(第几站):
    """平安过去的概率：幼儿园 25 / 学校 20 / 大学 15 / 终点站 40，之后每圈降 5，最低 5。"""
    基数 = [25, 20, 15, 40][(第几站 - 1) % 4]
    return max(5, 基数 - (本站圈(第几站) - 1) * 5)


def 过站(打车, 第几站):
    """返回 True 表示整局结束（血条归零）。"""
    global 血条, 阶段
    站 = 站名(第几站)
    圈数 = 本站圈(第几站)
    车费 = 打车费(第几站)
    扣 = 扣血值(第几站)
    安全 = 安全率(第几站)

    if 打车:
        print("你塞给司机 %d 块，他一脚油门直接把你送过这一站。" % 车费)
    elif (第几站 - 1) % 4 == 0:
        print("站台边上蹲着一群小孩，尖叫着绕着你跑，声音直接钻进脑子里。")
        if random.randint(1, 100) <= 安全:
            print("你从孩子堆里挤了过去，衣服被拽歪了，人没事。")
        else:
            print("被一群小孩缠住，吵得头都要裂了，扣 %d 血。" % 扣)
            血条 -= 扣
    elif (第几站 - 1) % 4 == 1:
        print("你小学的班主任正站在站牌底下，一眼就认出你了。")
        if random.randint(1, 100) <= 安全:
            print("你把帽檐压得很低贴着墙走，班主任正忙着训别的学生，没追上来。")
        else:
            print("老师一把揪住你：逃学？跟我回办公室！扣 %d 血。" % 扣)
            血条 -= 扣
    elif (第几站 - 1) % 4 == 2:
        print("你哥在站台上抽烟，看见你，把烟一扔就冲过来。")
        if random.randint(1, 100) <= 安全:
            print("公交刚好进站，你混在人堆里挤上去，你哥扑了个空。")
        else:
            print("被你哥一把按住，扣 %d 血。" % 扣)
            血条 -= 扣
    else:
        print("终点站的检票员正在挨个查票，你手里那张票早就过期了。")
        if random.randint(1, 100) <= 安全:
            print("你混在一群下车的人里溜了出去，检票员没注意。")
        else:
            print("检票员把你拎出来，罚了 %d 血才放人。" % 扣)
            血条 -= 扣

    if 血条 <= 0:
        print()
        print("==============================")
        print("你倒在%s的地上，血条归零。" % 站)
        print("============================================================")
        print("无尽结算：撑过 %d 天，走过 %d 站，手里还剩 %d 块。" % (天, 第几站 - 1, 钱))
        print("结局达成：倒在路上")
        print("============================================================")
        上传成绩(天, 第几站 - 1, 钱)
        return True

    阶段 = 第几站
    if 第几站 % 4 == 0:
        print()
        print("车报站：终点站到了。这是第 %d 圈的终点。" % 圈数)
        print("下车还能再走一圈，但下一圈的站台会更凶。")
        print()
    else:
        print("过了这一站，下一站：%s（第 %d 圈）。" % (站名(第几站 + 1), 本站圈(第几站 + 1)))
    print("血条 %d / %d，钱 %d 块，已走过 %d 站" % (血条, 血条上限, 钱, 阶段))
    print()
    return False


print("==== 逃家游戏 · 无尽版（非正式草稿）====")
print("没有终点。车一直有，站台一圈一圈重复，只会越来越凶。")
print("每天考试挣钱：60 分以上给 1-3 块，90 分以上给 3-5 块；不及格扣血。")
print("第一次出门：车票 50 块 + 买通弟弟 10 块 = 60 块。")
print("站台每一站可以「等」车（不要钱，但可能被熟人逮住），或者「打车」直接过站。")
print("打车费每进一圈涨 5 块，站台扣血每圈涨 10 点，平安概率每圈降 5%。")
print("血条归零就结算：撑过的天数、走过的站数、剩下的钱。")
print()
print("提示：输入 导出 / 导入 存档；输入 12345678 作者模式改钱。")
print()

已出门 = False
最近一站 = 阶段

while True:
    print("———— 第 %d 天 · 圈 %d · 钱 %d 块 · 血 %d / %d ————"
          % (天, 圈, 钱, 血条, 血条上限))
    if 阶段 > 0:
        操作 = input("等（等车，不要钱）/ 打车（%d 块，直接过站）/ 榜 / 改名 / 导出 / 导入："
                    % 打车费(阶段 + 1)).strip()
    else:
        操作 = input("按回车考试 / 跑（出门坐车）/ 110 / 榜 / 改名 / 12345678 / 导出 / 导入：").strip()

    if 操作 in ("导入", "导入存档"):
        结果 = 导入存档()
        if 结果:
            天, 血条, 经历, 钱, 阶段 = 结果
            已出门 = 阶段 > 0
            圈 = (阶段 // 4) + 1 if 阶段 > 0 else 1
        continue

    if 操作 in ("榜", "榜单", "排行榜"):
        查看榜单()
        continue

    if 操作 in ("改名", "登记名字", "名字"):
        cid, 已有 = 取身份()
        if 已有:
            print("你已经登记过「%s」，登记后不能改。" % 已有)
        else:
            try:
                nm = input("起个名字（全服唯一，最多 4 字）：").strip()[:4]
            except EOFError:
                nm = ""
            if nm:
                print(登记名字(nm)[1])
        print()
        continue

    if 操作 in ("导出", "导出存档"):
        导出存档(天, 血条, 经历)
        continue

    if 操作 == "12345678":
        钱 = 读取整数("设置你现在有多少钱：", 0)
        钱 = max(0, 钱)
        print("作者模式：你有 %d 块。" % 钱)
        print()
        continue

    if 操作 == "110" and 阶段 == 0:
        print()
        print("你拨通 110，接电话的是派出所。")
        print("警察：你妈又打你了？这个月第几次了。")
        print("你：……第三次。")
        print("警察：我们过去一趟，但你要不要考虑先离开那个家？")
        print("==============================")
        print("结局达成：报警了，但这次没人送你走")
        print("==============================")
        break

    # ===== 已经出门：站台循环 =====
    if 阶段 > 0:
        下一站 = 阶段 + 1
        if 操作 == "打车":
            车费 = 打车费(下一站)
            if 钱 < 车费:
                print("司机看了看你手里的钱，摆摆手开走了。这一站只能等公交。")
                print()
                continue
            钱 -= 车费
            if 过站(True, 下一站):
                break
            圈 = (阶段 // 4) + 1
            continue
        if 操作 in ("等", ""):
            if 过站(False, 下一站):
                break
            圈 = (阶段 // 4) + 1
            continue
        print("站台上只有两个选择：等（等车）或者 打车。要存档就输 导出 / 导入。")
        print()
        continue

    # ===== 还在家 =====
    if 操作 == "跑":
        if 钱 >= 60:
            钱 -= 60
            print("你把 50 块塞进售票窗口，又给了弟弟 10 块。")
            print("弟弟没吭声，把门开了一条缝。")
            print("你走出家门，站牌就在街口。第一站：幼儿园站。")
            print()
            阶段 = 0
            已出门 = True
            if 过站(False, 1):
                break
            圈 = 1
            continue
        if 钱 >= 50:
            血条 -= 10
            print("你攥着 50 块去买票，弟弟横在门口：没好处费，别想走。扣 10 血。")
        else:
            血条 -= 20
            print("你刚把门拉开一条缝，妈妈一把把你拽回来，抄起拖鞋就打——扣 20 血。")
        print("血条 %d / %d，钱 %d 块" % (血条, 血条上限, 钱))
        print()
        if 血条 <= 0:
            print("================================")
            print("无尽结算：撑过 %d 天，还没走出门，血条归零。" % 天)
            print("结局达成：没走出这个家")
            print("================================")
            上传成绩(天, 0, 钱)
            break
        continue

    # 考试
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
        print("================================")
        print("无尽结算：撑过 %d 天，血条归零。" % 天)
        print("结局达成：没撑到能走的那天")
        print("================================")
        上传成绩(天, 阶段, 钱)
        break

    天 += 1
    print()
