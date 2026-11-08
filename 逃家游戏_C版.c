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

static void 导出存档(const 难度配置 *c, int 天, int 血条) {
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
    fprintf(f, "  \"log\": [\n");
    for (int i = 0; i < 经历数; i++) {
        fprintf(f, "    {\"t\": \"%s\", \"c\": \"\"}%s\n",
                经历[i], (i == 经历数 - 1) ? "" : ",");
    }
    fprintf(f, "  ]\n");
    fprintf(f, "}\n");
    fclose(f);

    printf("存档已导出：%s\n", 文件名);
    printf("想接着玩：网页版点「导入存档」选它（压缩包也行，解压出 json 就行），");
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
static int 读存档文件(const char *路径, const 难度配置 *c, int *天数, int *血量) {
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
    const char *台词;
} 考试结果;

static 考试结果 考一次(const 难度配置 *c, int 分数) {
    考试结果 r = {0, 0, ""};
    if (strcmp(c->id, "orig") == 0) {
        if (分数 == 0) { r.扣血 = -40; r.台词 = "妈妈：你怎么考了鸭蛋？！？"; }
        else if (分数 < 60) { r.扣血 = -15; r.台词 = "妈妈：你怎么又考砸了？！"; }
        else { r.扣血 = 10; r.台词 = "妈妈：这次考得不错，奖励你！"; }
    } else if (strcmp(c->id, "revert") == 0) {
        if (分数 < 60) { r.扣血 = 60; r.台词 = "妈妈大喜！考砸了她反而放心，加血！"; }
        else { r.扣血 = -60; r.台词 = "妈妈暴怒！考好了她怕你太优秀，扣血！"; }
    } else if (strcmp(c->id, "hard") == 0) {
        if (分数 == 0) { r.扣血 = -25; r.台词 = "妈妈：鸭蛋？！跪墙角！"; }
        else if (分数 < 60) { r.扣血 = -15; r.台词 = "妈妈：又不及格！"; }
        else if (分数 < 90) { r.扣血 = 5; r.台词 = "妈妈：还行，别骄傲。"; }
        else { r.扣血 = 8; r.台词 = "妈妈：不错。"; }
    } else { /* limit */
        if (分数 == 0) {
            r.死了 = 1;
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
    char 操作[输入长度];
    char 缓冲[输入长度];

    清空经历();

    printf("==== 逃家游戏 · %s ====\n", c->名);
    printf("血条 %d，目标撑过 %d 天。\n", c->初始血条, c->目标天数);
    printf("每天按回车考试；输入 跑 逃跑；110 报警；12345678 作者模式跳天数。\n");
    printf("输入「导出」存成 json，输入「导入」读存档（网页版、Python 版的包都能用）。\n\n");

    for (;;) {
        printf("———— 第 %d 天 ————\n", 天);
        printf("按回车考试 / 跑 / 110 / 12345678 / 导出 / 导入：");
        读一行(操作, 输入长度);
        去空白(操作);

        /* ---- 存档 ---- */
        if (strcmp(操作, "导出") == 0 || strcmp(操作, "导出存档") == 0) {
            导出存档(c, 天, 血条);
            printf("\n");
            continue;
        }
        if (strcmp(操作, "导入") == 0 || strcmp(操作, "导入存档") == 0) {
            printf("把存档文件拖进来，或者直接填路径（.json / .zip 都行）：");
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
            int 新天 = 0, 新血 = 0;
            if (读存档文件(缓冲, c, &新天, &新血)) {
                天 = 新天;
                血条 = 新血;
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
        if (天 >= c->目标天数 && strcmp(c->id, "revert") != 0) {
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
            printf("结局达成：被皮带打死（强制结束）\n");
            分隔线();
            break;
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
        printf("  %d. %-4s  血条 %3d，撑过 %d 天\n",
               i + 1, 难度表[i].名, 难度表[i].初始血条, 难度表[i].目标天数);
    }
    printf("请输入 1-4（直接回车＝原始版）：");
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
