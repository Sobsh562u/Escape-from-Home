/*
 * 逃家游戏（C 语言桌面版）
 * Copyright (c) 2026 Sobsh562u
 * SPDX-License-Identifier: MIT
 *
 * 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。
 *
 * 编译方式：
 *   Linux / macOS : gcc 逃家游戏_C版.c -O2 -o 逃家游戏
 *   Windows (MinGW): x86_64-w64-mingw32-gcc 逃家游戏_C版.c -O2 -o 逃家游戏.exe
 *
 * 这一版是桌面端的完整实现：
 *   1. 四个难度（原始 / 反转 / 困难 / 极限）同一个程序，启动时选
 *   2. 支持「导出」「导入」存档，存档是 json，和网页版、Python 版同一套字段
 *   3. 不依赖任何第三方库，只要 libc
 *
 * 命令行可以直接指定难度，跳过菜单：
 *   ./逃家游戏 -m orig    原始版
 *   ./逃家游戏 -m revert  反转版
 *   ./逃家游戏 -m hard    困难版
 *   ./逃家游戏 -m limit   极限版
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define 输入长度 128
#define 记录上限 80
#define 记录长度 120

/* ==================== 难度表 ==================== */

typedef struct {
    const char *id;      /* 存档里的 mode 字段 */
    const char *名;
    int 初始血条;
    int 上限;
    int 目标天数;
} 难度配置;

static 难度配置 难度表[] = {
    {"orig",   "原始版", 100, 100, 5},
    {"revert", "反转版", 100, 100, 6570},
    {"hard",   "困难版",  50,  50, 10},
    {"limit",  "极限版", 100, 100, 5},
    {"run",    "跑路版", 100, 100, 0},   /* 目标天数 0 = 不限天数，攒钱跑路 */
};

static int 难度数 = (int)(sizeof(难度表) / sizeof(难度表[0]));

/* ==================== 经历记录 ==================== */

static char 经历[记录上限][记录长度];
static int 经历数 = 0;

static void 记录(const char *fmt, ...) {
    if (经历数 >= 记录上限) return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(经历[经历数], 记录长度, fmt, ap);
    va_end(ap);
    经历数++;
}

static void 清空经历(void) {
    经历数 = 0;
}

/* ==================== 输入 ==================== */

static void 读一行(char *buf, int len) {
    if (fgets(buf, len, stdin) == NULL) {
        buf[0] = '\0';
        return;
    }
    size_t n = strlen(buf);
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
        buf[--n] = '\0';
    }
}

static void 去空白(char *s) {
    char *p = s;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n > 0 && isspace((unsigned char)s[n - 1])) s[--n] = '\0';
}

static void 去引号(char *s) {
    size_t n = strlen(s);
    if (n >= 2 && (s[0] == '"' || s[0] == '\'') && s[n - 1] == s[0]) {
        s[n - 1] = '\0';
        memmove(s, s + 1, strlen(s + 1) + 1);
    }
}

/* ==================== 存档：导出 ==================== */

static void 时间串(char *out, int len) {
    time_t t = time(NULL);
    struct tm *tmv = localtime(&t);
    if (tmv) {
        strftime(out, len, "%Y-%m-%d %H:%M:%S", tmv);
    } else {
        strcpy(out, "unknown");
    }
}

/* 把字符串按 JSON 规则转义后写进文件 */
static void 写JSON串(FILE *f, const char *s) {
    for (const char *p = s; *p; p++) {
        switch (*p) {
            case '"':  fputs("\\\"", f); break;
            case '\\': fputs("\\\\", f); break;
            case '\n': fputs("\\n", f); break;
            case '\r': fputs("\\r", f); break;
            case '\t': fputs("\\t", f); break;
            default:
                if ((unsigned char)*p < 0x20) fprintf(f, "\\u%04x", *p);
                else fputc(*p, f);
        }
    }
}

