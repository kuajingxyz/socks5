#!/bin/bash

# 1. 权限检查
if [ "$(id -u)" != "0" ]; then
   echo "错误: 请使用 root 权限运行。"
   exit 1
fi

echo "============================================"
echo "    SOCKS5 一键部署脚本 (修复增强版)"
echo "============================================"

# 2. 强制从 TTY 读取输入，解决管道符跳过 read 的问题
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
echo "开始安装 Dante Server..."

# 3. 安装服务
apt-get update && apt-get install dante-server -y

# 4. 自动获取主网卡和公网 IP
INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5; exit}')
# 如果获取不到网卡则 fallback 到 eth0
INTERFACE=${INTERFACE:-eth0}
PUBLIC_IP=$(curl -s ifconfig.me)

# 5. 写入配置文件 (使用更健壮的写法)
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: daemon

# 监听设置
internal: 0.0.0.0 port = $PORT
external: $INTERFACE

# 认证设置
socksmethod: username

# 规则设置
clientpass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

sockspass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF

# 6. 配置代理用户
if id "$USER" &>/dev/null; then
    userdel -r "$USER" 2>/dev/null
fi
useradd -r -s /bin/false "$USER"
echo "$USER:$PASS" | chpasswd

# 7. 重启服务并检查状态
systemctl stop danted 2>/dev/null
systemctl enable danted
systemctl start danted

# 8. 最终输出
echo "============================================"
if systemctl is-active --quiet danted; then
    echo "✅ 部署成功并已启动！"
    echo "代理地址: $PUBLIC_IP"
    echo "代理端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
else
    echo "❌ 部署失败，请运行 'systemctl status danted' 查看报错。"
fi
echo "============================================"
