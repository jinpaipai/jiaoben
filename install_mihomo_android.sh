
#!/data/data/com.termux/files/usr/bin/bash
# Mihomo Android 裸核安装及管理脚本
# Termux + Termux:Widget + KernelSU
# 安装位置：/data/mihomo

set -Eeuo pipefail

BASE="/data/mihomo"
API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
TASK_DIR="$HOME/.shortcuts/tasks"
MANAGER="$HOME/.local/bin/mihomo-manager"
ROOT_MANAGER="$BASE/manage.sh"
SERVICE="/data/adb/service.d/mihomo.sh"

TMP_DIR="$(mktemp -d "$HOME/mihomo-install.XXXXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

info() { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*"; }
fail() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

root() {
    su -c "/system/bin/sh '$ROOT_MANAGER' $*"
}

# ==========================================
# 1. 环境检查
# ==========================================

if [ ! -x /data/data/com.termux/files/usr/bin/bash ]; then
    fail "请使用 Termux 执行安装脚本"
fi

info "检查 Root 权限..."

ROOT_UID="$(su -c id -u 2>/dev/null || true)"
[ "$ROOT_UID" = "0" ] || fail "Root 权限不可用，请在 KernelSU 中授权 Termux"

info "安装必要依赖..."
pkg install -y curl jq gzip coreutils

for cmd in curl jq gzip mktemp; do
    command -v "$cmd" >/dev/null || fail "缺少依赖：$cmd"
done

mkdir -p "$TASK_DIR" "$HOME/.local/bin"

# ==========================================
# 2. CPU 架构识别
# ==========================================

ARCH="$(uname -m)"

case "$ARCH" in
    aarch64|arm64)
        FILE_KEY="android-arm64"
        ;;
    armv7l|armv8l)
        FILE_KEY="android-armv7"
        ;;
    x86_64)
        FILE_KEY="android-amd64"
        ;;
    i386|i686)
        FILE_KEY="android-386"
        ;;
    *)
        fail "不支持的 CPU 架构：$ARCH"
        ;;
esac

info "当前架构：$ARCH"
info "内核类型：$FILE_KEY"

# ==========================================
# 3. 创建 Root 管理脚本
# ==========================================

cat > "$TMP_DIR/manage.sh" <<'ROOT_SCRIPT'
#!/system/bin/sh

BASE="/data/mihomo"
BIN="$BASE/mihomo"
CONFIG="$BASE/config.yaml"
LOG="$BASE/logs/mihomo.log"
PIDFILE="$BASE/mihomo.pid"

mkdir -p "$BASE/logs"

running_pid() {
    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            if [ -r "/proc/$PID/cmdline" ] &&
               tr '\000' ' ' < "/proc/$PID/cmdline" |
               grep -q "$BIN"; then
                echo "$PID"
                return 0
            fi
        fi
    fi
    return 1
}

start_core() {
    if running_pid >/dev/null; then
        echo "[INFO] Mihomo 已在运行"
        return 0
    fi

    [ -x "$BIN" ] || {
        echo "[ERROR] Mihomo 内核不存在"
        return 1
    }

    [ -s "$CONFIG" ] || {
        echo "[ERROR] config.yaml 不存在"
        return 1
    }

    "$BIN" -d "$BASE" -f "$CONFIG" -t || return 1

    echo "[INFO] 正在启动 Mihomo..."

    "$BIN" -d "$BASE" -f "$CONFIG" \
        >> "$LOG" 2>&1 </dev/null &

    PID=$!
    echo "$PID" > "$PIDFILE"

    sleep 2

    if running_pid >/dev/null; then
        echo "[OK] Mihomo 启动成功，PID：$PID"
    else
        rm -f "$PIDFILE"
        echo "[ERROR] Mihomo 启动失败"
        tail -n 20 "$LOG"
        return 1
    fi
}

stop_core() {
    PID="$(running_pid || true)"

    if [ -z "$PID" ]; then
        rm -f "$PIDFILE"
        echo "[INFO] Mihomo 未运行"
        return 0
    fi

    echo "[INFO] 正在停止 Mihomo：$PID"
    kill "$PID" 2>/dev/null || true

    i=0
    while [ "$i" -lt 10 ]; do
        if ! kill -0 "$PID" 2>/dev/null; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
    fi

    rm -f "$PIDFILE"
    echo "[OK] Mihomo 已停止"
}

