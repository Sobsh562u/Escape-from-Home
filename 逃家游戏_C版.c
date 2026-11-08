/*
 * 逃家游戏（C 语言版）
 * Copyright (c) 2026 Sobsh562u
 * SPDX-License-Identifier: MIT
 *
 * 本文件以 MIT 许可证发布；转载、修改、再分发时请保留本版权声明与仓库中的 LICENSE 文件。
 *
 * 编译方式：
 *   Linux / macOS : gcc 逃家游戏_C版.c -O2 -o 逃家游戏
 *   Windows (MinGW): gcc 逃家游戏_C版.c -O2 -o 逃家游戏.exe
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define 最大血条 100
#define 通关天数 5
#define 输入长度 64

/* 读一行输入，去掉换行符 */
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

int main(void) {
#ifdef _WIN32
    SetConsoleOutputCP(65001);   /* Windows 控制台用 UTF-8，中文不乱码 */
#endif
    srand((unsigned)time(NULL));

    int 血条 = 100;
    int 天 = 0;
    char 操作[输入长度];

    printf("你被关在家里写作业，想逃出去！\n");
    printf("只要撑过 %d 天，就是你 18 岁生日，而且你名下有套房，就能逃了。\n", 通关天数);
    printf("\n");
    printf("提示：每天按回车考试。但如果实在忍不了，可以输入 110……\n");
    printf("      偷偷告诉你：输入 12345678 可以跳天数。\n");
    printf("\n");

    for (;;) {
        printf("———— 第 %d 天 ————\n", 天);
        printf("妈妈发卷子，按回车考试；想报警就输入 110；跳天数输入 12345678：");
        读一行(操作, 输入长度);

        /* 作者模式：跳天数 */
        if (strcmp(操作, "12345678") == 0) {
            char 数字[输入长度];
            printf("跳到第几天？（可以填负数！）：");
            读一行(数字, 输入长度);
            天 = atoi(数字);
            continue;
        }

        /* 报警结局 */
        if (strcmp(操作, "110") == 0) {
            printf("\n");
            printf("你拨通了 110……\n");
            printf("警察：你好，请问发生什么事？\n");
            printf("你：我妈家暴我，把我关在家里天天逼我考试！\n");
            printf("警察：收到，我们马上出警。\n");
            printf("\n");
            printf("==============================\n");
            printf("几分钟后，警车停在你家楼下。\n");
            printf("警察把你妈妈带走了。\n");
            printf("你名下有房，明天 18 岁生日——自由了！\n");
            printf("隐藏结局达成：正义の报警！\n");
            printf("==============================\n");
            break;
        }

        /* 负天数彩蛋 */
        if (天 < 0) {
            printf("\n");
            if (天 <= -100) {
                printf("==============================\n");
                printf("你穿越到了 %d 年前……\n", -天);
                printf("那时候你妈妈都还没出生！\n");
                printf("谁在逼你考试？？？\n");
                printf("结局达成：祖父悖论\n");
                printf("==============================\n");
            } else {
                printf("你还是个受精卵，在妈妈肚子里。\n");
                printf("没有卷子可以考，也没有血条可以掉。\n");
                printf("结局达成：受精卵体外死亡\n");
                printf("==============================\n");
            }
            break;
        }

        /* 撑过 5 天通关 */
        if (天 >= 通关天数) {
            printf("\n");
            printf("==============================\n");
            printf("第 %d 天结束了！你还活着！\n", 通关天数);
            printf("明天就是你 18 岁生日，你掏出钥匙……\n");
            printf("打开那套写着你名字的房子。\n");
            printf("你终于逃出这个家！结局达成！\n");
            printf("==============================\n");
            break;
        }

        /* 正常考试 */
        int 分数 = rand() % 101;
        printf("你这次考了 %d 分\n", 分数);

        if (分数 == 0) {
            printf("妈妈：你怎么考了鸭蛋？！？\n");
            血条 -= 40;
        } else if (分数 < 60) {
            printf("妈妈：你怎么又考砸了？！\n");
            血条 -= 15;
        } else {
            printf("妈妈：这次考得不错，奖励你！\n");
            血条 += 10;
        }

        if (血条 > 最大血条) {
            血条 = 最大血条;
        }
        printf("你现在的血条： %d / %d\n", 血条, 最大血条);

        if (血条 <= 0) {
            printf("\n");
            printf("你的血条归零……你死了。\n");
            printf("GAME OVER —— 没撑到 18 岁。\n");
            break;
        }

        天 += 1;
        printf("\n");
    }

    printf("\n按回车键退出...");
    读一行(操作, 输入长度);
    return 0;
}
//（注：内容由AI生成）
