#!/bin/bash

# 1. 权限检查
if [ "$(id -u)" != "0" ]; then
   echo "错误: 请使用 root 权限运行此脚本。"
   exit 1
fi

echo "============================================"
echo "    SOCKS5 自动清理及重装脚本 (最终修复版)"
echo "============================================"

# 2. 强制从终端读取输入，确保变量绝不丢失
exec < /dev/tty

read -p "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}

read -p "请输入代理用户名 (默认 proxyuser): " USER
USER=${USER:-proxyuser}

read -p "请输入代理密码: " PASS
while [ -z "$PASS" ]; do
    read -p "密码不能为空，请重新输入: " PASS
done

# 恢复标准输入
exec < /dev/stdin

echo "--------------------------------------------"
echo "正在彻底清理旧的安装..."

# 3. 彻底清理环境 (防范端口占用和配置文件残留)
systemctl stop danted >/dev/null 2>&1
killall -9 danted >/dev/null 2>&1
apt-get remove --purge dante-server -y >/dev/null 2>&1
rm -rf /etc/danted.conf
rm -f /var/run/danted.pid

# 4. 重新安装 Dante
echo "正在重新安装 Dante Server..."
apt-get update && apt-get install dante-server -y

# 5. 自动获取当前活动的网卡名称
INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link show | awk -F': ' '$2 !~ /lo|vir/ {print $2; exit}')
fi
INTERFACE=${INTERFACE:-eth0}

# 6. 写入配置文件 (已修复致命的 client pass 语法空格问题)
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: daemon

internal: 0.0.0.0 port = $PORT
external: $INTERFACE

socksmethod: username

# 注意：Dante 严格要求以下指令必须带有空格
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF

# 7. 重置系统代理用户
if id "$USER" &>/dev/null; then
    userdel -f "$USER" >/dev/null 2>&1
fi
useradd -r -s /bin/false "$USER"
echo "$USER:$PASS" | chpasswd

# 8. 启动服务并设置开机自启
systemctl restart danted
systemctl enable danted

# 9. 获取公网 IP
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "无法获取IP")

echo "============================================"
# 检查服务最终状态
if systemctl is-active --quiet danted; then
    echo "✅ 重新部署成功！"
    echo "代理地址: $PUBLIC_IP"
    echo "代理端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "网卡设备: $INTERFACE"
    echo "--------------------------------------------"
    echo "👉 提示: 请务必在您的云面板放行 TCP 端口 $PORT"
else
    echo "❌ 部署后服务启动失败。"
    echo "请运行 'journalctl -u danted -e' 查看最新报错。"
fi
echo "============================================"
