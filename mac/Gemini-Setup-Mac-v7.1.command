#!/bin/bash
# =============================================================================
#  Gemini in Chrome Enabler - macOS v7.1 (lcandy2 逻辑 + safe-seed + 永久覆盖国家)
#  真实版本检测 + safe-seed 一致性国家 + 永久覆盖国家 + glic 开关 + profile 资格字段
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Chrome 配置路径
CHROME_STATE=~/Library/Application\ Support/Google/Chrome/Local\ State
CHROME_PREFS=~/Library/Application\ Support/Google/Chrome/Default/Preferences

clear
echo ""
echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║     Gemini in Chrome Enabler - macOS v7.1                 ║${NC}"
echo -e "${MAGENTA}║   safe-seed + 永久覆盖国家 + glic 开关 + 启动参数          ║${NC}"
echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 步骤 1: 环境检测
# =============================================================================
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  [1/5] 环境检测                                             │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Chrome 安装检测
if [ -d "/Applications/Google Chrome.app" ]; then
    CHROME_VER=$(/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --version 2>/dev/null | awk '{print $3}' || echo "未知")
    echo -e "  ${GREEN}✅ Chrome 已安装: $CHROME_VER${NC}"
else
    echo -e "  ${RED}❌ 未检测到 Chrome，请先安装 Google Chrome${NC}"
    read -p "按 Enter 键退出... " -r
    exit 1
fi

# Local State 文件检测
if [ -f "$CHROME_STATE" ]; then
    echo -e "  ${GREEN}✅ Chrome 配置文件存在${NC}"
else
    echo -e "  ${RED}❌ Chrome 配置文件不存在，请先启动一次 Chrome${NC}"
    read -p "按 Enter 键退出... " -r
    exit 1
fi

echo ""
read -p "环境检测完成，按 Enter 键继续... " -r
echo ""

# =============================================================================
# 步骤 2: 关闭 Chrome
# =============================================================================
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  [2/5] 关闭 Chrome                                          │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

check_chrome() {
    pgrep -x "Google Chrome" > /dev/null 2>&1
}

if check_chrome; then
    echo -e "  ${YELLOW}⚠️  检测到 Chrome 正在运行${NC}"
    echo ""
    echo -e "  ${WHITE}请手动关闭 Chrome (Cmd+Q 或点击菜单 > 退出)${NC}"
    echo ""
    read -p "关闭后按 Enter 键继续... " -r
    
    if check_chrome; then
        echo -e "  ${YELLOW}尝试自动关闭 Chrome...${NC}"
        osascript -e 'quit app "Google Chrome"' 2>/dev/null
        sleep 2
        
        if check_chrome; then
            echo -e "  ${RED}❌ Chrome 仍在运行，请手动关闭后重新运行脚本${NC}"
            read -p "按 Enter 键退出... " -r
            exit 1
        fi
    fi
fi

echo -e "  ${GREEN}✅ Chrome 已关闭${NC}"
echo ""

# =============================================================================
# 步骤 3: 备份配置
# =============================================================================
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  [3/5] 备份配置文件                                         │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
cp "$CHROME_STATE" "$CHROME_STATE.backup.$BACKUP_TIME"
echo -e "  ${GREEN}✅ 已备份: Local State.backup.$BACKUP_TIME${NC}"
echo ""

# =============================================================================
# 步骤 4: v7.1 补丁 (safe-seed + 永久覆盖国家 + glic 开关 + 启动参数方案)
# =============================================================================
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  [4/5] 执行 v7.1 补丁 (safe-seed + 永久覆盖国家 + glic 开关)  │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# 使用 Python 执行补丁 (与 Windows v7.1 一致的逻辑)
GEMINI_CHROME_VERSION="$CHROME_VER" python3 << 'PYTHON_SCRIPT'
import json
import os
import shutil
from datetime import datetime

TARGET_COUNTRY = "us"
TARGET_LOCALE = "en-US"
FALLBACK_VERSION = "155.0.8059.85"

CHROME_STATE = os.path.expanduser("~/Library/Application Support/Google/Chrome/Local State")
CHROME_PREFS = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/Preferences")
CHROME_DATA = os.path.expanduser("~/Library/Application Support/Google/Chrome")

def iter_profile_dirs(base):
    names = []
    if os.path.isdir(os.path.join(base, "Default")):
        names.append("Default")
    if os.path.isdir(base):
        for name in sorted(os.listdir(base)):
            if name.startswith("Profile ") and os.path.isdir(os.path.join(base, name)):
                names.append(name)
    return names

