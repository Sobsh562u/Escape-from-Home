#!/usr/bin/env python3
"""站点一致性检查：根页面与 网页版/ 页面必须保持同款关键要素，且内部链接不许断。

用法：python3 tools/check_site.py   （在仓库根目录跑；CI 里也是这条）
失败时返回码 1，并列出具体不一致项。
"""
import os
import re
import sys

ROOT_PAGE = "index.html"
WEB_PAGE = "网页版/index.html"
PAGES = (ROOT_PAGE, WEB_PAGE)
PACKAGES = (
    "包/逃家游戏_Windows.exe",
    "包/逃家游戏_Linux",
    "包/逃家游戏_Android.apk",
)

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        problems.append(f"缺少文件：{path}")
        return ""


def nav_names(html):
    names = set()
    for raw in re.findall(r'href="([^"]+\.html)"', html):
        if raw.startswith(("http://", "https://")):
            continue
        names.add(os.path.basename(raw.split("#")[0].split("?")[0]))
    return names


def hashes(html):
    return set(re.findall(r"\b[0-9a-f]{64}\b", html))


def version(html):
    return set(re.findall(r"v\d+\.\d+\.\d+\.\d+", html))


def broken_refs(page, html):
    base = os.path.dirname(page)
    broken = []
    for raw in re.findall(r'(?:href|src)="([^"]+)"', html):
        if raw.startswith(("http://", "https://", "data:", "#", "mailto:")):
            continue
        target = raw.split("#")[0].split("?")[0]
        if not target:
            continue
        path = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(path):
            broken.append(f"{page} -> {raw}")
    return broken


def main():
    pages = {}
    for page in PAGES:
        pages[page] = read(page)
        if not pages[page]:
            continue
        if 'id="actSec"' not in pages[page]:
            problems.append(f"{page} 缺少激活码区块 id=\"actSec\"")

        for item in broken_refs(page, pages[page]):
            problems.append(f"断链：{item}")

    for pkg in PACKAGES:
        if not os.path.exists(pkg):
            problems.append(f"缺少安装包：{pkg}")
        elif os.path.getsize(pkg) == 0:
            problems.append(f"安装包为空：{pkg}")

    root, web = pages[ROOT_PAGE], pages[WEB_PAGE]
    if root and web:
        for label, a, b in (
            ("导航链接", nav_names(root), nav_names(web)),
            ("激活码哈希", hashes(root), hashes(web)),
            ("版本号", version(root), version(web)),
        ):
            if a != b:
                problems.append(f"两页{label}不一致：根={sorted(a)} 网页版={sorted(b)}")

    if problems:
        print(f"✗ 站点检查未通过，{len(problems)} 个问题：")
        for p in problems:
            print("  -", p)
        return 1

    print("✓ 站点检查通过：两页关键要素一致，无断链，安装包齐全")
    return 0


if __name__ == "__main__":
    sys.exit(main())