static void 导出存档(const 难度配置 *c, int 天, int 血条, int 钱, int 阶段) {
    if (血条 <= 0) {
        printf("这局已经结束了，重新开一局再导出吧。\n");
        return;
    }
    char 时间[64];
    时间串(时间, (int)sizeof(时间));

    char 文件名[256];
    snprintf(文件名, sizeof(文件名), "逃家游戏存档-%s-第%d天.json", c->名, 天);

    FILE *f = fopen(文件名, "w");
    if (!f) {
        printf("文件写不进去（可能没有写权限）。\n");
        return;
    }
    fprintf(f, "{\n");
    fprintf(f, "  \"game\": \"逃家游戏 Escape from Home\",\n");
    fprintf(f, "  \"packVersion\": 2,\n");
    fprintf(f, "  \"mode\": \"%s\",\n", c->id);
    fprintf(f, "  \"modeLabel\": \"%s\",\n", c->名);
    fprintf(f, "  \"day\": %d,\n", 天);
    fprintf(f, "  \"hp\": %d,\n", 血条);
    fprintf(f, "  \"max\": %d,\n", c->上限);
    fprintf(f, "  \"savedAt\": \"%s\",\n", 时间);
    if (钱 >= 0) {
        fprintf(f, "  \"money\": %d,\n", 钱);
        fprintf(f, "  \"stage\": %d,\n", 阶段);
    }
    fprintf(f, "  \"log\": [\n");
    for (int i = 0; i < 经历数; i++) {
        fprintf(f, "    {\"t\": \"");
        写JSON串(f, 经历[i]);
        fprintf(f, "\", \"c\": \"\"}%s\n", (i == 经历数 - 1) ? "" : ",");
    }
    fprintf(f, "  ]\n");
    fprintf(f, "}\n");
    fclose(f);

    printf("存档已导出：%s\n", 文件名);
    printf("想接着玩：网页版点「导入存档」选它（网页版认 zip 和 json），");
    printf("或者下次开这个程序输入「导入」。\n");
}

/* ==================== 存档：导入 ==================== */

/* 在 json 文本里找 "键": 数值 */
static int 找数值(const char *buf, const char *键, int *out) {
    char 模式[64];
    snprintf(模式, sizeof(模式), "\"%s\"", 键);
    const char *p = strstr(buf, 模式);
    if (!p) return 0;
    p = strchr(p + strlen(模式), ':');
    if (!p) return 0;
    p++;
    while (*p && (*p == ' ' || *p == '\t')) p++;
    if (*p != '-' && *p != '+' && !isdigit((unsigned char)*p)) return 0;
    *out = atoi(p);
    return 1;
}

/* 在 json 文本里找 "键": "字符串" */
static int 找字符串(const char *buf, const char *键, char *out, int len) {
    char 模式[64];
    snprintf(模式, sizeof(模式), "\"%s\"", 键);
    const char *p = strstr(buf, 模式);
    if (!p) return 0;
    p = strchr(p + strlen(模式), ':');
    if (!p) return 0;
    p = strchr(p, '"');
    if (!p) return 0;
    p++;
    const char *q = strchr(p, '"');
    if (!q) return 0;
    int n = (int)(q - p);
    if (n >= len) n = len - 1;
    memcpy(out, p, (size_t)n);
    out[n] = '\0';
    return 1;
}

/* 读取本地 json 存档，成功返回 1 */
static int 读存档文件(const char *路径, const 难度配置 *c, int *天数, int *血量, int *钱, int *阶段) {
    FILE *f = fopen(路径, "rb");
    if (!f) {
        printf("打不开这个文件：%s\n", 路径);
        return 0;
    }
    long 大小 = 0;
    fseek(f, 0, SEEK_END);
    大小 = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (大小 <= 0 || 大小 > 2000000L) {
        fclose(f);
        printf("这个文件大小不对劲，读不了。\n");
        return 0;
    }
    char *buf = (char *)malloc((size_t)大小 + 1);
    if (!buf) {
        fclose(f);
        printf("内存不够，读不了。\n");
        return 0;
    }
    size_t 读 = fread(buf, 1, (size_t)大小, f);
    buf[读] = '\0';
    fclose(f);

    if (strstr(buf, "\"encrypted\"") && strstr(buf, "true")) {
        free(buf);
        printf("这是带密码的加密存档，桌面版解不开。\n");
        printf("去网页版导入它，或者导出时把密码留空再来。\n");
        return 0;
    }
    if (!找数值(buf, "day", 天数) || !找数值(buf, "hp", 血量)) {
        free(buf);
        printf("存档内容不对（缺天数或血条），导入失败。\n");
        return 0;
    }
    *钱 = 0;
    *阶段 = 0;
    找数值(buf, "money", 钱);
    找数值(buf, "stage", 阶段);
    char 包里模式[32] = "";
    if (找字符串(buf, "mode", 包里模式, (int)sizeof(包里模式)) &&
        strcmp(包里模式, c->id) != 0) {
        printf("注意：这份存档是「%s」，这里是「%s」，天数和血条照搬，规则按这边的来。\n", 包里模式, c->名);
    }
    free(buf);
    return 1;
}

