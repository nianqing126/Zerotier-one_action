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

# ---------------------------------------------------------------------------
# 0. 环境自检：修复 GNU coreutils
#
# 新版 Ubuntu（25.10+ / 部分 runner 镜像）默认使用 uutils（Rust 版）coreutils，
# 其 install --version 输出中没有 "GNU"，会让 OpenWrt SDK 的 prereq 检查误报：
#   Build dependency: Please install GNU 'install'
# 这里检测并自动指向真正的 GNU install（提供 ginstall 兜底，SDK 会自动回退使用）。
# ---------------------------------------------------------------------------
ensure_gnu_coreutils() {
  if install --version 2>/dev/null | grep -q GNU; then
    echo ">>> [0/6] GNU coreutils 检查通过: $(install --version | head -n1)"
    return 0
  fi

  echo ">>> [0/6] 检测到当前 install 不是 GNU coreutils，尝试自动修复..."
  echo "    当前 install: $(command -v install || echo 未找到)"
  install --version 2>&1 | head -n3 || true

  SUDO=""
  [ "$(id -u)" -ne 0 ] && SUDO="sudo"

  # 优先用包管理器装回 GNU coreutils
  ${SUDO} apt-get install -y --reinstall coreutils >/dev/null 2>&1 || \
    ${SUDO} apt-get install -y coreutils >/dev/null 2>&1 || true

  # 找到 GNU install 的真实路径（uutils 环境下的 GNU 二进制通常仍保留）
  GNU_INSTALL=""
  for candidate in /usr/bin/install /bin/install /usr/lib/coreutils/install /usr/libexec/coreutils/install; do
    if [ -x "${candidate}" ] && "${candidate}" --version 2>/dev/null | grep -q GNU; then
      GNU_INSTALL="${candidate}"
      break
    fi
  done

  if [ -z "${GNU_INSTALL}" ]; then
    echo "ERROR: 未找到 GNU install，请手动安装 GNU coreutils 后重试" >&2
    return 1
  fi

  # 以 ginstall 形式暴露给 SDK（OpenWrt prereq 会回退检查 ginstall）
  ${SUDO} ln -sf "${GNU_INSTALL}" /usr/local/bin/ginstall
  # 若 install 本身仍是非 GNU，则用 GNU 版本在 PATH 更高优先级的目录中覆盖
  if ! install --version 2>/dev/null | grep -q GNU; then
    ${SUDO} ln -sf "${GNU_INSTALL}" /usr/local/bin/install
  fi

  if install --version 2>/dev/null | grep -q GNU || ginstall --version 2>/dev/null | grep -q GNU; then
    echo ">>> [0/6] 已修复: 使用 ${GNU_INSTALL}"
  else
    echo "ERROR: GNU install 修复失败" >&2
    return 1
  fi
}

ensure_gnu_coreutils

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

# 2. 下载并解压 SDK（稳定版为 .tar.xz，snapshot 为 .tar.zst）
echo ">>> [2/6] 下载并解压 SDK..."
wget -q "${BASE}/${SDK_FILE}" -O sdk_archive
case "${SDK_FILE}" in
  *.tar.zst)
    echo "检测到 zstd 压缩包，使用 zstd 解压..."
    command -v unzstd >/dev/null 2>&1 || { echo "ERROR: 缺少 zstd，请在依赖安装步骤中安装 zstd" >&2; exit 1; }
    tar --use-compress-program=unzstd -xf sdk_archive
    SDK_DIR="${SDK_FILE%.tar.zst}"
    ;;
  *.tar.xz)
    tar -xf sdk_archive
    SDK_DIR="${SDK_FILE%.tar.xz}"
    ;;
  *)
    tar -xf sdk_archive
    SDK_DIR="${SDK_FILE%.tar.*}"
    ;;
esac

# 兜底：若按文件名推断的目录不存在，则自动查找真正的 SDK 目录
if [ ! -d "${SDK_DIR}" ]; then
  SDK_DIR="$(find . -maxdepth 2 -type f -name 'rules.mk' 2>/dev/null | head -n1 | xargs -r dirname)"
fi
if [ ! -d "${SDK_DIR}" ] || [ ! -x "${SDK_DIR}/scripts/feeds" ]; then
  echo "ERROR: 解压后未找到 SDK 目录，当前目录内容:" >&2
  ls -la >&2
  exit 1
fi
echo "SDK 目录: ${SDK_DIR}"
cd "${SDK_DIR}"

# 3. 更新 feeds 并安装软件包
#    zerotier 主程序来自 packages feed；
#    LuCI 界面与中文语言包使用本仓库内嵌的 packages/luci-app-zerotier
PACKAGES=(
  "zerotier"
  "luci-app-zerotier"
  "luci-i18n-zerotier-zh-cn"
)

