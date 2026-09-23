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

# 增加风扇控制驱动
sed -i 's/# CONFIG_PACKAGE_kmod-hwmon-gpiofan is not set/CONFIG_PACKAGE_kmod-hwmon-gpiofan=y/' .config
# 移除rknpu黑名单限制（放在cp之后，防止被覆盖）
sed -i '/blacklist rknpu/d' package/base-files/files/etc/modules.conf 2>/dev/null

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
cat target/linux/rockchip/armv8/config-6.6


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
