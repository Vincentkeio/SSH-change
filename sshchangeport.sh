#!/bin/bash

# 修改 SSH 配置
echo "修改 SSH 配置..."
# 你的配置修改代码，假设修改了 /etc/ssh/sshd_config 或其他文件

# 重启 SSH 服务
echo "重启 SSH 服务..."
systemctl restart ssh  # Ubuntu/Debian 系统适用

# 错误处理部分
if [ $? -ne 0 ]; then
    echo "SSH 服务重启失败"
    exit 1
fi

echo "SSH 服务修改和重启成功"