/* ==================== 结局判定辅助 ==================== */

static void 分隔线(void) {
    printf("==============================\n");
}

static void 结束语(void) {
    printf("\n按回车键退出...");
    char 缓冲[输入长度];
    读一行(缓冲, 输入长度);
}

/* ==================== 各难度的考试规则 ==================== */

typedef struct {
    int 扣血;
    int 死了;         /* 1 表示直接打死，不看血条 */
    const char *结局;  /* 死了时的结局名 */
    const char *台词;
} 考试结果;

static 考试结果 考一次(const 难度配置 *c, int 分数) {
    考试结果 r = {0, 0, "被打死", ""};
    if (strcmp(c->id, "orig") == 0) {
        if (分数 == 0) { r.扣血 = -40; r.台词 = "妈妈：你怎么考了鸭蛋？！？"; }
        else if (分数 < 60) { r.扣血 = -15; r.台词 = "妈妈：你怎么又考砸了？！"; }
        else { r.扣血 = 10; r.台词 = "妈妈：这次考得不错，奖励你！"; }
    } else if (strcmp(c->id, "revert") == 0) {
        if (分数 < 60) {
            static const int 加血池[5] = {20, 40, 60, 80, 100};
            r.扣血 = 加血池[rand() % 5];
            r.台词 = "妈妈大喜！考砸了她反而放心，加血！";
        } else {
            static const int 扣血池[5] = {20, 40, 60, 80, 10000};
            r.扣血 = -扣血池[rand() % 5];
            r.台词 = "妈妈暴怒！考好了她怕你太优秀，扣血！";
        }
    } else if (strcmp(c->id, "hard") == 0) {
        if (分数 == 0) { r.扣血 = -25; r.台词 = "妈妈：鸭蛋？！跪墙角！"; }
        else if (分数 < 60) { r.扣血 = -15; r.台词 = "妈妈：又不及格！"; }
        else if (分数 < 90) { r.扣血 = 5; r.台词 = "妈妈：还行，别骄傲。"; }
        else { r.扣血 = 8; r.台词 = "妈妈：不错。"; }
    } else if (strcmp(c->id, "run") == 0) {
        if (分数 == 0) { r.扣血 = -40; r.台词 = "妈妈：鸭蛋？跪下！"; }
        else if (分数 < 60) { r.扣血 = -15; r.台词 = "妈妈：又不及格，一分钱都别想要。"; }
        else { r.扣血 = 0; r.台词 = "妈妈：考得还行。"; }
    } else { /* limit */
        if (分数 == 0) {
            r.死了 = 1;
            r.结局 = "被皮带打死";
            r.台词 = "爸爸：你竟然考零蛋？！爸爸解下皮带……啪啪啪——皮带打死，血再多也没用。";
            return r;
        }
        r.扣血 = -(100 - 分数);
        r.台词 = (分数 < 60) ? "爸爸：这么点分？皮带伺候！" : "爸爸：还算像样，皮带放下了。";
    }
    return r;
}

/* ==================== 逃跑 ==================== */

/* 返回 1 表示直接结束游戏 */
static int 逃跑(const 难度配置 *c, const int 天, int *血条) {
    if (strcmp(c->id, "orig") == 0) {
        *血条 -= 20;
        printf("你想走出这个家门，刚把门拉开一条缝，妈妈一把把你拽回来，抄起拖鞋就打——扣 20 血。\n");
        return 0;
    }
    if (strcmp(c->id, "revert") == 0) {
        if (天 < 3650) {
            printf("你太小了，妈妈根本追不上，你跑掉了！\n");
            分隔线();
            printf("结局达成：小小年纪成功逃家\n");
            分隔线();
            return 1;
        }
        if (天 < 6570) {
            printf("半大孩子，跑了又回来了。\n");
            return 0;
        }
        printf("都 18 岁了才跑？妈妈就在门口等着，当场抓回。\n");
        分隔线();
        printf("结局达成：门口被抓\n");
        分隔线();
        return 1;
    }
    if (strcmp(c->id, "hard") == 0) {
        if (rand() % 100 < 20) {
            printf("天没黑你不敢跑，被妈妈抓个正着，扣 10 血！\n");
            *血条 -= 10;
        } else {
            printf("黑灯瞎火跑出门，又冷又饿，扣 5 血。\n");
            *血条 -= 5;
        }
        return 0;
    }
    printf("你没跑，但爸爸盯着你写作业到半夜，扣 5 血。\n");
    *血条 -= 5;
    return 0;
}

