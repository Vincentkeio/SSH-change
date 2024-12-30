#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用root权限运行此脚本！"
  exit 1
fi

# 检测操作系统类型
os_type=$(cat /etc/os-release | grep -i '^ID=' | cut -d= -f2 | tr -d '"')

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
open_ports() {
  if command -v ufw >/dev/null 2>&1; then
    # 确保ufw防火墙启用
    if ! sudo ufw status | grep -q "Status: active"; then
      echo "ufw防火墙未启用，正在启用ufw防火墙..."
      sudo ufw enable
    fi
    sudo ufw allow $new_port/tcp
    echo "已开放新端口 $new_port"
    sudo ufw delete allow $current_port/tcp || echo "警告：未找到旧端口 $current_port 的规则"
    sudo ufw reload  # 确保防火墙规则生效
    echo "已关闭旧端口 $current_port"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # 检查firewalld防火墙状态
    if ! sudo systemctl is-active --quiet firewalld; then
      echo "firewalld防火墙未启用，正在启动firewalld..."
      sudo systemctl start firewalld
      sudo systemctl enable firewalld
    fi
    sudo firewall-cmd --permanent --add-port=$new_port/tcp
    sudo firewall-cmd --permanent --remove-port=$current_port/tcp || echo "警告：未找到旧端口 $current_port 的规则"
    sudo firewall-cmd --reload
    echo "已开放新端口 $new_port"
    echo "已关闭旧端口 $current_port"
  else
    echo "警告：未检测到受支持的防火墙工具，请手动开放新端口 $new_port 并关闭旧端口 $current_port"
  fi
}

# 安装并启动防火墙服务
install_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    echo "未检测到ufw，正在安装ufw..."
    apt install -y ufw || yum install -y ufw
    ufw enable
  fi
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    echo "未检测到firewalld，正在安装firewalld..."
    apt install -y firewalld || yum install -y firewalld
    systemctl start firewalld
    systemctl enable firewalld
  fi
}

# 检查并修复 SSH 服务
install_ssh() {
  if [[ "$os_type" == "ubuntu" || "$os_type" == "debian" ]]; then
    # Ubuntu/Debian 系统
    if ! systemctl is-active --quiet ssh; then
      echo "SSH 服务未安装或未启动，正在安装 SSH 服务..."
      apt update && apt install -y openssh-server
      systemctl enable ssh
      systemctl start ssh
      echo "SSH 服务已安装并启动！"
    fi
  elif [[ "$os_type" == "centos" || "$os_type" == "rhel" ]]; then
    # CentOS/RHEL 系统
    if ! systemctl is-active --quiet sshd; then
      echo "SSH 服务未安装或未启动，正在安装 SSH 服务..."
      yum install -y openssh-server
      systemctl enable sshd
      systemctl start sshd
      echo "SSH 服务已安装并启动！"
    fi
  else
    echo "无法识别的操作系统：$os_type，无法处理 SSH 服务。"
    exit 1
  fi
}

# 检查并重启SSH服务
restart_ssh() {
  echo "尝试重启 SSH 服务..."

  # 确保 systemd 加载新的配置
  sudo systemctl daemon-reload
  echo "已执行 systemctl daemon-reload"

  # 对于 CentOS 和 RHEL，使用 sshd 服务
  if [[ "$os_type" == "centos" || "$os_type" == "rhel" ]]; then
    sudo systemctl restart sshd
    echo "已执行 systemctl restart sshd"
  else
    sudo systemctl restart ssh
    echo "已执行 systemctl restart ssh"
  fi
}

# 尝试重启 SSH 服务，最多重试 5 次
attempt=1
max_attempts=5
while ! systemctl is-active --quiet ssh && [ $attempt -le $max_attempts ]; do
  echo "尝试重启 SSH 服务，尝试次数: $attempt/$max_attempts"
  restart_ssh
  attempt=$((attempt + 1))
  sleep 2
done

# 如果 SSH 服务仍然无法启动，重新安装 SSH 服务并重试
if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
  echo "错误：SSH 服务无法启动，正在重新安装 SSH 服务..."
  install_ssh
  restart_ssh
fi

# 确保重启服务后，检查新的 SSH 配置是否生效
echo "重启后的 SSH 配置："
ss -tuln | grep $new_port  # 检查新的端口是否开放

# 如果端口未开放，立即修复
if ! ss -tuln | grep -q $new_port; then
  echo "错误：新端口 $new_port 未成功开放，执行修复步骤..."

  # 执行修复步骤：重新加载配置并重启SSH服务
  echo "执行 systemctl daemon-reload..."
  sudo systemctl daemon-reload

  echo "执行 /etc/init.d/ssh restart..."
  sudo /etc/init.d/ssh restart

  echo "执行 systemctl restart ssh..."
  sudo systemctl restart ssh

  # 再次检查新端口是否开放
  echo "检查新端口是否生效..."
  ss -tuln | grep $new_port

  # 如果修复后端口仍未开放，输出错误信息并退出
  if ! ss -tuln | grep -q $new_port; then
    echo "错误：修复后新端口 $new_port 仍未成功开放，请检查配置。"
    exit 1
  fi
fi

echo "操作完成！"
