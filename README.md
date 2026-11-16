# ZeroTier OpenWrt 云编译项目

基于 **GitHub Actions** 的 ZeroTier 在线编译项目，无需本地环境，一键云端编译并自动发布到 Release。

## 支持架构

| 芯片 | OpenWrt Target | 架构 | 代表机型 | Workflow 文件 |
|---|---|---|---|---|
| **MT7621A** | `ramips/mt7621` | mipsel_24kc | 小米 3G/4A、Newifi D2、红米 AC2100、K2P | `build-mt7621.yml` |
| **MT7620** | `ramips/mt7620` | mipsel_24kc | 小米 mini、斐讯 K2、极路由 | `build-mt7620.yml` |
| **MT7981B** | `mediatek/filogic` | aarch64_cortex-a53 | GL-MT3000、小米 WR30U、360 T7 | `build-mt7981.yml` |

## 产出格式

| 格式 | 编译来源 | 适用系统 |
|---|---|---|
| **.ipk** | OpenWrt 23.05.5 稳定版 SDK | OpenWrt 21.02 / 22.03 / 23.05 等使用 **opkg** 的稳定版 |
| **.apk** | OpenWrt SNAPSHOT SDK | OpenWrt 快照版 / 24.10 之后使用 **apk** 包管理器的系统 |

## 项目结构

```
├── .github/workflows/
│   ├── build-mt7621.yml      # MT7621A: ipk + apk + Release
│   ├── build-mt7620.yml      # MT7620:  ipk + apk + Release
│   ├── build-mt7981.yml      # MT7981B: ipk + apk + Release
│   └── build-all.yml         # 一键编译全部架构，合并发布
├── scripts/
│   └── build-zerotier.sh     # 核心编译脚本（三个架构共用）
└── README.md
```

## 快速开始

### 1. 上传到你的 GitHub 仓库

```bash
cd zerotier-openwrt-cloudbuilder
git init
git add -A
git commit -m "feat: ZeroTier OpenWrt 云编译"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 2. 开启 Actions 写权限（发布 Release 必需）

仓库页面 → **Settings** → **Actions** → **General** → **Workflow permissions** → 勾选 **Read and write permissions** → Save。

### 3. 运行编译

进入仓库 **Actions** 页面，选择要运行的 workflow：

- **编译单个架构**：选择 `ZeroTier MT7621A (ipk + apk)` 等，点击 **Run workflow**
  - `openwrt_version`：ipk 使用的 OpenWrt 稳定版版本（默认 `23.05.5`，可改为 `22.03.7` 等）
  - `release_tag`：发布到的 Release Tag
  - `upload_release`：是否发布到 Release
- **一键编译全部架构**：选择 `ZeroTier 全架构一键编译`，三个架构并行编译，产物合并到同一个 Release。

也可以用 **打 Tag 触发** 自动编译发布：

```bash
# 全架构编译，发布到 v1.0.0 Release
git tag v1.0.0 && git push origin v1.0.0

# 只编译 MT7621A，发布到 mt7621-v1.0.0 Release
git tag mt7621-v1.0.0 && git push origin mt7621-v1.0.0
```

### 4. 下载安装包

编译完成后（单个架构约 10~20 分钟），到仓库 **Releases** 页面下载对应的 `.ipk` / `.apk` 文件。

## 路由器上安装

```bash
# 把安装包传到路由器后：

# OpenWrt 稳定版 (opkg)
opkg install zerotier_*.ipk

# OpenWrt SNAPSHOT (apk)
apk add --allow-untrusted zerotier-*.apk

# 启用并加入网络
uci set zerotier.global.enabled='1'
uci add zerotier network
uci set zerotier.@network[-1].id='<你的 Network ID>'
uci commit zerotier
/etc/init.d/zerotier restart
```

## 自定义

- **更换 ZeroTier 版本**：ipk 版本由所选 OpenWrt 稳定版的 packages feed 决定（23.05 为 1.12.x），apk 由 snapshot feed 决定（最新版）。如需指定版本，可在 `scripts/build-zerotier.sh` 的 feeds 更新后 checkout 对应 commit。
- **增加新架构**：复制任意一个 workflow 文件，修改 `env` 中的 `TARGET` / `SUBTARGET` / `ARCH_NAME` 三项即可。
- **编译其他软件包**：修改 `scripts/build-zerotier.sh` 中的 `PKG="zerotier"` 即可编译 packages feed 中的任意软件。

## 常见问题

| 问题 | 解决方法 |
|---|---|
| Release 发布失败 (403) | 检查 Settings → Actions → General → Workflow permissions 是否为 **Read and write** |
| SDK 下载 404 | 检查 `openwrt_version` 是否存在，或该版本是否支持对应 target |
| snapshot 编译失败 | snapshot 是滚动开发版，偶发失败属正常，可隔几天重跑 |
| MT7981 在 22.03 找不到 | filogic 自 23.05 才进入稳定版，请使用 23.05+ 或 snapshot |