def detect_version(data):
    env_ver = os.environ.get("GEMINI_CHROME_VERSION", "").strip()
    if env_ver and "." in env_ver:
        return env_ver, "chrome --version"
    vpcc = data.get("variations_permanent_consistency_country")
    if isinstance(vpcc, list) and vpcc and isinstance(vpcc[0], str) and "." in vpcc[0]:
        return vpcc[0], "Local State 现有值"
    return FALLBACK_VERSION, "内置兜底值"

def backup(path):
    if not os.path.exists(path):
        return None
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = path + ".bak." + ts
    shutil.copy2(path, bak)
    return bak

def patch_local_state():
    try:
        with open(CHROME_STATE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"  ❌ 失败: {e}")
        return False

    version, source = detect_version(data)
    print(f"  ➜ 检测到 Chrome 版本: {version} (来源: {source})")

    data["variations_country"] = TARGET_COUNTRY
    print(f'  ➜ variations_country = "{TARGET_COUNTRY}"')

    data["variations_permanent_consistency_country"] = [version, TARGET_COUNTRY]
    print(f'  ➜ variations_permanent_consistency_country = ["{version}", "{TARGET_COUNTRY}"]')

    # safe-seed 一致性国家 (Chrome 148+ 会话级判定)
    data["variations_safe_seed_permanent_consistency_country"] = TARGET_COUNTRY
    print(f'  ➜ variations_safe_seed_permanent_consistency_country = "{TARGET_COUNTRY}"')
    data["variations_safe_seed_session_consistency_country"] = TARGET_COUNTRY
    print(f'  ➜ variations_safe_seed_session_consistency_country = "{TARGET_COUNTRY}"')
    data["variations_safe_seed_locale"] = TARGET_LOCALE
    print(f'  ➜ variations_safe_seed_locale = "{TARGET_LOCALE}"')

    # v7.1 新增: 永久覆盖国家 (Chrome 150+ 关键字段)
    data["variations_permanent_overridden_country"] = TARGET_COUNTRY
    print(f'  ➜ variations_permanent_overridden_country = "{TARGET_COUNTRY}"')

    # v7.1 新增: browser 命名空间下的 variations_country (与根级是两个独立字段)
    if not isinstance(data.get("browser"), dict):
        data["browser"] = {}
    data["browser"]["variations_country"] = TARGET_COUNTRY
    print(f'  ➜ browser.variations_country = "{TARGET_COUNTRY}"')

    # v7.1 新增: 根级 glic 开关 (launcher_enabled 是最关键的总开关)
    if not isinstance(data.get("glic"), dict):
        data["glic"] = {}
    data["glic"]["launcher_enabled"] = True
    data["glic"]["multi_instance_enabled_by_tier"] = True
    print("  ➜ glic.launcher_enabled = true")
    print("  ➜ glic.multi_instance_enabled_by_tier = true")

    if not isinstance(data.get("intl"), dict):
        data["intl"] = {}
    data["intl"]["app_locale"] = TARGET_LOCALE
    print(f'  ➜ intl.app_locale = "{TARGET_LOCALE}"')

    count = [0]
    def fix_eligible(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "is_glic_eligible":
                    obj[k] = True
                    count[0] += 1
                else:
                    fix_eligible(v)
        elif isinstance(obj, list):
            for i in obj:
                fix_eligible(i)
    fix_eligible(data)
    print(f"  ➜ 已递归设置 {count[0]} 处 is_glic_eligible = true")

    profile_section = data.get("profile")
    if not isinstance(profile_section, dict):
        profile_section = {}
        data["profile"] = profile_section
    info_cache = profile_section.get("info_cache")
    if not isinstance(info_cache, dict):
        info_cache = {}
        profile_section["info_cache"] = info_cache
    profiles = iter_profile_dirs(CHROME_DATA)
    for name in profiles:
        entry = info_cache.get(name)
        if not isinstance(entry, dict):
            entry = {}
            info_cache[name] = entry
        entry["is_glic_eligible"] = True
    print(f"  ➜ 覆盖 {len(profiles)} 个 profile: {', '.join(profiles) if profiles else '(无)'}")

    with open(CHROME_STATE, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    print("  ✅ Local State 补丁完成")
    return True

def patch_preferences():
    try:
        bak = backup(CHROME_PREFS)
        if bak:
            print(f"  ➜ 已备份: {os.path.basename(bak)}")
        if not os.path.exists(CHROME_PREFS):
            print("  ⚠️  Default/Preferences 不存在, 跳过")
            return
        with open(CHROME_PREFS, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data.get("intl"), dict):
            data["intl"] = {}
        data["intl"]["selected_languages"] = "en-US,en"
        data["intl"]["accept_languages"] = "en-US,en"
        with open(CHROME_PREFS, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))
        print("  ✅ Preferences 语言修复完成")
    except Exception as e:
        print(f"  ⚠️  Preferences 修复失败: {e}")

def patch_profile_glic():
    """每个 Profile 的 Preferences 里写 glic 资格字段 (v7.1 新增)"""
    done = 0
    for name in iter_profile_dirs(CHROME_DATA):
        path = os.path.join(CHROME_DATA, name, "Preferences")
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data.get("glic"), dict):
                data["glic"] = {}
            data["glic"]["rollout_eligibility"] = True
            data["glic"]["previously_not_allowed"] = False
            data["glic"]["multi_instance_enabled_by_tier"] = True
            data["glic"].setdefault("completed_fre", 1)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
            print(f"  ➜ {name}: rollout_eligibility=true, previously_not_allowed=false")
            done += 1
        except Exception as e:
            print(f"  ⚠️  {name} 失败: {e}")
    print(f"  ✅ 已覆盖 {done} 个 profile 的 glic 资格字段")