install_core() {
    SRC="$2"

    [ -s "$SRC" ] || {
        echo "[ERROR] 下载文件不存在"
        return 1
    }

    cp "$SRC" "$BASE/.mihomo.new" || return 1
    chmod 755 "$BASE/.mihomo.new"

    "$BASE/.mihomo.new" -v || {
        rm -f "$BASE/.mihomo.new"
        echo "[ERROR] 新内核无法执行"
        return 1
    }

    WAS_RUNNING=0
    if running_pid >/dev/null; then
        WAS_RUNNING=1
        stop_core
    fi

    if [ -f "$BIN" ]; then
        cp -p "$BIN" "$BASE/mihomo.bak" || return 1
    fi

    if ! mv -f "$BASE/.mihomo.new" "$BIN"; then
        echo "[ERROR] 替换内核失败"
        return 1
    fi

    chmod 755 "$BIN"
    echo "[OK] Mihomo 内核已安装"

    if [ "$WAS_RUNNING" -eq 1 ]; then
        if ! start_core; then
            echo "[WARN] 新内核启动失败，尝试回滚"
            if [ -f "$BASE/mihomo.bak" ]; then
                cp -p "$BASE/mihomo.bak" "$BIN"
                start_core
            fi
            return 1
        fi
    fi
}

install_config() {
    SRC="$2"

    [ -s "$SRC" ] || {
        echo "[ERROR] 配置文件为空"
        return 1
    }

    cp "$SRC" "$BASE/.config.new" || return 1
    chmod 600 "$BASE/.config.new"

    if ! "$BIN" -d "$BASE" \
        -f "$BASE/.config.new" -t; then
        rm -f "$BASE/.config.new"
        echo "[ERROR] 新配置检查失败，保留旧配置"
        return 1
    fi

    WAS_RUNNING=0
    if running_pid >/dev/null; then
        WAS_RUNNING=1
    fi

    if [ -f "$CONFIG" ]; then
        cp -p "$CONFIG" "$BASE/config.yaml.bak" || return 1
    fi

    mv -f "$BASE/.config.new" "$CONFIG"
    chmod 600 "$CONFIG"

    echo "[OK] 配置已更新"

    if [ "$WAS_RUNNING" -eq 1 ]; then
        stop_core
        if ! start_core; then
            echo "[WARN] 启动失败，尝试恢复旧配置"
            if [ -f "$BASE/config.yaml.bak" ]; then
                cp -p "$BASE/config.yaml.bak" "$CONFIG"
                start_core
            fi
            return 1
        fi
    fi
}

case "$1" in
    start)
        start_core
        ;;
    stop)
        stop_core
        ;;
    restart)
        stop_core
        start_core
        ;;
    status)
        if PID="$(running_pid)"; then
            echo "[OK] Mihomo 正在运行，PID：$PID"
        else
            echo "[INFO] Mihomo 未运行"
        fi
        if [ -x "$BIN" ]; then
            "$BIN" -v
        fi
        ;;
    install-core)
        install_core "$@"
        ;;
    install-config)
        install_config "$@"
        ;;
    test)
        "$BIN" -d "$BASE" -f "$CONFIG" -t
        ;;
    log)
        tail -n 80 "$LOG"
        ;;
    *)
        echo "用法：$0 {start|stop|restart|status|install-core|install-config|test|log}"
        exit 1
        ;;
esac
ROOT_SCRIPT

# ==========================================
# 4. 创建安装目录
# ==========================================

info "创建 /data/mihomo..."

su -c "mkdir -p '$BASE' '$BASE/logs' '$BASE/geo'"

su -c "cp '$TMP_DIR/manage.sh' '$ROOT_MANAGER'"

su -c "chmod 700 '$ROOT_MANAGER'"

# ==========================================
# 5. 创建 Termux 管理器
# ==========================================

cat > "$MANAGER" <<'MANAGER_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

set -Eeuo pipefail

BASE="/data/mihomo"
API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
ROOT_MANAGER="$BASE/manage.sh"

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

root() {
    su -c "/system/bin/sh '$ROOT_MANAGER' $*"
}

TMP_DIR="$(mktemp -d "$HOME/mihomo-task.XXXXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64) KEY="android-arm64" ;;
    armv7l|armv8l) KEY="android-armv7" ;;
    x86_64) KEY="android-amd64" ;;
    i386|i686) KEY="android-386" ;;
    *) fail "不支持的架构：$ARCH" ;;
esac

download_core() {
    info "正在获取 GitHub 最新版本..."

    curl -fsSL --retry 3 "$API" \
        -o "$TMP_DIR/release.json" ||
        fail "获取 GitHub Release 信息失败"

    TAG="$(jq -r '.tag_name // empty' "$TMP_DIR/release.json")"

    URL="$(jq -r --arg key "$KEY" '
        [.assets[]?.browser_download_url
         | select(contains($key) and endswith(".gz"))]
        | first // empty
    ' "$TMP_DIR/release.json")"

    [ -n "$URL" ] || fail "未找到匹配的 Android 内核"

    info "最新版本：$TAG"
    info "下载地址：$URL"

    curl -fL --retry 3 --connect-timeout 15 \
        -o "$TMP_DIR/core.gz" "$URL" ||
        fail "内核下载失败"

    gzip -t "$TMP_DIR/core.gz" ||
        fail "压缩文件校验失败"

    gzip -dc "$TMP_DIR/core.gz" > "$TMP_DIR/mihomo"

    [ -s "$TMP_DIR/mihomo" ] ||
        fail "解压后的内核为空"

    root install-core "$TMP_DIR/mihomo"
}

