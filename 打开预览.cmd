@echo off
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 goto use_py
python preview_server.py
goto finished
:use_py
where py >nul 2>nul
if errorlevel 1 goto missing_python
py -3 preview_server.py
goto finished
:missing_python
echo 未找到 Python 3。请安装 Python 3 后重新打开预览。
:finished
pause