/* ==================== 跑路版：攒钱跑路 ==================== */

/* 攒够 60 出门；返回 1 表示当场死亡 */
static int 跑路(int *血条, int *钱, int *阶段) {
    if (*钱 >= 60) {
        *钱 -= 60;
        printf("你把 50 块塞进售票窗口，又给了弟弟 10 块。弟弟数了数，没吭声，把门开了一条缝。\n");
        printf("你走出家门，夜风灌进领口，公交站牌就在街口。\n");
        printf("从这里开始：输入「等」等公交（免费，但那几站都是熟人），输入「打车」花 10 块直接过站。\n");
        *阶段 = 1;
        return 0;
    }
    if (*钱 >= 50) {
        *血条 -= 10;
        printf("你攥着 50 块去买票，弟弟横在门口：没好处费，别想走。扣 10 血。\n");
        return *血条 <= 0;
    }
    *血条 -= 20;
    printf("你想走出这个家门，刚把门拉开一条缝，妈妈一把把你拽回来，抄起拖鞋就打——扣 20 血。\n");
    return *血条 <= 0;
}

/* 站台：返回 1 表示已经出城（通关） */
static int 过站(int *阶段, int *血条, int 打车) {
    int 扣血 = (*阶段 == 1) ? 20 : ((*阶段 == 2) ? 30 : 40);
    int 安全 = (*阶段 == 1) ? 25 : ((*阶段 == 2) ? 20 : 15);

    if (打车) {
        printf("你招手拦了辆出租，塞过去 10 块，司机一脚油门直接把你送过这一站。\n");
    } else if (*阶段 == 1) {
        printf("站台边上蹲着一群小孩，尖叫着绕着你跑，声音直接钻进脑子里。\n");
        if (rand() % 100 < 安全) {
            printf("你从孩子堆里挤了过去，衣服被拽歪了，人没事。\n");
        } else {
            printf("被一群小孩缠住，吵得头都要裂了，扣 %d 血。\n", 扣血);
            *血条 -= 扣血;
        }
    } else if (*阶段 == 2) {
        printf("你小学的班主任正站在站牌底下，一眼就认出你了。\n");
        if (rand() % 100 < 安全) {
            printf("你把帽檐压得很低贴着墙走，班主任正忙着训别的学生，没追上来。\n");
        } else {
            printf("老师一把揪住你：逃学？跟我回办公室！扣 %d 血。\n", 扣血);
            *血条 -= 扣血;
        }
    } else {
        printf("你哥在站台上抽烟，看见你，把烟一扔就冲过来。\n");
        if (rand() % 100 < 安全) {
            printf("公交刚好进站，你混在人堆里挤上去，你哥扑了个空。\n");
        } else {
            printf("被你哥一把按住，扣 %d 血。\n", 扣血);
            *血条 -= 扣血;
        }
    }
    if (*血条 <= 0) return 0;
    *阶段 += 1;
    if (*阶段 >= 4) {
        分隔线();
        printf("你过了最后一站。出城的公路在眼前展开，天亮的时候你已经不在这个城市了。\n");
        printf("结局达成：终点站\n");
        分隔线();
        return 1;
    }
    const char *下一站 = (*阶段 == 2) ? "学校站" : "大学站";
    printf("过了这一站，下一站：%s。\n\n", 下一站);
    return 0;
}

/* ==================== 报警 ==================== */

