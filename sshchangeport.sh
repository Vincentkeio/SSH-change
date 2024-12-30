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

echo "当前SSH端口为: $current_port"

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

# 检查修改后的配置是否生效
grep "^Port " "$ssh_config_file"

# 开放新端口并关闭旧端口
if command -v ufw >/dev/null 2>&1; then
  ufw allow $new_port/tcp
  echo "已开放新端口 $new_port"
  # 如果旧端口规则不存在，跳过删除
  ufw status | grep -q "ALLOW.*$current_port" && ufw delete allow $current_port/tcp
  echo "已关闭旧端口 $current_port"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=$new_port/tcp
  echo "已开放新端口 $new_port"
  # 如果旧端口规则不存在，跳过删除
  firewall-cmd --permanent --remove-port=$current_port/tcp || echo "警告：未找到旧端口 $current_port 的规则"
  echo "已关闭旧端口 $current_port"
  firewall-cmd --reload
else
  echo "警告：未检测到受支持的防火墙工具，请手动开放新端口 $new_port 并关闭旧端口 $current_port"
fi

# 检测并安装 SSH 服务（如果不存在）
if ! systemctl is-active --quiet sshd && ! systemctl is-active --quiet ssh; then
  echo "未检测到 SSH 服务，正在安装 SSH 服务..."
  
  # 检查系统类型并安装 SSH 服务
  if command -v apt >/dev/null 2>&1; then
    # 对于基于Debian/Ubuntu的系统
    apt update && apt install -y openssh-server
  elif command -v yum >/dev/null 2>&1; then
    # 对于基于RHEL/CentOS的系统
    yum install -y openssh-server
  elif command -v dnf >/dev/null 2>&1; then
    # 对于基于Fedora的系统
    dnf install -y openssh-server
  else
    echo "错误：无法识别此系统，无法自动安装 SSH 服务！"
    exit 1
  fi

  # 启动 SSH 服务
  systemctl enable sshd
  systemctl start sshd
  echo "SSH 服务已安装并启动！"
else
  echo "SSH 服务已存在，跳过安装。"
fi

# 检查并重启SSH服务
# 使用 systemctl 或 /etc/init.d 重启 SSH 服务
service_name="sshd"
if systemctl is-active --quiet "$service_name"; then
  systemctl restart "$service_name"
  echo "SSH 服务已成功重启！"
elif [ -f "/etc/init.d/sshd" ]; then
  /etc/init.d/sshd restart
  echo "通过 /etc/init.d 重启了 SSH 服务！"
else
  echo "错误：无法重启 SSH 服务，请检查配置是否正确！"
  exit 1
fi

# 确保重启服务后，检查新的 SSH 配置是否生效
echo "重启后的 SSH 配置："
ss -tuln | grep $new_port  # 检查新的端口是否开放

# 提示用户
echo "操作完成！当前SSH端口: $new_port。旧端口 $current_port 已关闭（如果防火墙工具支持）。"
