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

  echo "SSH 配置已更新，新的端口号为: $new_
