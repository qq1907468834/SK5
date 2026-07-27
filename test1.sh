#!/bin/bash
#SOCKS5一键安装脚本 Gost
set -e
if [ "$(id -u)" -ne 0 ];then
    echo "请使用root权限运行！"
    exit 1
fi

# ==========可修改默认参数==========
SOCKS_USER="admin"
SOCKS_PASS="Socks@8888"
SOCKS_PORT="1080"
# =================================

echo "===================开始部署SOCKS5==================="
apt update -y
apt install wget curl -y

# 自动判断CPU架构
ARCH=$(uname -m)
if [[ $ARCH == "x86_64" ]];then
    GOST_LINK="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
elif [[ $ARCH == "aarch64" ]];then
    GOST_LINK="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-arm64-2.11.5.gz"
else
    echo "不支持当前服务器架构：$ARCH"
    exit 1
fi

#下载安装gost
wget -O gost.gz $GOST_LINK
gunzip gost.gz
chmod +x gost
mv gost /usr/local/bin/

#创建systemd服务
cat > /etc/systemd/system/gost-socks5.service <<EOF
[Unit]
Description=Gost Socks5 Proxy
After=network.target
[Service]
ExecStart=/usr/local/bin/gost -L socks5://${SOCKS_USER}:${SOCKS_PASS}@0.0.0.0:${SOCKS_PORT}
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

#启动服务
systemctl daemon-reload
systemctl enable --now gost-socks5

#防火墙放行端口
ufw allow ${SOCKS_PORT}/tcp >/dev/null 2>&1
ufw allow ${SOCKS_PORT}/udp >/dev/null 2>&1

#【核心】自动获取服务器公网IP（多接口容错，防止单个IP接口失效）
GET_IP(){
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 shturl.cc/Tk || curl -s --max-time 5 ipinfo.io/ip)
}
GET_IP

# ==========部署完成，格式化输出你要求的信息==========
echo -e "\033[32m====================================================\033[0m"
echo "✅ SOCKS5搭建完成"
echo "公网地址：${PUBLIC_IP}"
echo "端口：${SOCKS_PORT}"
echo "账号：${SOCKS_USER}"
echo "密码：${SOCKS_PASS}"
echo "完整连接：socks5://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:${SOCKS_PORT}"
echo -e "\033[32m====================================================\033[0m"