@echo off
setlocal DisableDelayedExpansion

rem Use UTF-8 so the Chinese status messages render correctly in cmd.exe.
chcp 65001 >nul

rem 让 Python 以 UTF-8 输出, 避免中文/表情在部分控制台编码下报错。
set "PYTHONUTF8=1"

set "SCRIPT_DIR=%~dp0"

title Gemini in Chrome Enabler - Launch with US Region

echo ====================================================
echo   Gemini in Chrome Enabler - v7.1 带美国参数启动
echo   流程: 关闭 Chrome - 打补丁 - 以美国区域参数启动
echo ====================================================

REM 1. 检查主脚本
if not exist "%SCRIPT_DIR%enable_gemini_win.py" (
    echo [ERROR] 找不到主脚本："%SCRIPT_DIR%enable_gemini_win.py"
    pause
    exit /b 1
)

REM 2. 选择可用的 Python。优先使用 Python Launcher，避免命中 Microsoft Store 别名。
set "PYTHON_CMD=py -3"
call %PYTHON_CMD% --version >nul 2>&1
if not errorlevel 1 goto python_ready

set "PYTHON_CMD=python"
call %PYTHON_CMD% --version >nul 2>&1
if errorlevel 1 goto python_missing

:python_ready
echo [1/2] Python 已就绪：
call %PYTHON_CMD% --version

echo [2/2] 正在打补丁并以美国区域参数启动 Chrome...
call %PYTHON_CMD% -u "%SCRIPT_DIR%enable_gemini_win.py" --launch
if errorlevel 1 goto script_failed

echo.
echo ====================================================
echo [DONE] Chrome 已启动！
echo ====================================================
echo.
echo 如果右上角没有出现 Gemini 图标，请检查：
echo   1. 是否已连接美国 VPN（Gemini 服务必须走美国 IP）
echo   2. Google 账号归属地是否为美国
echo      （访问 myaccount.google.com 查看，非美国可申请修改）
echo   3. chrome://flags 搜索 glic，全部设为 Enabled 后重启
echo   4. 账号需满 18 岁，无痕/访客模式下不显示
echo.
pause
exit /b 0

:python_missing
echo [ERROR] 未检测到 Python 3，请先从 https://www.python.org/ 安装 Python。
echo 请确保安装时勾选 "Add Python to PATH"，或安装 Python Launcher。
pause
exit /b 1

:script_failed
set "SCRIPT_EXIT_CODE=%ERRORLEVEL%"
echo.
echo [ERROR] 执行失败，错误码：%SCRIPT_EXIT_CODE%
echo 请保留上面的错误信息，以便定位具体问题。
pause
exit /b %SCRIPT_EXIT_CODE%