static void 报警(const 难度配置 *c) {
    printf("\n");
    if (strcmp(c->id, "orig") == 0) {
        printf("你拨通了 110……\n");
        printf("警察问清地址，几分钟后警车停在楼下。\n");
        printf("警察把你妈妈带走了。\n");
        printf("你名下有房，明天 18 岁生日——自由了。\n");
        分隔线();
        printf("隐藏结局达成：正义报警\n");
        分隔线();
    } else if (strcmp(c->id, "revert") == 0) {
        printf("你拨通了 110……\n");
        printf("警察来了，把你抓走了。\n");
        分隔线();
        printf("结局达成：报警反被抓\n");
        分隔线();
    } else if (strcmp(c->id, "hard") == 0) {
        printf("你拨通 110，警察说：小孩子别乱打电话！\n");
        分隔线();
        printf("结局达成：被当成恶作剧，没人来救你\n");
        分隔线();
    } else {
        printf("你拨通 110，接电话的是爸爸。\n");
        printf("爸爸：还敢报警？回家再说。\n");
        分隔线();
        printf("结局达成：报警被爸爸逮住\n");
        分隔线();
    }
}

/* ==================== 高考（反转版） ==================== */

static void 高考(void) {
    int 分数 = rand() % 751;
    printf("高考！你考了 %d 分！\n", 分数);
    分隔线();
    if (分数 >= 700) {
        printf("妈妈：考这么高？肯定作弊！拿鸡毛掸子追着打。\n");
        printf("结局达成：考太高被当成作弊打死了\n");
    } else if (分数 >= 400) {
        printf("本科——但妈妈逼你复读，关在家里不许出门。\n");
        printf("结局达成：考上本科却失去自由\n");
    } else if (分数 >= 200) {
        printf("大专。妈妈懒得管你了，你搬出去住。\n");
        printf("结局达成：成绩一般反而自由了\n");
    } else {
        printf("妈妈气到晕倒，没人管你了。\n");
        printf("结局达成：考砸反而没人管，自由了\n");
    }
    分隔线();
}

/* ==================== 玩一局 ==================== */

