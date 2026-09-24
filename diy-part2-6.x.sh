#!/bin/bash
#===============================================
# Description: DIY script
# File name: diy-script.sh
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#===============================================

# ===============================================================
# RK3568 通用 EasePi U-Boot：为 bd-one 注入 ADC keys
# bendian_bd-one -> Device/Legacy/rk3568 -> easepi-rk3568
# ===============================================================
UBOOT_DTS="package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-easepi.dts"
ADC_KEYS_SRC="$GITHUB_WORKSPACE/configfiles/adc-keys.txt"

test -f "$UBOOT_DTS" || {
  echo "ERROR: 找不到通用 U-Boot DTS: $UBOOT_DTS"
  exit 1
}

test -f "$ADC_KEYS_SRC" || {
  echo "ERROR: 找不到 adc-keys.txt: $ADC_KEYS_SRC"
  exit 1
}

# KEY_VOLUMEUP 宏来自 dt-bindings/input/input.h。
if ! grep -qF '#include <dt-bindings/input/input.h>' "$UBOOT_DTS"; then
  sed -i '/#include <dt-bindings\/gpio\/gpio.h>/a #include <dt-bindings/input/input.h>' \
    "$UBOOT_DTS"
fi

# 只注入一次，避免同一份源码被缓存/重复执行时产生重复节点。
if ! grep -q 'adc-keys {' "$UBOOT_DTS"; then
  sed -i '/"rockchip,rk3568";/r '"$ADC_KEYS_SRC" "$UBOOT_DTS"
fi

echo "========== EasePi RK3568 U-Boot DTS injection =========="
echo "Target: $UBOOT_DTS"

echo "----- input.h -----"
grep -nF '#include <dt-bindings/input/input.h>' "$UBOOT_DTS" || {
  echo "ERROR: input.h 未成功注入"
  exit 1
}

echo "----- adc-keys node -----"
grep -n -B 3 -A 18 'adc-keys {' "$UBOOT_DTS" || {
  echo "ERROR: adc-keys 节点未成功注入"
  exit 1
}

echo "----- required ADC-key properties -----"
grep -nE \
  'io-channels = <&saradc 0>|keyup-threshold-microvolt|KEY_VOLUMEUP|press-threshold-microvolt|u-boot,dm-spl' \
  "$UBOOT_DTS" || {
  echo "ERROR: adc-keys 节点内容不完整"
  exit 1
}

echo "✅ EasePi RK3568 U-Boot DTS injection verified."
echo "========================================================="



# ===============================================================
# 通用 EasePi RK3568 U-Boot：仅检查现有配置，不强制改写。
# bd-one 通过 Device/Legacy/rk3568 使用 easepi-rk3568。
# ===============================================================
UBOOT_DEFCONFIG="package/boot/uboot-rockchip/src/configs/easepi-rk3568_defconfig"

test -f "$UBOOT_DEFCONFIG" || {
  echo "ERROR: 找不到 U-Boot defconfig: $UBOOT_DEFCONFIG"
  exit 1
}

echo "========== EasePi RK3568 U-Boot config check =========="
grep -nE \
  'CONFIG_(CMD_ADC|ADC_KEY|ADC|ADC_ROCKCHIP|SPL_OF_CONTROL|SPL_PINCTRL|USB_DWC3_GADGET|USB_GADGET|USB_GADGET_DOWNLOAD|ROCKCHIP_DNL_KEY)' \
  "$UBOOT_DEFCONFIG" || true
echo "========================================================"


