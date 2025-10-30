#!/bin/sh

# 权限检查函数
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误：请使用 root 用户执行此脚本（执行命令：su - 切换到 root）" >&2
        exit 1
    fi
}

init_basic_env() {
    echo "===== 基础环境初始化开始 ====="

    if apt update > /dev/null 2>&1; then
        echo "  成功：包索引更新完成"
    else
        echo "  错误：包索引更新失败，请检查网络连接" >&2
        exit 1
    fi

    # 安装指定软件包
    echo "安装 micro 和 btop"
    if apt install -y micro btop > /dev/null 2>&1; then
        echo "  成功：软件包安装完成"
    else
        echo "  错误：软件包安装失败，请检查仓库配置" >&2
        exit 1
    fi
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

install_zsh() {
    apt install -y zsh
    curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
}

install_trzsz() {
    wget -O tcping.tar.gz https://github.com/pouriyajamshidi/tcping/releases/latest/download/tcping-linux-amd64-static.tar.gz
    tar -xvf tcping.tar.gz
    chmod +x tcping
    mv tcping /usr/local/bin/
    rm tcping.tar.gz
}

install_ufw() {
    apt install ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw enable
    ufw allow ssh
    systemctl restart ufw
}

install_docker() {
    curl -fLsS https://get.docker.com/ | sh
}

install_ufw_docker() {
    wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    chmod +x /usr/local/bin/ufw-docker
    ufw-docker install
    systemctl restart ufw
}

# 菜单显示函数
show_menu() {
    clear
    echo "==================== Debian 初始化 ===================="
    echo "  请选择需要执行的操作（输入数字并按回车）："
    echo "---------------------------------------------------------"
    echo "  1. 基础环境初始化（安装常用工具）"
    echo "  2. 设置主机名"
    echo "  3. 设置 ssh "
    echo "  4. 安装 zsh + zim "
    echo "  5. 安装 trzsz "
    echo "  6. 安装 ufw "
    echo "  7. 安装 docker "
    echo "  8. 安装 ufw-docker "
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
            install_zsh
            read -p "按 Enter 键返回菜单"
            ;;
        5)
            install_trzsz
            read -p "按 Enter 键返回菜单"
            ;;
        6)
            install_ufw
            read -p "按 Enter 键返回菜单"
            ;;
        7)
            install_docker
            read -p "按 Enter 键返回菜单"
            ;;
        8)
            install_ufw_docker
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