update_config() {
    info "读取订阅地址..."

    URL="$(su -c "cat '$BASE/subscription.url'" 2>/dev/null || true)"

    [ -n "$URL" ] || fail "未设置订阅地址"

    info "开始下载订阅..."

    curl -fL --retry 3 --connect-timeout 15 \
        --max-time 120 \
        -o "$TMP_DIR/config.yaml" "$URL" ||
        fail "订阅下载失败，保留旧配置"

    [ -s "$TMP_DIR/config.yaml" ] ||
        fail "订阅文件为空"

    root install-config "$TMP_DIR/config.yaml"
}

case "${1:-}" in
    start)
        root start
        ;;
    stop)
        root stop
        ;;
    restart)
        root restart
        ;;
    status)
        root status
        ;;
    log)
        root log
        ;;
    test)
        root test
        ;;
    update-core)
        download_core
        ;;
    update-config)
        update_config
        ;;
    *)
        echo "Mihomo Android Manager"
        echo "可用命令："
        echo "  start"
        echo "  stop"
        echo "  restart"
        echo "  status"
        echo "  log"
        echo "  test"
        echo "  update-core"
        echo "  update-config"
        exit 1
        ;;
esac
MANAGER_SCRIPT

chmod 700 "$MANAGER"

# ==========================================
# 6. 下载并安装最新内核
# ==========================================

info "下载并安装 Mihomo 内核..."
"$MANAGER" update-core

# ==========================================
# 7. 配置订阅地址
# ==========================================

echo
read -r -p "请输入 Mihomo/Clash YAML 订阅链接（回车保留旧订阅）： " SUB_LINK

if [ -n "$SUB_LINK" ]; then
    case "$SUB_LINK" in
        https://*)
            printf '%s\n' "$SUB_LINK" > "$TMP_DIR/subscription.url"
            su -c "cp '$TMP_DIR/subscription.url' '$BASE/subscription.url' && chmod 600 '$BASE/subscription.url'"
            info "订阅地址已保存"
            ;;
        *)
            warn "订阅地址必须以 https:// 开头，已跳过"
            ;;
    esac
fi

if su -c "test -s '$BASE/subscription.url'"; then
    info "尝试下载订阅配置..."
    if ! "$MANAGER" update-config; then
        warn "订阅更新失败，请稍后通过快捷任务重试"
    fi
else
    warn "未配置订阅，暂时无法启动 Mihomo"
fi

# ==========================================
# 8. 生成 Termux:Widget 快捷任务
# ==========================================

info "生成桌面快捷任务..."

create_task() {
    NAME="$1"
    ACTION="$2"

    cat > "$TASK_DIR/$NAME.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
"$MANAGER" "$ACTION"
echo
read -r -p "按回车退出..."
EOF

    chmod 700 "$TASK_DIR/$NAME.sh"
}

create_task "01_start_mihomo" "start"
create_task "02_stop_mihomo" "stop"
create_task "03_restart_mihomo" "restart"
create_task "04_update_config" "update-config"
create_task "05_update_core" "update-core"
create_task "06_check_status" "status"
create_task "07_view_log" "log"

# ==========================================
# 9. 创建 KernelSU 开机启动脚本
# ==========================================

info "配置 KernelSU 开机自启..."

cat > "$TMP_DIR/mihomo-service.sh" <<'SERVICE_SCRIPT'
#!/system/bin/sh

BASE="/data/mihomo"
MANAGER="$BASE/manage.sh"

# 等待系统基本启动完成
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] &&
      [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
done

# 再等待网络服务初始化
sleep 10

if [ -f "$BASE/config.yaml" ] &&
   [ -x "$BASE/mihomo" ]; then
    /system/bin/sh "$MANAGER" start \
        >> "$BASE/logs/service.log" 2>&1
fi
SERVICE_SCRIPT

su -c "mkdir -p /data/adb/service.d"
su -c "cp '$TMP_DIR/mihomo-service.sh' '$SERVICE'"
su -c "chmod 700 '$SERVICE'"

# ==========================================
# 10. 最终检查
# ==========================================

echo
echo "========================================"
echo "     Mihomo Android 安装完成"
echo "========================================"

root status

echo
echo "内核目录：$BASE"
echo "快捷任务：$TASK_DIR"
echo "管理程序：$MANAGER"
echo "开机脚本：$SERVICE"

echo
echo "Termux 管理命令："
echo "  mihomo-manager start"
echo "  mihomo-manager stop"
echo "  mihomo-manager restart"
echo "  mihomo-manager status"
echo "  mihomo-manager update-config"
echo "  mihomo-manager update-core"

echo
echo "请在 Termux:Widget 中添加任务快捷方式。"
echo "安装完成。"
