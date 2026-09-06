#!/usr/bin/env bash
# 编译内核:Image + dtbs + modules
# 限载运行:默认 -j6 + nice -n 10(可 JOBS=n 覆盖)
set -euo pipefail
source "$(dirname "$0")/env.sh"
detect_toolchain

cd "$KERNEL_DIR"
[[ -f .config ]] || {
    echo "错误:无 .config,先运行 scripts/kernel-config.sh" >&2
    exit 1
}

echo "编译开始:CROSS_COMPILE=$CROSS_COMPILE JOBS=$JOBS"
"${NICE_CMD[@]}" make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image dtbs modules
echo "编译完成:$(ls -la arch/arm64/boot/Image | awk '{print $5}') 字节 Image @ arch/arm64/boot/Image"
