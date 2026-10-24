# -*- coding: utf-8 -*-
"""Chrome Gemini (GLIC) 解锁 - Windows v7.1

v7.0: safe-seed 会话国家修正 + 真实版本检测 + 自动备份 + 自检
v7.1: 集成社区 2026-10 最新方案 (LINUX DO / macrochen skill, Chrome 150+ 实测):
        - 根级 variations_permanent_overridden_country = "us"      (关键)
        - browser.variations_country = "us"                        (与根级是两个独立字段)
        - 根级 glic.launcher_enabled / glic.multi_instance_enabled_by_tier
        - 每个 Profile 的 Preferences: glic.rollout_eligibility /
          previously_not_allowed / multi_instance_enabled_by_tier / completed_fre
        - --launch: 补丁完成后以 --variations-override-country=us
          --enable-features=Glic,GlicMultiWindow,GlicLauncher,GlicRolloutEligibility,GlicSidePanel
          启动 Chrome (Chrome 每次启动会按 IP 重置 safe-seed 字段, 运行时覆盖最可靠)

仅使用 Python 标准库。
"""

import json
import os
import shutil
import subprocess
import sys
import time
import winreg
from datetime import datetime
from pathlib import Path

TARGET_COUNTRY = "us"
TARGET_LOCALE = "en-US"
# 仅在所有检测手段都失败时使用; Chrome 稳定版 2026-10 实际版本以本机为准
FALLBACK_VERSION = "155.0.8059.85"
# 启动参数: 运行时强制 variations 国家为 us, 并启用 Glic 相关特性
LAUNCH_FLAGS = [
    "--variations-override-country=us",
    "--enable-features=Glic,GlicMultiWindow,GlicLauncher,GlicRolloutEligibility,GlicSidePanel",
]


# -----------------------------------------------------------------------------
# 基础工具
# -----------------------------------------------------------------------------

def get_user_data_dir():
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    if not local_app_data:
        raise RuntimeError("未找到 LOCALAPPDATA 环境变量")
    return Path(local_app_data) / "Google" / "Chrome" / "User Data"


def iter_profile_dirs(user_data):
    """返回本机存在的 profile 目录名 (info_cache 的 key)"""
    names = []
    default_dir = user_data / "Default"
    if default_dir.is_dir():
        names.append("Default")
    for item in sorted(user_data.glob("Profile *")):
        if item.is_dir():
            names.append(item.name)
    return names


def detect_chrome_version(data, user_data):
    """按可靠性顺序检测 Chrome 真实版本号"""
    # 1. User Data/Last Version (Chrome 自己维护, 最可靠)
    try:
        text = (user_data / "Last Version").read_text(encoding="ascii", errors="ignore").strip()
        if text and "." in text:
            return text, "Last Version 文件"
    except OSError:
        pass

    # 2. 注册表卸载信息
    reg_paths = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome"),
    ]
    for hive, path in reg_paths:
        try:
            with winreg.OpenKey(hive, path) as key:
                value, _ = winreg.QueryValueEx(key, "DisplayVersion")
                value = str(value).strip()
                if value and "." in value:
                    return value, "注册表"
        except OSError:
            continue

    # 3. Local State 里已有的记录
    vpcc = data.get("variations_permanent_consistency_country")
    if isinstance(vpcc, list) and vpcc and isinstance(vpcc[0], str) and "." in vpcc[0]:
        return vpcc[0], "Local State 现有值"

    return FALLBACK_VERSION, "内置兜底值"


def backup_file(path):
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = path.with_name(path.name + ".bak." + ts)
    shutil.copy2(path, backup)
    return backup


def chrome_running():
    """检测 Chrome 是否仍在运行 (tasklist 输出按字节读取, 兼容各系统区域编码)"""
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq chrome.exe", "/NH"],
            capture_output=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    text = (result.stdout + result.stderr).decode("utf-8", "ignore")
    return "chrome.exe" in text.lower()


def kill_chrome_and_wait(timeout=20):
    """关闭 Chrome 并等待进程真正退出 (Local State 被占用时写入会失败)"""
    os.system("taskkill /F /IM chrome.exe /T >nul 2>&1")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not chrome_running():
            return True
        time.sleep(0.5)
    return not chrome_running()


def cleanup_registry():
    """清理 Chrome 策略 (企业策略可能强制关闭 Gemini)"""
    print("[3/7] 清理注册表策略...")
    path = r"SOFTWARE\Policies\Google\Chrome"
    deleted = 0
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_ALL_ACCESS) as key:
            while True:
                try:
                    name = winreg.EnumValue(key, 0)[0]
                    winreg.DeleteValue(key, name)
                    print(f"    - 已删除: {name}")
                    deleted += 1
                except OSError:
                    break
    except FileNotFoundError:
        pass
    except OSError as exc:
        print(f"    ! 跳过: {exc}")
    if not deleted:
        print("    - 无策略项需要清理")
    print("    OK 完成")


