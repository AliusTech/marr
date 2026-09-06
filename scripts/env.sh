# scripts/env.sh —— 内核手工构建的公共环境(供其余脚本 source,不直接执行)
# 交叉工具链:优先 TOOLCHAIN_DIR 环境变量,其次默认 Bootlin 路径,最后系统 aarch64-linux-gnu-

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${REPO_ROOT}/kernel"
OUT_DIR="${REPO_ROOT}/out"

# 负载上限:默认 6 线程(8 核约 80%),可用 JOBS=n 覆盖;一律 nice 降优先级
JOBS="${JOBS:-6}"
NICE_CMD=(nice -n 10)

detect_toolchain() {
    if [[ -n "${CROSS_COMPILE:-}" ]]; then
        return 0
    fi
    local dir="${TOOLCHAIN_DIR:-$HOME/toolchains/aarch64--glibc--stable-2025.08-1}"
    if [[ -x "$dir/bin/aarch64-buildroot-linux-gnu-gcc" ]]; then
        export PATH="$dir/bin:$PATH"
        CROSS_COMPILE="aarch64-buildroot-linux-gnu-"
    elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        CROSS_COMPILE="aarch64-linux-gnu-"
    else
        echo "错误:未找到 aarch64 交叉工具链(Bootlin 目录缺失且系统无 aarch64-linux-gnu-gcc)。" >&2
        echo "     下载 Bootlin 工具链到 ~/toolchains/,或设置 TOOLCHAIN_DIR 指向其根目录。" >&2
        return 1
    fi
}