echo ">>> [3/6] 更新 feeds 并安装依赖 ..."
./scripts/feeds update -a
# luci-base 用于构建语言包所需的 po2lmo 主机工具
./scripts/feeds install zerotier luci-base

# 内嵌 LuCI 应用到 SDK 的 package 目录
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 适配版 Makefile：用绝对路径引用 luci.mk，脱离 feeds/luci 目录也能编译
write_luci_makefile() {
  cat > "$1/Makefile" <<'MK'
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2022 ImmortalWrt.org
# 内嵌版：源自 immortalwrt/luci applications/luci-app-zerotier
include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI for Zerotier
LUCI_DEPENDS:=+zerotier

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
MK
}

# 兜底 1：从 jsDelivr CDN 直接拉取上游 immortalwrt/luci 中的该应用（无需 git）
fetch_luci_from_cdn() {
  local dest="$1"
  local base="https://cdn.jsdelivr.net/gh/immortalwrt/luci@master/applications/luci-app-zerotier"
  local files=(
    "htdocs/luci-static/resources/view/zerotier/config.js"
    "htdocs/luci-static/resources/view/zerotier/interface.js"
    "po/zh_Hans/zerotier.po"
    "po/zh_Hant/zerotier.po"
    "po/templates/zerotier.pot"
    "root/etc/uci-defaults/40_luci-zerotier"
    "root/usr/share/luci/menu.d/luci-app-zerotier.json"
    "root/usr/share/rpcd/acl.d/luci-app-zerotier.json"
  )
  mkdir -p "${dest}"
  local f
  for f in "${files[@]}"; do
    mkdir -p "${dest}/$(dirname "${f}")"
    curl -fsSL --retry 3 --max-time 60 "${base}/${f}" -o "${dest}/${f}" 2>/dev/null || {
      echo "  [warn] CDN 下载失败: ${f}" >&2
      rm -f "${dest}/${f}"
    }
  done
  [ -s "${dest}/htdocs/luci-static/resources/view/zerotier/config.js" ]
}

# 在仓库内查找 luci-app-zerotier（兼容 packages/ 下、根目录、多套一层等放置方式）
LOCAL_LUCI="$(find "${REPO_ROOT}" -maxdepth 3 -type d -name luci-app-zerotier \
                -not -path '*/.git/*' 2>/dev/null | head -n1)"

if [ -z "${LOCAL_LUCI}" ]; then
  echo ">>> [提示] 仓库内未找到 packages/luci-app-zerotier，改为从上游获取..."
  echo "     仓库根目录内容（用于排查是否漏提交目录）:"
  ls -la "${REPO_ROOT}" >&2 || true
  TMPD="$(mktemp -d)"
  if fetch_luci_from_cdn "${TMPD}/app"; then
    LOCAL_LUCI="${TMPD}/app"
    echo ">>> 已从 jsDelivr 获取 luci-app-zerotier"
  elif git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/immortalwrt/luci.git "${TMPD}/luci" >/dev/null 2>&1 \
     && ( cd "${TMPD}/luci" && git sparse-checkout set applications/luci-app-zerotier >/dev/null 2>&1 ) \
     && [ -d "${TMPD}/luci/applications/luci-app-zerotier" ]; then
    LOCAL_LUCI="${TMPD}/luci/applications/luci-app-zerotier"
    echo ">>> 已从 GitHub 获取 luci-app-zerotier"
  else
    rm -rf "${TMPD}"
    echo "ERROR: 无法获取 luci-app-zerotier，编译中止" >&2
    echo "       本地执行以下命令把目录提交进仓库：" >&2
    echo "         git add -f packages/luci-app-zerotier" >&2
    echo "         git commit -m 'feat: add luci-app-zerotier' && git push" >&2
    exit 1
  fi
  echo "     （建议把该目录提交进仓库，避免每次编译依赖网络）"
else
  echo ">>> 注入内嵌 LuCI 应用: ${LOCAL_LUCI}"
fi

rm -rf package/luci-app-zerotier
cp -r "${LOCAL_LUCI}" package/luci-app-zerotier

# 校正 Makefile：
# 1) 上游原版用 ../../luci.mk，复制到 SDK 的 package/ 下会找不到
# 2) 末尾必须保留 "# call BuildPackage" 注释，否则 SDK 的包扫描（grep 该关键字）会跳过整个目录
# 3) 没有 PKG_VERSION 时版本号会变成 unknown
if ! grep -q 'feeds/luci/luci.mk' package/luci-app-zerotier/Makefile 2>/dev/null \
   || ! grep -q 'call BuildPackage' package/luci-app-zerotier/Makefile 2>/dev/null \
   || ! grep -q 'PKG_VERSION' package/luci-app-zerotier/Makefile 2>/dev/null; then
  echo ">>> 校正 luci-app-zerotier/Makefile"
  write_luci_makefile package/luci-app-zerotier
