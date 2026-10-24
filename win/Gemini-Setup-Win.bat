@echo off
setlocal DisableDelayedExpansion

rem Use UTF-8 so the Chinese status messages render correctly in cmd.exe.
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"

title Gemini in Chrome Enabler - Windows Setup v7.1

rem 让 Python 以 UTF-8 输出, 避免中文/表情在部分控制台编码下报错。
set "PYTHONUTF8=1"

echo ====================================================
echo       Gemini in Chrome Enabler - Windows Setup v7.1
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

REM 当前主脚本只使用 Python 标准库，不再强制联网安装未使用的 psutil。
echo [2/2] 正在启动主修复程序...
call %PYTHON_CMD% -u "%SCRIPT_DIR%enable_gemini_win.py"
if errorlevel 1 goto script_failed

echo.
echo ====================================================
echo [DONE] 操作已完成！
echo ====================================================
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
echo [ERROR] 主修复程序执行失败，错误码：%SCRIPT_EXIT_CODE%
echo 请保留上面的错误信息，以便定位具体问题。
pause
exit /b %SCRIPT_EXIT_CODE%
