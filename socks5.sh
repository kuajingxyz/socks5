#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "错误: 请使用 sudo 或 root 用户运行此脚本。"
   exit 1
fi

echo "============================================"
echo "    SOCKS5 一键部署脚本 (Dante)"
echo "============================================"

# 解决管道符导致 read 跳过的问题：强制从当前终端读取输入
exec < /dev/tty

# 交互式输入配置信息
read -p "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}

read -p "请输入代理用户名 (默认 proxyuser): " USER
USER=${USER:-proxyuser}

read -p "请输入代理密码: " PASS
while [ -z "$PASS" ]; do
    read -p "密码不能为空，请重新输入: " PASS
done

echo "--------------------------------------------"
echo "正在安装并配置，请稍候..."

# 1. 更新并安装 Dante
apt-get update && apt-get install dante-server -y

# 2. 获取主网卡名称
INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')

# 3. 写入 Dante 配置文件
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

# 4. 处理用户逻辑（如果存在则先删除，确保更新）
if id "$USER" &>/dev/null; then
    userdel -r "$USER" 2>/dev/null
fi
useradd -r -s /bin/false "$USER"
echo "$USER:$PASS" | chpasswd

# 5. 重启并设置开机自启
systemctl restart danted
systemctl enable danted

# 6. 获取公网 IP
IP=$(curl -s ifconfig.me)

echo "============================================"
echo "✅ 部署成功！"
echo "代理地址: $IP"
echo "代理端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASS"
echo "============================================"
echo "请确保防火墙已放行 TCP 端口: $PORT"

# 恢复标准输入
exec < /dev/stdin