fi

# 4. 生成配置（显式启用三个包，defconfig 会自动补齐依赖）
echo ">>> [4/6] 生成配置..."
for p in "${PACKAGES[@]}"; do
  grep -q "^CONFIG_PACKAGE_${p}=" .config 2>/dev/null || echo "CONFIG_PACKAGE_${p}=m" >> .config
done
make defconfig

for p in "${PACKAGES[@]}"; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=" .config; then
    echo "WARNING: ${p} 未能在配置中启用（可能是依赖缺失或被上游移除）" >&2
  fi
done

# 5. 编译（先并行，失败时单线程重跑输出完整日志）
echo ">>> [5/6] 开始编译: ${PACKAGES[*]} ..."

# 语言包需要 po2lmo 主机工具（由 luci-base 的 host 部分提供，装在 hostpkg 或 host 目录）
if [ ! -x staging_dir/hostpkg/bin/po2lmo ] && [ ! -x staging_dir/host/bin/po2lmo ]; then
  LUCI_BASE_DIR="$(find package -maxdepth 3 -type d -name luci-base 2>/dev/null | head -n1)"
  if [ -n "${LUCI_BASE_DIR}" ]; then
    echo ">>> 构建 po2lmo 主机工具: ${LUCI_BASE_DIR}/host/compile"
    make "${LUCI_BASE_DIR}/host/compile" -j"$(nproc)" >/tmp/po2lmo.log 2>&1 || \
      echo "WARNING: po2lmo 构建失败，语言包可能会缺失（详见 /tmp/po2lmo.log）" >&2
  fi
fi

BUILD_TARGETS=()
for name in "zerotier" "luci-app-zerotier"; do
  dir="$(find package -maxdepth 3 -type d -name "${name}" 2>/dev/null | head -n1)"
  if [ -n "${dir}" ]; then
    BUILD_TARGETS+=("${dir}/compile")
  else
    echo "WARNING: 未找到软件包目录 ${name}" >&2
  fi
done
if [ ${#BUILD_TARGETS[@]} -eq 0 ]; then
  echo "ERROR: 没有可编译的目标" >&2
  exit 1
fi

run_build() {
  local jobs="$1" verbose="$2"
  make "${BUILD_TARGETS[@]}" -j"${jobs}" V="${verbose}" 2>&1 | tee /tmp/openwrt-build.log
  return "${PIPESTATUS[0]}"
}

if ! run_build "$(nproc)" sc; then
  # 特殊处理：SDK prereq 对 GNU install 的误判（uutils coreutils 环境）
  if grep -q "Prerequisite check failed" /tmp/openwrt-build.log; then
    echo ">>> 检测到 prereq 检查误判，创建 stamp 跳过检查后重试..."
    mkdir -p staging_dir/host
    touch staging_dir/host/.prereq-build
    run_build "$(nproc)" sc || {
      echo "并行编译失败，使用单线程重跑以输出完整错误日志..."
      run_build 1 s
    }
  else
    echo "并行编译失败，使用单线程重跑以输出完整错误日志..."
    run_build 1 s
  fi
fi

# 6. 收集产物（ipk 或 apk）
echo ">>> [6/6] 收集编译产物..."
mkdir -p ../out
# ipk 文件名用下划线（zerotier_1.x-r1_mipsel_24kc.ipk），apk 用短横线
# （zerotier-1.x-r1.apk），因此按名称前缀匹配，不限定分隔符与后缀
find bin/packages -type f \( \
    -name "zerotier*" -o \
    -name "luci-app-zerotier*" -o \
    -name "luci-i18n-zerotier*" \
  \) -exec cp -v {} ../out/ \;

if [ -z "$(ls -A ../out 2>/dev/null)" ]; then
  echo "ERROR: 未收集到任何安装包，请检查编译日志" >&2
  exit 1
fi

# 统一加芯片前缀：apk 的文件名本身不含架构，不同架构会重名并互相覆盖；
# ipk 中 mt7621 / mt7620 同为 mipsel_24kc，同样会重名。
# 例: mt7621-zerotier_1.12.2-2_mipsel_24kc.ipk / mt7981-zerotier-1.16.2-r1.apk
# （opkg / apk 安装时只看包内元数据，不依赖文件名，改名不影响安装）
TAG="$(printf '%s' "${SUBTARGET}" | tr '[:upper:]' '[:lower:]')"
shopt -s nullglob
for f in ../out/*.ipk ../out/*.apk; do
  base="$(basename "${f}")"
  case "${base}" in
    "${TAG}-"*) continue ;;
  esac
  mv "${f}" "../out/${TAG}-${base}"
done
shopt -u nullglob

echo "=========================================================="
echo " 编译完成，产物列表:"
ls -lh ../out/
echo "=========================================================="
