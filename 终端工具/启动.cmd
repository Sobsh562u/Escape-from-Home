@echo off
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo 没找到 Python。去 python.org 装一个，安装时记得勾选 "Add python.exe to PATH"。
  pause
  exit /b
)
python "逃家模组.py"
if errorlevel 1 pause
