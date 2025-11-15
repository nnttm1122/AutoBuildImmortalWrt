#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

# 创建配置目录和pppoe-settings文件
echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 第三方软件包处理
if [ -n "$CUSTOM_PACKAGES" ]; then
    echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
    echo "✅ Run files copied to extra-packages:"
    ls -lh /home/build/immortalwrt/extra-packages/*.run

    # 解压并拷贝ipk到packages目录
    sh shell/prepare-packages.sh
    ls -lah /home/build/immortalwrt/packages/
    
    # 添加架构优先级信息
    sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
else
    echo "⚪️ 未选择任何第三方软件包"
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建QEMU-arm64固件..."

# 定义所需安装的包列表
PACKAGES="curl luci-i18n-quickstart-zh-cn luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn luci-i18n-ttyd-zh-cn luci-i18n-passwall-zh-cn luci-app-openclash luci-i18n-nikki-zh-cn"
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 若构建 openclash 则下载 core
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 输出要构建的包
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 输出目录
OUTPUT_DIR="/home/build/immortalwrt/bin/targets/armsr/armv8"
mkdir -p $OUTPUT_DIR

# 构建镜像
make image \
    PROFILE=$PROFILE \
    PACKAGES="$PACKAGES" \
    FILES="/home/build/immortalwrt/files" \
    ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

# 找到 rootfs 文件并重命名为 PVE 专用
ROOTFS_FILE=$(find bin/targets/armsr/armv8/ -type f -name "*rootfs.tar.gz" | head -n1)
if [ -f "$ROOTFS_FILE" ]; then
    mv "$ROOTFS_FILE" "$OUTPUT_DIR/pve-rootfs.tar.gz"
    echo "✅ PVE rootfs 已生成: $OUTPUT_DIR/pve-rootfs.tar.gz"
else
    echo "❌ 没有找到生成的 rootfs 文件"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