def ensure_dict(container, key):
    """取 container[key], 不存在或类型不对则建空 dict"""
    value = container.get(key)
    if not isinstance(value, dict):
        value = {}
        container[key] = value
    return value


# -----------------------------------------------------------------------------
# 核心补丁
# -----------------------------------------------------------------------------

def patch_local_state(path, user_data):
    print(f"[4/7] 补丁 Local State: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 1. 真实版本号
    version, source = detect_chrome_version(data, user_data)
    print(f"    - Chrome 版本: {version}  (来源: {source})")

    # 2. 常规 variations 国家 (v6.2 原有)
    data["variations_country"] = TARGET_COUNTRY
    print(f'    - variations_country = "{TARGET_COUNTRY}"')

    # 3. 版本 + 国家永久一致性 (v6.2 原有)
    data["variations_permanent_consistency_country"] = [version, TARGET_COUNTRY]
    print(f'    - variations_permanent_consistency_country = ["{version}", "{TARGET_COUNTRY}"]')

    # 4. safe-seed 一致性国家 (v7.0 新增, Chrome 148+ 的会话级判定)
    data["variations_safe_seed_permanent_consistency_country"] = TARGET_COUNTRY
    print(f'    - variations_safe_seed_permanent_consistency_country = "{TARGET_COUNTRY}"')
    data["variations_safe_seed_session_consistency_country"] = TARGET_COUNTRY
    print(f'    - variations_safe_seed_session_consistency_country = "{TARGET_COUNTRY}"')
    data["variations_safe_seed_locale"] = TARGET_LOCALE
    print(f'    - variations_safe_seed_locale = "{TARGET_LOCALE}"')

    # 5. 界面语言 (v6.2 原有)
    data["intl"] = ensure_dict(data, "intl")
    data["intl"]["app_locale"] = TARGET_LOCALE
    print(f'    - intl.app_locale = "{TARGET_LOCALE}"')

    # 6. 递归开启 is_glic_eligible (v6.2 原有)
    count = [0]

    def fix_eligible(obj):
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "is_glic_eligible":
                    obj[key] = True
                    count[0] += 1
                else:
                    fix_eligible(value)
        elif isinstance(obj, list):
            for item in obj:
                fix_eligible(item)

    fix_eligible(data)
    print(f"    - 递归设置 {count[0]} 处 is_glic_eligible = true")

    # 7. 为每个 profile 补建缺失的资格字段 (v7.0 新增)
    profile_section = ensure_dict(data, "profile")
    info_cache = ensure_dict(profile_section, "info_cache")
    profiles = iter_profile_dirs(user_data)
    created = 0
    for name in profiles:
        entry = info_cache.get(name)
        if not isinstance(entry, dict):
            entry = {}
            info_cache[name] = entry
            created += 1
        entry["is_glic_eligible"] = True
    print(f"    - 覆盖 {len(profiles)} 个 profile: {', '.join(profiles) if profiles else '(无)'}"
          f" (新建条目 {created} 个)")

    # 8. 永久覆盖国家 (v7.1 新增, Chrome 150+ 关键字段)
    data["variations_permanent_overridden_country"] = TARGET_COUNTRY
    print(f'    - variations_permanent_overridden_country = "{TARGET_COUNTRY}"')

    # 9. browser 命名空间下的 variations_country (v7.1 新增, 与根级是两个独立字段)
    browser = ensure_dict(data, "browser")
    browser["variations_country"] = TARGET_COUNTRY
    print(f'    - browser.variations_country = "{TARGET_COUNTRY}"')

    # 10. 根级 glic 开关 (v7.1 新增, launcher_enabled 是最关键的总开关)
    glic = ensure_dict(data, "glic")
    glic["launcher_enabled"] = True
    glic["multi_instance_enabled_by_tier"] = True
    print("    - glic.launcher_enabled = true")
    print("    - glic.multi_instance_enabled_by_tier = true")

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    print("    OK Local State 补丁完成")
    return version


def patch_preferences(path):
    """修复 Default/Preferences 的语言"""
    print(f"[5/7] 补丁 Default Preferences: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    data["intl"] = ensure_dict(data, "intl")
    data["intl"]["selected_languages"] = "en-US,en"
    data["intl"]["accept_languages"] = "en-US,en"
    print('    - selected_languages / accept_languages = "en-US,en"')

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    print("    OK Preferences 补丁完成")


def patch_profile_glic(user_data):
    """每个 Profile 的 Preferences 里写 glic 资格字段 (v7.1 新增)"""
    print("[6/7] 补丁各 Profile 的 glic 资格字段...")
    done = 0
    for name in iter_profile_dirs(user_data):
        path = user_data / name / "Preferences"
        if not path.exists():
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            glic = ensure_dict(data, "glic")
            glic["rollout_eligibility"] = True
            glic["previously_not_allowed"] = False
            glic["multi_instance_enabled_by_tier"] = True
            glic.setdefault("completed_fre", 1)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
            print(f"    - {name}: rollout_eligibility=true, previously_not_allowed=false,"
                  f" multi_instance_enabled_by_tier=true")
            done += 1
        except Exception as exc:
            print(f"    ! {name} 失败: {exc}")
    print(f"    OK 覆盖 {done} 个 profile")


# -----------------------------------------------------------------------------
# 自检
# -----------------------------------------------------------------------------

def verify(user_data):
    print("[7/7] 自检 (读回文件验证)...")
    path = user_data / "Local State"
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    results = []

    def record(ok, label, actual):
        results.append((ok, label, actual))

    record(data.get("variations_country") == TARGET_COUNTRY,
           "variations_country", data.get("variations_country"))
    vpcc = data.get("variations_permanent_consistency_country")
    record(isinstance(vpcc, list) and len(vpcc) == 2 and vpcc[1] == TARGET_COUNTRY,
           "variations_permanent_consistency_country", vpcc)
    record(data.get("variations_safe_seed_permanent_consistency_country") == TARGET_COUNTRY,
           "variations_safe_seed_permanent_consistency_country",
           data.get("variations_safe_seed_permanent_consistency_country"))
    record(data.get("variations_safe_seed_session_consistency_country") == TARGET_COUNTRY,
           "variations_safe_seed_session_consistency_country",
           data.get("variations_safe_seed_session_consistency_country"))
    record(data.get("variations_safe_seed_locale") == TARGET_LOCALE,
           "variations_safe_seed_locale", data.get("variations_safe_seed_locale"))
    record(isinstance(data.get("intl"), dict) and data["intl"].get("app_locale") == TARGET_LOCALE,
           "intl.app_locale", (data.get("intl") or {}).get("app_locale"))
    record(data.get("variations_permanent_overridden_country") == TARGET_COUNTRY,
           "variations_permanent_overridden_country",
           data.get("variations_permanent_overridden_country"))
    record((data.get("browser") or {}).get("variations_country") == TARGET_COUNTRY,
           "browser.variations_country", (data.get("browser") or {}).get("variations_country"))
    glic = data.get("glic") or {}
    record(glic.get("launcher_enabled") is True, "glic.launcher_enabled", glic.get("launcher_enabled"))
    record(glic.get("multi_instance_enabled_by_tier") is True,
           "glic.multi_instance_enabled_by_tier", glic.get("multi_instance_enabled_by_tier"))

    info_cache = (data.get("profile") or {}).get("info_cache") or {}
    bad = [name for name in iter_profile_dirs(user_data)
           if not (isinstance(info_cache.get(name), dict)
                   and info_cache[name].get("is_glic_eligible") is True)]
    record(not bad, "is_glic_eligible (所有 profile)",
           "全部为 true" if not bad else "异常: " + ", ".join(bad))

    glic_bad = []
    for name in iter_profile_dirs(user_data):
        pref_path = user_data / name / "Preferences"
        if not pref_path.exists():
            continue
        try:
            with open(pref_path, "r", encoding="utf-8") as f:
                prefs = json.load(f)
            pg = prefs.get("glic") or {}
            if not (pg.get("rollout_eligibility") is True
                    and pg.get("previously_not_allowed") is False
                    and pg.get("multi_instance_enabled_by_tier") is True):
                glic_bad.append(name)
        except Exception:
            glic_bad.append(name + "(读取失败)")
    record(not glic_bad, "Preferences glic 资格字段 (所有 profile)",
           "全部正常" if not glic_bad else "异常: " + ", ".join(glic_bad))

    all_ok = True
    for ok, label, actual in results:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            all_ok = False
        print(f"    [{mark}] {label} = {actual!r}")
    print("    => " + ("全部通过" if all_ok else "存在失败项, 请检查上方输出"))
    return all_ok


# -----------------------------------------------------------------------------
# 启动
# -----------------------------------------------------------------------------

def find_chrome_exe():
    candidates = [
        Path(os.environ.get("ProgramFiles", "")) / "Google" / "Chrome" / "Application" / "chrome.exe",
        Path(os.environ.get("ProgramFiles(x86)", "")) / "Google" / "Chrome" / "Application" / "chrome.exe",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "Application" / "chrome.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def launch_chrome_with_flags():
    exe = find_chrome_exe()
    if not exe:
        print("    ! 未找到 chrome.exe, 请手动启动 Chrome")
        return False
    print(f"    - 可执行文件: {exe}")
    print(f"    - 启动参数: {' '.join(LAUNCH_FLAGS)}")
    try:
        subprocess.Popen([str(exe), *LAUNCH_FLAGS], close_fds=True)
        print("    OK Chrome 已启动 (带美国区域覆盖参数)")
        return True
    except OSError as exc:
        print(f"    ! 启动失败: {exc}")
        return False


# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------

def main():
    launch_mode = "--launch" in sys.argv[1:]

    print("=" * 62)
    print("   Chrome Gemini (GLIC) 解锁 - Windows v7.1")
    if launch_mode:
        print("   补丁 + 以美国区域参数启动 Chrome")
    else:
        print("   safe-seed 修正 + 永久覆盖国家 + glic 开关 + 自动备份 + 自检")
    print("=" * 62)

    user_data = get_user_data_dir()
    local_state = user_data / "Local State"
    preferences = user_data / "Default" / "Preferences"
    print(f"\n用户数据目录: {user_data}")

    if not local_state.exists():
        print("\n[ERROR] Local State 不存在, 请先启动一次 Chrome 再运行本脚本。")
        pause()
        return 1

    # 1. 备份
    print("\n[1/7] 备份配置文件...")
    for target in (local_state, preferences):
        if target.exists():
            backup = backup_file(target)
            print(f"    - 已备份: {backup.name}")
    for name in iter_profile_dirs(user_data):
        target = user_data / name / "Preferences"
        if target.exists():
            backup = backup_file(target)
            print(f"    - 已备份: {backup.name}")
    print("    OK 完成")

    # 2. 关闭 Chrome
    print("\n[2/7] 关闭 Chrome...")
    if kill_chrome_and_wait():
        print("    OK Chrome 已完全退出")
    else:
        print("    ! 仍有 Chrome 进程残留, 补丁可能写入失败, 请手动结束后重试")

    # 3. 清理策略
    print()
    cleanup_registry()

    # 4. Local State 主补丁
    print()
    patch_local_state(local_state, user_data)

    # 5. Default Preferences 语言
    print()
    if preferences.exists():
        patch_preferences(preferences)
    else:
        print("[5/7] Default/Preferences 不存在, 跳过 (不影响 Local State 补丁)")

    # 6. 各 Profile glic 资格字段
    print()
    patch_profile_glic(user_data)

    # 7. 自检
    print()
    verify(user_data)

    # 启动 (--launch 模式)
    if launch_mode:
        print("\n[启动] 以美国区域参数启动 Chrome...")
        launch_chrome_with_flags()

    print("\n" + "=" * 62)
    if launch_mode:
        print("补丁完成, Chrome 已启动。如果图标没出现:")
        print("  1. 确认已连接美国 VPN (Gemini 服务本身必须走美国 IP)")
        print("  2. Google 账号归属地为美国 (myaccount.google.com 检查)")
        print("  3. chrome://flags 搜索 glic, 全部设为 Enabled 后重启")
    else:
        print("补丁完成! 接下来:")
        print("  1. 推荐用 Launch-Chrome-Gemini.bat 启动 (自动补丁+带美国参数启动)")
        print("    或给 Chrome 快捷方式的目标追加参数:")
        print('    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" '
              '--variations-override-country=us '
              '--enable-features=Glic,GlicMultiWindow,GlicLauncher,GlicRolloutEligibility,GlicSidePanel')
        print("  2. 先连接美国节点 VPN, 再启动 Chrome (顺序不能反)")
        print("  3. 登录美区 Google 账号 (账号归属地需为美国)")
        print("  4. 打开 chrome://settings/ai 检查 Gemini 开关是否出现")
        print("  5. 若图标仍未出现, 可在 chrome://flags 启用:")
        print("     #glic / #glic-side-panel")
        print("  6. Chrome 每次启动会按 IP 重置 safe-seed 字段, 失效后用美国 VPN 重跑即可")
    print("=" * 62)

    if not launch_mode:
        pause()
    return 0


def pause():
    """仅在交互式控制台暂停, 避免管道/自动化场景挂起"""
    if os.environ.get("GEMINI_ENABLER_NO_PAUSE") == "1":
        return
    if sys.stdout.isatty():
        os.system("pause")


if __name__ == "__main__":
    sys.exit(main())
