#!/usr/bin/env bash
# 打包启动载荷:Image + rockchip dtbs + 模块 → out/kernel/
# 供 bring-up 阶段 TF 卡/ums 手工部署使用;Yocto 就绪后由 wic 整卡镜像取代
set -euo pipefail
source "$(dirname "$0")/env.sh"
detect_toolchain

cd "$KERNEL_DIR"
[[ -f arch/arm64/boot/Image ]] || {
    echo "错误:未发现 Image,先运行 scripts/kernel-build.sh" >&2
    exit 1
}

STAGE="$OUT_DIR/kernel"
rm -rf "$STAGE"
mkdir -p "$STAGE/dtbs"

cp arch/arm64/boot/Image "$STAGE/"
cp arch/arm64/boot/dts/rockchip/*.dtb "$STAGE/dtbs/"
KREL="$(make -s ARCH=arm64 kernelrelease)"

make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
    INSTALL_MOD_PATH="$STAGE/staging" modules_install >/dev/null
# staging 里的 build/source 是指向内核树的绝对软链,打包前去掉
rm -f "$STAGE/staging/lib/modules/$KREL/build" "$STAGE/staging/lib/modules/$KREL/source"
tar -C "$STAGE/staging" -cJf "$STAGE/modules.tar.xz" "lib"
rm -rf "$STAGE/staging"

echo "打包完成 → $STAGE"
du -sh "$STAGE" "$STAGE"/* | sed 's|'"$STAGE"'|.|'
echo "内核版本:$KREL"