static void 玩一局(const 难度配置 *c) {
    int 血条 = c->初始血条;
    int 天 = 0;
    int 钱 = 0;
    int 阶段 = 0;     /* 跑路版：0=在家，1 幼儿园，2 学校，3 大学 */
    char 操作[输入长度];
    char 缓冲[输入长度];

    清空经历();

    printf("==== 逃家游戏 · %s ====\n", c->名);
    if (strcmp(c->id, "run") == 0) {
        printf("血条 %d，不限天数。60 分以上考试给钱，攒够 60 块（车票 50 + 买通弟弟 10）就能出门。\n", c->上限);
    } else {
        printf("血条 %d，目标撑过 %d 天。\n", c->初始血条, c->目标天数);
    }
    printf("每天按回车考试；输入 跑 逃跑；110 报警；12345678 作者模式跳天数。\n");
    printf("输入「导出」存成 json，输入「导入」读存档（网页版、Python 版的包都能用）。\n\n");

    for (;;) {
        if (strcmp(c->id, "run") == 0 && 阶段 > 0) {
            const char *站 = (阶段 == 1) ? "幼儿园站" : ((阶段 == 2) ? "学校站" : "大学站");
            printf("———— 第 %d 天 · %s · 钱 %d 块 ————\n", 天, 站, 钱);
            printf("等（等车，不要钱）/ 打车（10 块，直接过站）：");
        } else {
            printf("———— 第 %d 天 ————\n", 天);
            if (strcmp(c->id, "run") == 0) {
                printf("（钱 %d 块）按回车考试 / 跑 / 110 / 12345678 / 导出 / 导入：", 钱);
            } else {
                printf("按回车考试 / 跑 / 110 / 12345678 / 导出 / 导入：");
            }
        }
        读一行(操作, 输入长度);
        去空白(操作);

        /* ---- 跑路版：站台 ---- */
        if (strcmp(c->id, "run") == 0 && 阶段 > 0) {
            if (操作[0] == '\0' || strcmp(操作, "等") == 0) {
                if (过站(&阶段, &血条, 0)) break;
                if (血条 <= 0) {
                    printf("\n你的血条归零……你倒在站台上。\nGAME OVER —— 没走出这条街。\n");
                    break;
                }
                printf("血条 %d / %d，钱 %d 块\n\n", 血条, c->上限, 钱);
                continue;
            }
            if (strcmp(操作, "打车") == 0) {
                if (钱 < 10) {
                    printf("司机看了看你手里的钱，摆摆手开走了。这一站只能等公交。\n\n");
                    continue;
                }
                钱 -= 10;
                if (过站(&阶段, &血条, 1)) break;
                printf("血条 %d / %d，钱 %d 块\n\n", 血条, c->上限, 钱);
                continue;
            }
            printf("站台上只有两个选择：等（等车）或者 打车。\n\n");
            continue;
        }

        /* ---- 存档 ---- */
        if (strcmp(操作, "导出") == 0 || strcmp(操作, "导出存档") == 0) {
            导出存档(c, 天, 血条, strcmp(c->id, "run") == 0 ? 钱 : -1, 阶段);
            printf("\n");
            continue;
        }
        if (strcmp(操作, "导入") == 0 || strcmp(操作, "导入存档") == 0) {
            printf("把存档文件拖进来，或者直接填路径（只认 .json；zip 请先解压出 存档.json）：");
            读一行(缓冲, 输入长度);
            去引号(缓冲);
            去空白(缓冲);
            if (缓冲[0] == '\0') {
                printf("没填路径，继续玩当前这一局。\n\n");
                continue;
            }
            /* 去掉可能带上的 .zip，提示用户先解压 */
            size_t 长 = strlen(缓冲);
            if (长 > 4 && strcmp(缓冲 + 长 - 4, ".zip") == 0) {
                printf("桌面版读不了压缩包，先解压出里面的 存档.json 再导入。\n");
                continue;
            }
            int 新天 = 0, 新血 = 0, 新钱 = 0, 新阶段 = 0;
            if (读存档文件(缓冲, c, &新天, &新血, &新钱, &新阶段)) {
                天 = 新天;
                血条 = 新血;
                if (新钱 >= 0) 钱 = 新钱;
                阶段 = 新阶段;
                if (血条 > c->上限) 血条 = c->上限;
                if (血条 < 1) 血条 = 1;
                printf("已导入：第 %d 天，血条 %d / %d\n\n", 天, 血条, c->上限);
            } else {
                printf("\n");
            }
            continue;
        }

        /* ---- 作者模式 ---- */
        if (strcmp(操作, "12345678") == 0) {
            if (strcmp(c->id, "run") == 0) {
                printf("设置你现在有多少钱：");
                读一行(缓冲, 输入长度);
                钱 = atoi(缓冲);
                if (钱 < 0) 钱 = 0;
                printf("作者模式：你有 %d 块。（60 块才够车票加买通弟弟）\n\n", 钱);
                continue;
            }
            printf("跳到第几天？（可以填负数！）：");
            读一行(缓冲, 输入长度);
            天 = atoi(缓冲);
            if (天 < 0) {
                printf("\n");
                if (天 <= -100) {
                    分隔线();
                    printf("你穿越到了 %d 年前……\n", -天);
                    printf("那时候你妈妈都还没出生，谁在逼你考试？\n");
                    printf("结局达成：祖父悖论\n");
                    分隔线();
                } else {
                    printf("你还是个受精卵，在妈妈肚子里。没有卷子，也没有血条。\n");
                    分隔线();
                    printf("结局达成：受精卵体外死亡\n");
                    分隔线();
                }
                break;
            }
            continue;
        }

        /* ---- 报警 ---- */
        if (strcmp(操作, "110") == 0) {
            报警(c);
            break;
        }

        /* ---- 逃跑 ---- */
        if (strcmp(操作, "跑") == 0) {
            if (strcmp(c->id, "run") == 0) {
                if (阶段 > 0) {
                    printf("你已经在出门的路上了，站台上只能等车或者打车。\n\n");
                    continue;
                }
                if (跑路(&血条, &钱, &阶段)) {
                    printf("\n你的血条归零……你死了。\nGAME OVER —— 没走出这个家。\n");
                    break;
                }
                if (血条 > c->上限) 血条 = c->上限;
                printf("血条 %d / %d，钱 %d 块\n\n", 血条, c->上限, 钱);
                continue;
            }
            if (逃跑(c, 天, &血条)) break;
            if (血条 > c->上限) 血条 = c->上限;
            printf("血条 %d / %d\n", 血条, c->上限);
            if (血条 <= 0) {
                printf("\n你的血条归零……你死了。\nGAME OVER —— 没撑到 18 岁。\n");
                break;
            }
            /* 原始版逃跑不推进天数，其他版本算一天 */
            if (strcmp(c->id, "orig") != 0) {
                天 += 1;
                记录("第 %d 天：跑了一次，血条 %d / %d", 天 - 1, 血条, c->上限);
            } else {
                记录("第 %d 天：跑了被抓回来，血条 %d / %d", 天, 血条, c->上限);
            }
            printf("\n");
            continue;
        }

        /* ---- 撑到目标天数 ---- */
        if (c->目标天数 > 0 && 天 >= c->目标天数 && strcmp(c->id, "revert") != 0) {
            分隔线();
            printf("第 %d 天结束了，你还活着。18 岁生日，名下有房。\n", c->目标天数);
            printf("结局达成：逃出这个家\n");
            分隔线();
            break;
        }

        /* ---- 反转版：到 6570 天进高考 ---- */
        if (strcmp(c->id, "revert") == 0 && 天 >= c->目标天数) {
            高考();
            break;
        }

        /* ---- 考试 ---- */
        int 分数 = rand() % 101;
        printf("你考了 %d 分。\n", 分数);
        考试结果 r = 考一次(c, 分数);
        printf("%s\n", r.台词);

        if (r.死了) {
            分隔线();
            printf("结局达成：%s（强制结束）\n", r.结局);
            分隔线();
            break;
        }

        if (strcmp(c->id, "run") == 0) {
            /* 跑路版：60 分以上给钱，配 1-3 或 3-5 块 */
            if (分数 >= 60) {
                int 给 = (分数 >= 90) ? (3 + rand() % 3) : (1 + rand() % 3);
                钱 += 给;
                printf("妈妈：考得还行，赏你 %d 块。（现在 %d 块）\n", 给, 钱);
                r.扣血 = 0;
            }
        }
        if (r.扣血 < 0) {
            printf("扣 %d 血。\n", -r.扣血);
        } else if (r.扣血 > 0) {
            printf("加 %d 血。\n", r.扣血);
        }
        血条 += r.扣血;
        if (血条 > c->上限) 血条 = c->上限;
        if (血条 < 0) 血条 = 0;
        printf("血条 %d / %d\n", 血条, c->上限);
        记录("第 %d 天：考了 %d 分，血条 %d / %d", 天, 分数, 血条, c->上限);

        if (血条 <= 0) {
            printf("\n你的血条归零……你死了。\nGAME OVER —— 没撑到 18 岁。\n");
            break;
        }

        天 += 1;
        printf("\n");
    }
}

