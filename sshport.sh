#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用root权限运行此脚本！"
  exit 1
fi

# 提示用户输入新的SSH端口
read -p "请输入新的SSH端口号 (1-65535): " new_port

# 验证端口号是否有效
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
  echo "错误：请输入一个有效的端口号（1-65535）！"
  exit 1
fi

# 获取当前SSH端口
current_port=$(grep -E "^#?Port " /etc/ssh/sshd_config | awk '{print $2}')
if [ -z "$current_port" ]; then
  current_port=22 # 如果未设置Port，默认值为22
fi

# 修改sshd_config文件
ssh_config_file="/etc/ssh/sshd_config"
if [ -f "$ssh_config_file" ]; then
  # 备份配置文件
  cp "$ssh_config_file" "${ssh_config_file}.bak"

  # 更新端口配置
  if grep -qE "^#?Port " "$ssh_config_file"; then
    sed -i "s/^#\?Port .*/Port $new_port/" "$ssh_config_file"
  else
    echo "Port $new_port" >> "$ssh_config_file"
  fi

  echo "SSH 配置已更新，新的端口号为: $new_port"
else
  echo "错误：找不到SSH配置文件 $ssh_config_file"
  exit 1
fi

# 开放新端口并关闭旧端口
if command -v ufw >/dev/null 2>&1; then
  ufw allow $new_port/tcp
  echo "已开放新端口 $new_port"
  ufw delete allow $current_port/tcp
  echo "已关闭旧端口 $current_port"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=$new_port/tcp
  echo "已开放新端口 $new_port"
  firewall-cmd --permanent --remove-port=$current_port/tcp
  echo "已关闭旧端口 $current_port"
  firewall-cmd --reload
else
  echo "警告：未检测到受支持的防火墙工具，请手动开放新端口 $new_port 并关闭旧端口 $current_port"
fi

# 检查是否存在 sshd 服务（systemd 或 init.d）
echo "检查SSH服务..."
if command -v systemctl >/dev/null 2>&1; then
  # 如果使用 systemd，检查是否存在 sshd 服务
  if systemctl list-units --type=service | grep -q sshd; then
    echo "使用 systemd 重启 SSH 服务..."
    systemctl restart sshd
  else
    echo "错误：未找到 systemd 中的 sshd 服务。尝试修复..."
    # 如果找不到sshd.service，尝试重新安装或修复
    apt-get install --reinstall openssh-server -y  # Debian/Ubuntu
    # 或者：
    # yum reinstall openssh-server -y  # CentOS/RedHat
    systemctl restart sshd
  fi
elif [ -f "/etc/init.d/sshd" ]; then
  # 如果使用传统的 init.d 管理 SSH 服务
  echo "使用 init.d 重启 SSH 服务..."
  /etc/init.d/sshd restart
else
  echo "错误：找不到 SSH 服务管理工具（systemd 或 init.d）。"
  exit 1
fi

# 确保系统防火墙立即生效
echo "正在尝试关闭当前SSH会话并重新连接..."
sleep 2  # 等待配置生效
echo "如果没有问题，您应该可以使用新的端口重新连接。"

# 提示用户
echo "操作完成！当前SSH端口: $new_port。旧端口 $current_port 已关闭（如果防火墙工具支持）。"
