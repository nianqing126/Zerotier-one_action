# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2022 ImmortalWrt.org
# 内嵌版：源自 immortalwrt/luci applications/luci-app-zerotier
# 修改点：luci.mk 改为绝对路径引用，便于脱离 feeds/luci 目录独立编译

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Zerotier
LUCI_DEPENDS:=+zerotier

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature


