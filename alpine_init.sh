#!/bin/sh

# 权限检查函数
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误：请使用 root 用户执行此脚本（执行命令：su - 切换到 root）" >&2
        exit 1
    fi
}

# 基础环境初始化
init_basic_env() {
    echo "===== 基础环境初始化开始 ====="
    
    # 添加 edge 社区仓库
    echo "[1/3] 添加 edge 社区仓库"
    if grep -q "edge/community" /etc/apk/repositories; then
        echo "  提示：edge/community 仓库已存在，跳过添加"
    else
        echo 'https://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
        echo "  成功：仓库已添加到 /etc/apk/repositories"
    fi

    # 更新 apk 包索引
    echo "[2/3] 更新 apk 包索引"
    if apk update > /dev/null 2>&1; then
        echo "  成功：包索引更新完成"
    else
        echo "  错误：包索引更新失败，请检查网络连接" >&2
        exit 1
    fi

    # 安装指定软件包
    echo "[3/3] 安装 micro 和 openrc"
    if apk add --no-cache micro openrc > /dev/null 2>&1; then
        echo "  成功：软件包安装完成"
    else
        echo "  错误：软件包安装失败，请检查仓库配置" >&2
        exit 1
    fi

    echo "===== 基础环境初始化完成 ====="
    echo "  已安装工具："
    echo "    - micro   "
    echo "    - openrc  "
}

# 设置主机名
set_hostname() {
    echo "===== 设置主机名开始 ====="

    current_hostname=$(hostname)
    echo "当前主机名：$current_hostname"

	read -p "请输入新的主机名：" new_hostname
    if ! hostname "$new_hostname"; then
        echo "错误：设置主机名失败" >&2
        return 1
    fi

    if ! echo "$new_hostname" > /etc/hostname; then
        echo "错误：写入 /etc/hostname 失败" >&2
        hostname "$current_hostname"  # 回滚临时设置
        return 1
    fi

    if ! sed -i "s/\b$current_hostname\b/$new_hostname/g; /^127.0.0.1/ s/$/ $new_hostname/" /etc/hosts; then
        echo "错误：更新 /etc/hosts 失败！" >&2
        return 1
    fi

    echo "===== 设置主机名完成 ====="
    echo "  当前主机名：$(hostname)"
}

setup_ssh() {
    echo "===== 设置 ssh 开始 ====="

    pubkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDga8UYXPw2CDHTUH2a0mSOAnzXkl+7cD4BTDf/BSD4A3xnFA6g1XDn37tmm4oF6SvKsD57Lu+UMqj5uOKleZQiLdQ1J2+Z02CvfkvVLFTan/Q/wOVTNTvfoALkM6DNcxEUzjbno49g1mLdohpEWcsj7MgfOAwrwzg8fc+vi5aqYtyxFUBTMWlB4U9fVA4NUwjE5EkqjC0Jv1ogGYV4bcu9tGJCvC6xU6G5u1P2cK/fxOSexMpgx2O4L37pNVhdzx2xH7bbg7LswGAvsoKS5VOGa8xq0Et1FQAfqkwMOg7YEDEVq/tWV9gN2PjBsi3kWyW6KqV9ZPZ9QG0erw2L7Udc4YwcgVU2xMlUmUL2J8sUnBM7WfG/DLL3WMfP/7PsvUDYh/PysPqiYkGFanqOCFqw504CUv5QB/YP534sx00j49O3SiZRp7E2hioMLib3XkSszxGxbxq/4qNyNDzXz40A0slbL0U7FUERLmqBbl3qvVVwXe16dg7FZSg/VGZb1DE= viaco@DESKTOP-DHUM8IM"
    ssh_dir="/root/.ssh"
    auth_keys="$ssh_dir/authorized_keys"
    
    
    echo "[1/5] 配置 authorized_keys"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown root:root "$ssh_dir"
    echo "$pubkey" > "$auth_keys"
    chmod 600 "$auth_keys"  # 仅所有者可读写
    chown root:root "$auth_keys"

    
    echo "[2/5] 配置 sshd_config"
    sshd_config="/etc/ssh/sshd_config"
    cp "$sshd_config" "$sshd_config.bak.$(date +%Y%m%d%H%M%S)" # 备份原始配置
    # 启用公钥认证
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
    if ! grep -q '^PubkeyAuthentication yes' "$sshd_config"; then
        echo "PubkeyAuthentication yes" >> "$sshd_config"
    fi
    # 配置公钥文件路径
    sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' "$sshd_config"
    if ! grep -q '^AuthorizedKeysFile .ssh/authorized_keys' "$sshd_config"; then
        echo "AuthorizedKeysFile .ssh/authorized_keys" >> "$sshd_config"
    fi
    # 询问是否禁用密码登录（增强安全性）
    read -p "是否禁用密码登录（仅允许公钥登录）？(y/N) " disable_password
    if [ "$disable_password" = "y" ] || [ "$disable_password" = "Y" ]; then
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        if ! grep -q '^PasswordAuthentication no' "$sshd_config"; then
            echo "PasswordAuthentication no" >> "$sshd_config"
        fi
        echo "  已禁用密码登录"
    else
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
        echo "  保留密码登录"
    fi
 

    echo "[3/5] 校验配置文件"
    if ! sshd -t >/dev/null 2>&1; then
        echo "错误：sshd_config 配置语法错误！正在恢复备份" >&2
        cp "$sshd_bak" "$sshd_config"
        return 1
    fi
    echo "  sshd_config 配置已更新（备份：$sshd_bak）"
 

    echo "[4/5] 重启服务"
    rc-update add sshd default >/dev/null 2>&1
    if ! rc-service sshd restart >/dev/null 2>&1; then
        echo "错误：sshd 服务重启失败！正在恢复配置" >&2
        cp "$sshd_bak" "$sshd_config"
        rc-service sshd restart >/dev/null 2>&1
        return 1
    fi
 

    echo "[5/5] 服务状态检查"
    if rc-service sshd status | grep -q "started"; then
        echo "===== 设置 ssh 完成 ====="
        echo "  公钥路径：$auth_keys"
    else
        echo "错误：sshd 服务未正常启动，请检查 /var/log/messages 日志！" >&2
        return 1
    fi
}

# 安装 vnstat
install_vnstat() {
    echo "[1/3] 安装 vnstat"
    apk add vnstat
    echo "[2/3] 设置开机启动"
    rc-update add vnstatd default
    echo "[3/3] 启动服务"
    rc-service vnstatd start
}


# 安装 sing-box
install_singbox() {
    read -p "输入 AnyTLS 端口（默认 30021）" user_input
    if [ -z "$user_input" ]; then
        anytls_port=30021
    else
        anytls_port=$user_input
    fi
    
    echo "  AnyTLS 端口：$anytls_port"

    read -p "输入 shadowsocks 端口（默认 30022）" user_input
    if [ -z "$user_input" ]; then
        ss_port=30022
    else
        ss_port=$user_input
    fi
    echo "  shadowsocks 端口：$ss_port"

    cert_dir="/etc/sing-box/cert"
    cert_pem_path="$cert_dir/cert.pem"
    cert_key_path="$cert_dir/private.key"
    config_path="/etc/sing-box/config.json"
    
    echo "[1/6] 安装 sing-box"
    if grep -q "edge/community" /etc/apk/repositories; then
        echo "  提示：edge/community 仓库已存在，跳过添加"
    else
        echo 'https://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
        echo "  成功：仓库已添加到 /etc/apk/repositories"
    fi
    apk add sing-box
    echo "[2/6] 写入证书"
    mkdir -p $cert_dir
    cat > "$cert_pem_path" << 'EOF'
-----BEGIN CERTIFICATE-----
MIIBgzCCASmgAwIBAgIUPBDmycV5DFQXFFO1KPaI+6l6kRcwCgYIKoZIzj0EAwIw
FjEUMBIGA1UEAwwLbW96aWxsYS5vcmcwIBcNMjUwODE0MTQ1MTEwWhgPMjEyNTA3
MjExNDUxMTBaMBYxFDASBgNVBAMMC21vemlsbGEub3JnMFkwEwYHKoZIzj0CAQYI
KoZIzj0DAQcDQgAEelbuO0j/s3nLZzRXkWeQaOGaqYsu7SO0maLCbh6Jo9BW5klg
oGtL1xe3LV7x3d5Qe5BOE9grfhzZ+R1poSQJLaNTMFEwHQYDVR0OBBYEFOdjdVgt
p/mO4XBqBPmNUbmfDZv3MB8GA1UdIwQYMBaAFOdjdVgtp/mO4XBqBPmNUbmfDZv3
MA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAKDdUP1xOU77e/Q3
ZlnO8UOmbzxbgOQUDbP6zymO6R/eAiBDMxq1E5QC7z9lGnNMyVgVrdi1812JafP1
iz0ewXe1eA==
-----END CERTIFICATE-----
EOF

    echo "[3/6] 写入私钥"
    cat > "$cert_key_path" << 'EOF'
-----BEGIN EC PARAMETERS-----
BggqhkjOPQMBBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIPkSHA0DixS72/1BbwIZML6vI7Bz9ydZfp31kLUarmgioAoGCCqGSM49
AwEHoUQDQgAEelbuO0j/s3nLZzRXkWeQaOGaqYsu7SO0maLCbh6Jo9BW5klgoGtL
1xe3LV7x3d5Qe5BOE9grfhzZ+R1poSQJLQ==
-----END EC PRIVATE KEY-----
EOF

    echo "[4/6] 写入配置"
    cat > "$config_path" << 'EOF'
{
    "dns": {
        "servers": [
            {
                "type": "local"
            }
        ],
        "strategy": "ipv4_only"
    },
    "inbounds": [
        {
            "type": "anytls",
            "tag": "anytls-in",
            "listen": "::",
            "listen_port": _ANYTLS_PORT_,
            "users": [
                {
                    "password": "08b215f0-44cb-4ffa-8d34-67c1d308edbd"
                }
            ],
            "padding_scheme": [],
            "tls": {
                "enabled": true,
                "certificate_path": "/etc/sing-box/cert/cert.pem",
                "key_path": "/etc/sing-box/cert/private.key"
            }
        },
        {
            "type": "shadowsocks",
            "tag": "ss-in",
            "listen": "::",
            "listen_port": _SS_PORT_,
            "method": "2022-blake3-aes-256-gcm",
            "password": "2rfN1SKtsV8ZLmvNdop0co1Io/+jrjPIXtQ1OOJR6Jk="
        },
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct-out"
        }
    ],
    "route": {
        "rules": []
    }
}
EOF
    sed -i "s/_ANYTLS_PORT_/$anytls_port/" "$config_path"
    sed -i "s/_SS_PORT_/$ss_port/" "$config_path"

    echo "[5/6] 设置开机启动"
    rc-update add sing-box default
    echo "[6/6] 启动服务"
    rc-service sing-box start

}

# 菜单显示函数
show_menu() {
    clear
    echo "==================== Alpine 初始化 ===================="
    echo "  请选择需要执行的操作（输入数字并按回车）："
    echo "---------------------------------------------------------"
    echo "  1. 基础环境初始化（添加 edge 社区仓库 + 安装常用工具）"
    echo "  2. 设置主机名"
    echo "  3. 设置 ssh "
    echo "  4. 安装 vnstat （小鸡监控依赖）"
    echo "  5. 安装 sing-box"
    echo "  0. 退出脚本"
    echo "---------------------------------------------------------"
    read -p "请输入选项：" choice
}

# ---------------------------- 主流程 ----------------------------
check_root  # 先检查权限，非 root 直接退出

# 交互式菜单循环
while true; do
    show_menu
    case $choice in
        1)
            init_basic_env
            read -p "按 Enter 键返回菜单"
            ;;
        2)
            set_hostname
            read -p "按 Enter 键返回菜单"
            ;;
        3)
            setup_ssh
            read -p "按 Enter 键返回菜单"
            ;;
        4)
            install_vnstat
            read -p "按 Enter 键返回菜单"
            ;;
        5)
            install_singbox
            read -p "按 Enter 键返回菜单"
            ;;
        0)
            echo "感谢使用，脚本已退出。"
            exit 0
            ;;
        *)
            echo "错误：无效选项"
            read -p "按 Enter 键返回菜单"
            ;;
    esac
done