# 修改uhttpd配置文件，启用nginx
# sed -i "/.*uhttpd.*/d" .config
# sed -i '/.*\/etc\/init.d.*/d' package/network/services/uhttpd/Makefile
# sed -i '/.*.\/files\/uhttpd.init.*/d' package/network/services/uhttpd/Makefile
sed -i "s/:80/:81/g" package/network/services/uhttpd/files/uhttpd.config
sed -i "s/:443/:4443/g" package/network/services/uhttpd/files/uhttpd.config
cp -a $GITHUB_WORKSPACE/configfiles/etc/* package/base-files/files/etc/
# ls package/base-files/files/etc/

# Add the default password for the 'root' user（Change the empty password to 'password'）
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

#切换golong版本
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# 增加风扇控制驱动
sed -i 's/# CONFIG_PACKAGE_kmod-hwmon-gpiofan is not set/CONFIG_PACKAGE_kmod-hwmon-gpiofan=y/' .config

#添加第三方软件源
sed -i "s/option check_signature/# option check_signature/g" package/system/opkg/Makefile
echo src/gz openwrt_kiddin9 https://dl.openwrt.ai/latest/packages/aarch64_generic/kiddin9 >> ./package/system/opkg/files/customfeeds.conf

cat > package/base-files/files/etc/modules.conf << 'EOF'
# examples:
# options mod1 option=val
# blacklist mod2
blacklist r8125
blacklist r8168
EOF

echo "===== 生成后的 modules.conf 内容 ====="
cat package/base-files/files/etc/modules.conf
if grep -q "rknpu" package/base-files/files/etc/modules.conf; then
    echo "⚠️ 警告：文件中意外包含 rknpu，请检查"
else
    echo "✅ 确认文件中没有 rknpu 相关黑名单"
fi

# 尝试启用 RKNPU 的 OpenWrt 内核模块包。
# 该配置在后续 make defconfig 后仍须验证是否被保留。
sed -i '/^CONFIG_PACKAGE_kmod-rknpu=/d' .config
sed -i '/^# CONFIG_PACKAGE_kmod-rknpu is not set$/d' .config
echo 'CONFIG_PACKAGE_kmod-rknpu=y' >> .config

echo "===== P2 阶段：请求启用 kmod-rknpu ====="
grep -nE '^CONFIG_PACKAGE_kmod-rknpu=|^# CONFIG_PACKAGE_kmod-rknpu is not set$' .config || {
    echo "ERROR: 未能写入 CONFIG_PACKAGE_kmod-rknpu"
    exit 1
}


echo "===== 搜索源码中所有含 rknpu auto_unload 的位置 ====="
grep -rn "auto_unload.*rknpu" . 2>/dev/null || echo "未在当前源码树中找到相关配置"

echo "===== 源码中 kmods 配置文件检查 ====="
if [ -f package/base-files/files/etc/config/kmods ]; then
    cat package/base-files/files/etc/config/kmods
else
    echo "源码中未找到 package/base-files/files/etc/config/kmods，说明这个文件可能是编译时自动生成的，不在预置文件里"
fi

# 追加自定义内核配置项
echo "CONFIG_PSI=y
CONFIG_KPROBES=y" >> target/linux/rockchip/armv8/config-6.6


# 集成CPU性能跑分脚本
cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64 package/base-files/files/bin/coremark-arm64
cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64.sh package/base-files/files/bin/coremark.sh
chmod 755 package/base-files/files/bin/coremark-arm64
chmod 755 package/base-files/files/bin/coremark.sh


# iStoreOS-settings
git clone --depth=1 -b main https://github.com/xiaomeng9597/istoreos-settings package/default-settings


# 定时限速插件
git clone --depth=1 https://github.com/sirpdboy/luci-app-eqosplus package/luci-app-eqosplus


# ===============================================================
# OpenWrt 软件包选择
# 注意：这里操作的是根目录 .config；不是 Linux config-6.6。
# ===============================================================

enable_package() {
    local pkg="$1"
    sed -i "/^CONFIG_PACKAGE_${pkg}=/d" .config
    sed -i "/^# CONFIG_PACKAGE_${pkg} is not set$/d" .config
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
}

echo "========== 请求启用 RKNPU 包 =========="
enable_package "kmod-rknpu"
grep -nE '^CONFIG_PACKAGE_kmod-rknpu=y$' .config || {
    echo "ERROR: 未能写入 CONFIG_PACKAGE_kmod-rknpu=y"
    exit 1
}

disable_package() {
    local pkg="$1"

    sed -i "/^CONFIG_PACKAGE_${pkg}=/d" .config
    sed -i "/^# CONFIG_PACKAGE_${pkg} is not set$/d" .config
    echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
}

disable_package "luci-app-ddns"
disable_package "ddnsto"
disable_package "luci-app-linkease"
disable_package "ddnsto"

echo "========== 请求启用 LuCI 包 =========="
enable_package "luci-app-npc"
enable_package "npc"
enable_package "luci-app-passwall"
enable_package "luci-app-openclash"

echo "===== 当前 .config 中请求的 LuCI/RKNPU 包 ====="
grep -nE '^CONFIG_PACKAGE_(kmod-rknpu|luci|luci-base|luci-i18n-base-zh-cn|luci-app-eqosplus|luci-i18n-eqosplus-zh-cn|luci-app-opkg|luci-app-ttyd|luci-app-filemanager|luci-app-argon-config)=y$' \
  .config || true



# 增加bendian_bd-one
echo -e "\\ndefine Device/bendian_bd-one
\$(call Device/Legacy/rk3568,\$(1))
  DEVICE_VENDOR := BENDIAN
  DEVICE_MODEL := BD ONE
  DEVICE_DTS := rk3568/rk3568-bendian-one
  DEVICE_PACKAGES += kmod-nvme kmod-ata-ahci-dwc kmod-hwmon-pwmfan kmod-hwmon-gpiofan kmod-thermal kmod-r8169
endef
TARGET_DEVICES += bendian_bd-one" >> target/linux/rockchip/image/legacy.mk


# 增加nsy_g68-plus
echo -e "\\ndefine Device/nsy_g68-plus
\$(call Device/Legacy/rk3568,\$(1))
  DEVICE_VENDOR := NSY
  DEVICE_MODEL := G68
  DEVICE_DTS := rk3568/rk3568-nsy-g68-plus
  DEVICE_PACKAGES += kmod-nvme kmod-ata-ahci-dwc kmod-hwmon-pwmfan kmod-thermal kmod-r8169
endef
TARGET_DEVICES += nsy_g68-plus" >> target/linux/rockchip/image/legacy.mk


# 复制 02_network 网络配置文件到 target/linux/rockchip/armv8/base-files/etc/board.d/ 目录下
cp -f $GITHUB_WORKSPACE/configfiles/02_network target/linux/rockchip/armv8/base-files/etc/board.d/02_network


cp -f $GITHUB_WORKSPACE/configfiles/init.sh target/linux/rockchip/armv8/base-files/lib/board/init.sh


cat "${GITHUB_WORKSPACE}/configfiles/config-6.6.local" >> target/linux/rockchip/armv8/config-6.6
#cat target/linux/rockchip/armv8/config-6.6


# target/linux/rockchip/files/drivers/net/
mkdir -p target/linux/rockchip/files/drivers/net/dsa
cp -a $GITHUB_WORKSPACE/configfiles/userpatches/dsa/* target/linux/rockchip/files/drivers/net/dsa/
chmod -R 775 target/linux/rockchip/files/drivers/net/dsa/
ls target/linux/rockchip/files/drivers/net/dsa/


cp -a $GITHUB_WORKSPACE/configfiles/userpatches/patches-6.x/* target/linux/rockchip/patches-6.6/
ls target/linux/rockchip/patches-6.6/


# 复制dts设备树文件到指定目录下
cp -a $GITHUB_WORKSPACE/configfiles/dts/rk3568/* target/linux/rockchip/dts/rk3568/
cp -a $GITHUB_WORKSPACE/configfiles/dts/rk3588/* target/linux/rockchip/dts/rk3588/
