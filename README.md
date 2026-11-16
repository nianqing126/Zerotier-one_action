# ZeroTier OpenWrt 云编译项目

基于 **GitHub Actions** 的 ZeroTier 在线编译项目，无需本地环境，一键云端编译并自动发布到 Release。

## 支持架构

| 芯片 | OpenWrt Target | 架构 | 代表机型 | Workflow 文件 |
|---|---|---|---|---|
| **MT7621A** | `ramips/mt7621` | mipsel_24kc | 小米 3G/4A、Newifi D2、红米 AC2100、K2P | `build-mt7621.yml` |
| **MT7620** | `ramips/mt7620` | mipsel_24kc（与 MT7621A 同架构） | 小米 mini、斐讯 K2、极路由 | `build-mt7620.yml` |
| **MT7981B** | `mediatek/filogic` | aarch64_cortex-a53 | GL-MT3000、小米 WR30U、360 T7 | `build-mt7981.yml` |

## 产出格式

| 格式 | 编译来源 | 适用系统 |
|---|---|---|
| **.ipk** | OpenWrt 23.05.5 稳定版 SDK | OpenWrt 21.02 / 22.03 / 23.05 / 24.10 等使用 **opkg** 的系统 |
| **.apk** | OpenWrt SNAPSHOT SDK | OpenWrt 25.12 / 快照版等使用 **apk** 包管理器的系统 |

每个格式都会产出 **3 个包**：

| 包名 | 说明 |
|---|---|
| `zerotier` | ZeroTier 主程序 + init 脚本 + `/etc/config/zerotier` |
| `luci-app-zerotier` | LuCI 网页界面（菜单：VPN → ZeroTier） |
| `luci-i18n-zerotier-zh-cn` | LuCI 中文语言包（同时产出 zh-tw / ru） |

> LuCI 界面使用仓库内嵌的 `packages/luci-app-zerotier`（源自 immortalwrt/luci，GPL-3.0），
> 采用 JS 版 LuCI 写法，兼容 21.02 ~ 25.12 的 LuCI；官方 feeds 自 23.05 起已不再提供该应用。

## 项目结构

```
├── .github/workflows/
│   ├── build-mt7621.yml      # MT7621A: ipk + apk + Release
│   ├── build-mt7620.yml      # MT7620:  ipk + apk + Release
│   ├── build-mt7981.yml      # MT7981B: ipk + apk + Release
│   └── build-all.yml         # 一键编译全部架构（自包含、6 任务并行、单 Release）
├── packages/
│   └── luci-app-zerotier/    # 内嵌的 LuCI 界面 + 中文语言包（随编译注入 SDK）
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

**文件名以架构为前缀**，一眼可辨、不会互相覆盖：

```
mt7621-zerotier_1.12.2-2_mipsel_24kc.ipk          ← 主程序（MT7621A）
mt7621-zerotier-1.16.2-r1.apk                     ← 主程序（MT7621A, snapshot）
mt7621-luci-app-zerotier_1.0.0-1_all.ipk          ← 界面（noarch，全架构通用）
mt7621-luci-i18n-zerotier-zh-cn_1.0.0-1_all.ipk   ← 中文语言包（noarch）
```

> `.apk` 格式本身不带架构后缀（OpenWrt 官方仓库靠目录区分架构），放到同一个 Release 里就必须靠文件名前缀区分，否则不同架构会重名互相覆盖。

## 架构说明

| 架构 | OpenWrt target | 包架构标识 | 说明 |
|---|---|---|---|
| MT7621A | `ramips/mt7621` | `mipsel_24kc` | |
| MT7620 | `ramips/mt7620` | `mipsel_24kc` | **与 MT7621A 同一 CPU 架构**，zerotier 是纯用户态程序，二进制互通；但两者 SDK 不同（gcc/libc 版本可能不同），项目仍分开编译，各自用自己 SDK 最稳 |
| MT7981B | `mediatek/filogic` | `aarch64_cortex-a53` | 与上面两个完全不同，不可混用 |

**LuCI 界面和语言包不需要区分架构**：它们是 `Architecture: all`（apk 中为 `noarch`），内容与 CPU 无关，各架构那份完全一致，装任意一份都行。

## 路由器上安装

```bash
# 把三个安装包一起传到路由器 /tmp 后（以 MT7621A 为例）：