patch_local_state()
patch_preferences()
patch_profile_glic()
PYTHON_SCRIPT

echo ""

# =============================================================================
# 步骤 4.5: macOS defaults 持久化设置
# =============================================================================
echo -e "${BLUE}  [4.5] 设置 macOS 系统级持久化...${NC}"
defaults write com.google.Chrome VariationsRestrictParameter -string "us" 2>/dev/null
echo -e "  ${GREEN}      ✅ VariationsRestrictParameter -> us${NC}"
defaults write com.google.Chrome AppleLanguages '("en-US")' 2>/dev/null
echo -e "  ${GREEN}      ✅ AppleLanguages -> en-US${NC}"
echo ""

# =============================================================================
# 步骤 5: 验证 & 完成
# =============================================================================
echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  [5/5] 验证结果                                             │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# 检查 variations_country
if grep -q '"variations_country":"us"' "$CHROME_STATE"; then
    echo -e "  ${GREEN}✅ variations_country: us${NC}"
else
    echo -e "  ${YELLOW}⚠️  variations_country: 验证失败${NC}"
fi

# 检查 safe-seed 一致性国家 (v7.1 新增)
if grep -q '"variations_safe_seed_session_consistency_country":"us"' "$CHROME_STATE"; then
    echo -e "  ${GREEN}✅ variations_safe_seed_session_consistency_country: us${NC}"
else
    echo -e "  ${YELLOW}⚠️  variations_safe_seed_session_consistency_country: 验证失败${NC}"
fi

# 检查永久覆盖国家 (v7.1 新增)
if grep -q '"variations_permanent_overridden_country":"us"' "$CHROME_STATE"; then
    echo -e "  ${GREEN}✅ variations_permanent_overridden_country: us${NC}"
else
    echo -e "  ${YELLOW}⚠️  variations_permanent_overridden_country: 验证失败${NC}"
fi

# 检查 is_glic_eligible
if grep -q '"is_glic_eligible":true' "$CHROME_STATE"; then
    echo -e "  ${GREEN}✅ is_glic_eligible: true${NC}"
else
    echo -e "  ${YELLOW}⚠️  is_glic_eligible: 未找到${NC}"
fi

echo ""

# =============================================================================
# 结果总结
# =============================================================================
echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                    ${GREEN}🎉 v7.1 补丁完成！${MAGENTA}                       ║${NC}"
echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  📋 下一步:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${WHITE}1. 开启 VPN 并连接到美国节点${NC}"
echo -e "  ${WHITE}2. 用以下命令启动 Chrome（每次启动都带美国区域参数）:${NC}"
echo -e "  ${WHITE}   open -n -a \"Google Chrome\" --args --variations-override-country=us \\${NC}"
echo -e "  ${WHITE}     --enable-features=Glic,GlicMultiWindow,GlicLauncher,GlicRolloutEligibility,GlicSidePanel${NC}"
echo -e "  ${WHITE}3. 登录美区 Google 账号${NC}"
echo -e "  ${WHITE}4. Chrome 会自动从服务器获取 Gemini 配置${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "是否现在启动 Chrome? (y/n)"
read -p "> " -r OPEN_CHROME
if [[ "$OPEN_CHROME" =~ ^[Yy]$ ]]; then
    open -n -a "Google Chrome" --args --variations-override-country=us \
        --enable-features=Glic,GlicMultiWindow,GlicLauncher,GlicRolloutEligibility,GlicSidePanel
    echo -e "  ${GREEN}Chrome 已启动（带美国区域参数）！${NC}"
fi

echo ""
echo -e "${GREEN}感谢使用 Gemini in Chrome Enabler v7.1!${NC}"
echo ""
read -p "按 Enter 键退出... " -r
