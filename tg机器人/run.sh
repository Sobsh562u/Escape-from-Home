#!/usr/bin/env bash
# 在 GitHub Codespaces / 任意 Linux 云机器里一键启动发码机器人
# 用法：bash run.sh   （第一次会问你要 token）
set -e

cd "$(dirname "$0")"

if [ -z "$TG_BOT_TOKEN" ]; then
  read -r -p "粘贴 @taojia_group_bot 的 token: " TG_BOT_TOKEN
  export TG_BOT_TOKEN
fi

# Codespaces 的出口在墙外，不需要代理；本地机器才需要设 HTTPS_PROXY
if [ -n "$HTTPS_PROXY" ]; then
  echo "检测到代理：$HTTPS_PROXY"
else
  echo "未设代理（Codespaces 里这是正常的）"
fi

python3 -m pip install --quiet --upgrade requests || pip install --quiet --upgrade requests

echo "启动中… 按 Ctrl+C 停"
while true; do
  python3 bot.py || echo "退出码 $?，5 秒后自动重启"
  sleep 5
done
