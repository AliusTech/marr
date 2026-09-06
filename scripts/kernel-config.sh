#!/usr/bin/env bash
# 配置内核:arm64 defconfig + PREEMPT_RT(bringup 既定决策)
# 幂等:重复执行回到同一配置状态
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "$KERNEL_DIR"
make ARCH=arm64 defconfig

# 6.12+ 抢占模型是 choice:切到 PREEMPT_RT 需关掉其余选项并开 EXPERT(否则不可见)
./scripts/config -e EXPERT \
    -d PREEMPT -d PREEMPT_NONE -d PREEMPT_VOLUNTARY \
    -e PREEMPT_RT
make ARCH=arm64 olddefconfig

grep -q '^CONFIG_PREEMPT_RT=y' .config || {
    echo "错误:PREEMPT_RT 未能启用,检查依赖" >&2
    exit 1
}
echo "配置完成:arm64 defconfig + PREEMPT_RT=y"