# OpenWrt 稳定版 (opkg)
opkg install mt7621-zerotier_*.ipk mt7621-luci-app-zerotier_*.ipk mt7621-luci-i18n-zerotier-zh-cn_*.ipk

# OpenWrt 25.12 / SNAPSHOT (apk)
apk add --allow-untrusted mt7621-zerotier-*.apk mt7621-luci-app-zerotier-*.apk mt7621-luci-i18n-zerotier-zh-cn-*.apk

# 启用并加入网络（也可以在 LuCI：VPN → ZeroTier 里操作）
uci set zerotier.global.enabled='1'
uci add zerotier network
uci set zerotier.@network[-1].id='<你的 Network ID>'
uci commit zerotier
/etc/init.d/zerotier restart
```

安装完成后刷新 LuCI，左侧 **VPN → ZeroTier** 即为管理界面；中文界面在「系统 → 系统 → 语言和界面」中选择「简体中文」。

## 自定义

- **更换 ZeroTier 版本**：ipk 版本由所选 OpenWrt 稳定版的 packages feed 决定（23.05 为 1.12.x），apk 由 snapshot feed 决定（最新版）。如需指定版本，可在 `scripts/build-zerotier.sh` 的 feeds 更新后 checkout 对应 commit。
- **增加新架构**：复制任意一个 workflow 文件，修改 `env` 中的 `TARGET` / `SUBTARGET` / `ARCH_NAME` 三项即可。
- **修改 LuCI 界面**：直接编辑 `packages/luci-app-zerotier/` 下的 JS / po 文件，编译时会被注入 SDK。

## 常见问题

| 问题 | 解决方法 |
|---|---|
| `Please install GNU 'install'` | 新版 Ubuntu 镜像改用 uutils coreutils，`install --version` 不含 GNU，导致 SDK prereq 误判。已做三重处理：编译任务固定 `ubuntu-22.04`、脚本自动修复 GNU coreutils、失败时自动跳过误判检查 |
| Release 只有 `zerotier` 没有 luci | 说明跑的是旧版脚本，请确认仓库中的 `scripts/build-zerotier.sh` 与 `packages/luci-app-zerotier/` 是新版（日志里应出现「注入内嵌 LuCI 应用」） |
| Release 发布失败 (403) | 检查 Settings → Actions → General → Workflow permissions 是否为 **Read and write** |
| SDK 下载 404 | 检查 `openwrt_version` 是否存在，或该版本是否支持对应 target |
| snapshot 编译失败 | snapshot 是滚动开发版，偶发失败属正常，可隔几天重跑 |
| MT7981 在 22.03 找不到 | filogic 自 23.05 才进入稳定版，请使用 23.05+ 或 snapshot |
| 放进 `.github/workflows/` 后 Actions 里不显示 | ① 目录必须是 `workflows`（带 s），文件后缀必须是 `.yml` / `.yaml`；② **必须在默认分支（main / master）上**，GitHub 只展示默认分支的 workflow，其他分支的只在 PR 里有体现；③ 若是「调用其它 workflow」的写法，被调用的文件必须同分支存在且含 `workflow_call`，否则整个文件被判无效而不显示；④ 提交后刷新页面，偶有 1 分钟延迟。当前 `build-all.yml` 已改为**自包含**，不再依赖其它文件 |
| 报错 `ERROR: 未找到 packages/luci-app-zerotier` | 仓库里没提交这个新增目录。脚本已改为自动从 jsDelivr / GitHub 拉取兜底，但建议本地执行 `git add -f packages/luci-app-zerotier` 后提交，避免每次编译都依赖网络 |
| `No rule to make target 'package/luci-app-zerotier/compile'` | `packages/luci-app-zerotier/Makefile` 末尾的 `# call BuildPackage - OpenWrt buildroot signature` 注释被删了。SDK 扫描包时用 `grep` 找这句关键字，缺了整包会被静默跳过（脚本会自动补回） |