/* ==================== 入口 ==================== */

static int 选难度(void) {
    char 缓冲[输入长度];
    printf("==== 逃家游戏 · 桌面版 ====\n");
    printf("选个难度：\n");
    for (int i = 0; i < 难度数; i++) {
        if (难度表[i].目标天数 > 0) {
            printf("  %d. %-4s  血条 %3d，撑过 %d 天\n",
                   i + 1, 难度表[i].名, 难度表[i].初始血条, 难度表[i].目标天数);
        } else {
            printf("  %d. %-4s  血条 %3d，不限天数，攒钱跑路\n",
                   i + 1, 难度表[i].名, 难度表[i].初始血条);
        }
    }
    printf("请输入 1-%d（直接回车＝原始版）：", 难度数);
    读一行(缓冲, 输入长度);
    去空白(缓冲);
    if (缓冲[0] == '\0') return 0;
    int n = atoi(缓冲);
    if (n >= 1 && n <= 难度数) return n - 1;
    printf("没看懂，按原始版开始。\n");
    return 0;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    SetConsoleOutputCP(65001);   /* Windows 控制台用 UTF-8，中文不乱码 */
#endif
    srand((unsigned)time(NULL));

    int 选 = -1;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            for (int k = 0; k < 难度数; k++) {
                if (strcmp(argv[i + 1], 难度表[k].id) == 0) 选 = k;
            }
            i++;
        } else if (strncmp(argv[i], "-m=", 3) == 0) {
            for (int k = 0; k < 难度数; k++) {
                if (strcmp(argv[i] + 3, 难度表[k].id) == 0) 选 = k;
            }
        }
    }
    if (选 < 0) 选 = 选难度();

    玩一局(&难度表[选]);
    结束语();
    return 0;
}
