#!/bin/bash

# 1. 权限检查
if [ "$(id -u)" != "0" ]; then
   echo "错误: 请使用 root 权限运行此脚本。"
   exit 1
fi

echo "============================================"
echo "    SOCKS5 自动清理及重装脚本"
echo "============================================"

# 2. 强制从 TTY 读取输入，防止变量落空
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

# 3. 彻底清理旧服务和进程
systemctl stop danted >/dev/null 2>&1
killall -9 danted >/dev/null 2>&1  # 强制杀掉残留进程
apt-get remove --purge dante-server -y >/dev/null 2>&1
rm -rf /etc/danted.conf
rm -f /var/run/danted.pid

# 4. 重新安装 Dante
echo "正在重新安装 Dante Server..."
apt-get update && apt-get install dante-server -y

# 5. 自动获取当前活动的网卡名称
INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')
# 如果获取不到网卡，回退到常见默认值
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link show | awk -F': ' '$2 !~ /lo|vir/ {print $2; exit}')
fi
INTERFACE=${INTERFACE:-eth0}

# 6. 写入全新的配置文件 (纯净无注释版，防止字符干扰)
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: daemon

internal: 0.0.0.0 port = $PORT
external: $INTERFACE

socksmethod: username

clientpass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

sockspass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF

# 7. 重新处理用户 (删除后重建，确保密码更新)
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
if systemctl is-active --quiet danted; then
    echo "✅ 重新部署成功！"
    echo "代理地址: $PUBLIC_IP"
    echo "代理端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "网卡设备: $INTERFACE"
else
    echo "❌ 部署后服务启动失败。"
    echo "排查建议: "
    echo "1. 运行 'danted -v' 检查语法。"
    echo "2. 运行 'ss -ntlp | grep $PORT' 检查端口是否被占用。"
fi
echo "============================================"
