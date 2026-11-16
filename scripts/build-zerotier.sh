#!/usr/bin/env bash
# =============================================================================
# ZeroTier OpenWrt 云编译脚本（供 GitHub Actions 调用）
#
# 用法:
#   build-zerotier.sh <target> <subtarget> <openwrt版本|snapshot>
#
# 示例:
#   build-zerotier.sh ramips mt7621 23.05.5      # 编译稳定版 -> 产出 .ipk
#   build-zerotier.sh ramips mt7621 snapshot     # 编译快照版 -> 产出 .apk
#   build-zerotier.sh mediatek filogic 23.05.5
#
# 产物统一输出到当前目录下的 out/ 文件夹
# =============================================================================
set -euo pipefail

TARGET="${1:?缺少 target，例如 ramips}"
SUBTARGET="${2:?缺少 subtarget，例如 mt7621}"
BRANCH="${3:?缺少 OpenWrt 版本号或 snapshot}"
PKG="zerotier"

if [ "${BRANCH}" = "snapshot" ]; then
  BASE="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${SUBTARGET}"
else
  BASE="https://downloads.openwrt.org/releases/${BRANCH}/targets/${TARGET}/${SUBTARGET}"
fi

echo "=========================================================="
echo " Target      : ${TARGET}/${SUBTARGET}"
echo " OpenWrt     : ${BRANCH}"
echo " SDK Base URL: ${BASE}"
echo "=========================================================="

# 1. 从 sha256sums 解析 SDK 文件名（兼容不同 gcc 版本命名）
echo ">>> [1/6] 获取 SDK 文件名..."
wget -q "${BASE}/sha256sums" -O sha256sums
SDK_FILE="$(grep 'openwrt-sdk' sha256sums | awk '{print $2}' | sed 's/^\*//' | head -n1)"
if [ -z "${SDK_FILE}" ]; then
  echo "ERROR: 未能在 ${BASE} 找到 openwrt-sdk 文件，请检查 target/subtarget/版本号" >&2
  exit 1
fi
echo "SDK 文件: ${SDK_FILE}"

# 2. 下载并解压 SDK
echo ">>> [2/6] 下载并解压 SDK..."
wget -q "${BASE}/${SDK_FILE}" -O sdk.tar.xz
tar -xf sdk.tar.xz
SDK_DIR="${SDK_FILE%.tar.xz}"
cd "${SDK_DIR}"

# 3. 更新 feeds 并安装 zerotier
echo ">>> [3/6] 更新 feeds..."
./scripts/feeds update -a
./scripts/feeds install "${PKG}"

# 4. 生成默认配置
echo ">>> [4/6] 生成配置..."
make defconfig

# 5. 编译（先并行，失败时单线程重跑输出完整日志）
echo ">>> [5/6] 开始编译 ${PKG} ..."
if ! make package/"${PKG}"/compile -j"$(nproc)" V=sc; then
  echo "并行编译失败，使用单线程重跑以输出完整错误日志..."
  make package/"${PKG}"/compile -j1 V=s
fi

# 6. 收集产物（ipk 或 apk）
echo ">>> [6/6] 收集编译产物..."
mkdir -p ../out
find bin/packages \( -name "${PKG}*.ipk" -o -name "${PKG}*.apk" \) -exec cp -v {} ../out/ \;

echo "=========================================================="
echo " 编译完成，产物列表:"
ls -lh ../out/
echo "=========================================================="
