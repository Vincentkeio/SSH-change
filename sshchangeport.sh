#!/bin/bash

# 检查当前操作系统
OS=$(grep -Eo "(ubuntu|debian|centos)" /etc/os-release | head -n 1)

# 重启SSH服务的部分
echo "尝试重启 SSH 服务..."
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    systemctl restart ssh
elif [[ "$OS" == "centos" ]]; then
    systemctl restart sshd
else
    echo "未知操作系统，无法确定正确的 SSH 服务名称"
    exit 1
fi

# 错误处理部分
if [ $? -ne 0 ]; then
    echo "SSH 服务重启失败"

    # 如果是 CentOS 系统，尝试启动 sshd 服务
    if [[ "$OS" == "centos" ]]; then
        echo "系统是 CentOS，尝试启动 sshd 服务..."
        systemctl start sshd.service
        if [ $? -eq 0 ]; then
            echo "sshd 服务已成功启动"
        else
            echo "sshd 服务启动失败，手动检查系统日志。"
        fi
    fi

    # 其他处理代码
    echo "请检查 SSH 服务日志以获取更多信息。"
    exit 1
else
    echo "SSH 服务重启成功"
fi
