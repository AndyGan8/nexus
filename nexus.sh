#!/bin/bash

# 一键安装和管理 Nexus CLI 的脚本

# 设置错误处理
set -e

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查依赖
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}错误：未找到 curl，请先安装 curl！${NC}"
        exit 1
    fi
}

# 检查是否已安装 Nexus CLI
check_nexus_installed() {
    if command -v nexus-network >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查 Nexus CLI 版本
check_nexus_version() {
    if check_nexus_installed; then
        echo "当前 Nexus CLI 版本："
        nexus-network --version || echo -e "${YELLOW}无法获取版本信息${NC}"
    else
        echo -e "${YELLOW}Nexus CLI 未安装${NC}"
    fi
}

# 安装 Nexus CLI
install_nexus() {
    check_dependencies
    echo -e "${YELLOW}注意：即将通过 curl 下载并执行安装脚本，请确保信任来源！${NC}"
    read -p "是否继续安装？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "安装已取消。"
        return 0
    fi

    echo "开始安装 Nexus CLI..."
    curl -s https://cli.nexus.xyz/ | sh -s -- -y

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Nexus CLI 安装成功！${NC}"
        # 动态检测 shell 类型并提供合适的 PATH 更新提示
        case "$SHELL" in
            */zsh)
                echo "请运行以下命令更新 PATH 或重启终端："
                echo "  source ~/.zshrc"
                ;;
            */bash)
                echo "请运行以下命令更新 PATH 或重启终端："
                echo "  source ~/.bashrc"
                ;;
            *)
                echo "请手动更新 PATH 或重启终端："
                echo "  export PATH=\$PATH:/usr/local/bin"
                ;;
        esac
    else
        echo -e "${RED}安装失败，请检查网络或脚本权限。${NC}" >&2
        exit 1
    fi
}

# 启动节点
start_node() {
    if ! check_nexus_installed; then
        echo -e "${RED}Nexus CLI 未安装，请先选择安装！${NC}"
        return 1
    fi

    read -p "请输入您的 node-id: " node_id
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误：node-id 不能为空！${NC}"
        return 1
    fi

    echo "正在启动 Nexus 节点..."
    nexus-network start --node-id "$node_id"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}节点启动成功！${NC}"
    else
        echo -e "${RED}节点启动失败，请检查 node-id 或网络连接。${NC}"
        return 1
    fi
}

# 查看日志
view_logs() {
    if ! check_nexus_installed; then
        echo -e "${RED}Nexus CLI 未安装，请先选择安装！${NC}"
        return 1
    fi

    echo "正在查看 Nexus 节点日志..."
    echo -e "${YELLOW}提示：按 Ctrl+C 退出日志查看${NC}"
    nexus-network logs --follow
}

# 删除会话和节点
remove_node() {
    if ! check_nexus_installed; then
        echo -e "${RED}Nexus CLI 未安装，无需删除！${NC}"
        return 0
    fi

    read -p "确定要删除 Nexus CLI 和相关会话数据吗？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "操作已取消。"
        return 0
    fi

    echo "正在删除 Nexus CLI 和会话数据..."
    # 停止节点
    nexus-network stop >/dev/null 2>&1 || true
    # 动态查找 Nexus CLI 二进制文件
    nexus_path=$(command -v nexus-network 2>/dev/null || echo "")
    if [ -n "$nexus_path" ]; then
        rm -f "$nexus_path" 2>/dev/null || true
    fi
    # 删除可能的配置文件和数据目录
    rm -rf ~/.nexus 2>/dev/null || true

    echo -e "${GREEN}Nexus CLI 和会话数据已删除！${NC}"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n=== Nexus CLI 管理脚本 ==="
        echo "1. 安装 Nexus CLI 并启动节点"
        echo "2. 查看节点日志"
        echo "3. 删除会话和节点"
        echo "4. 检查 Nexus CLI 版本"
        echo "5. 退出"
        read -p "请选择操作 (1-5): " choice

        case $choice in
            1)
                install_nexus
                start_node
                read -p "按 Enter 键返回菜单..."
                ;;
            2)
                view_logs
                ;;
            3)
                remove_node
                read -p "按 Enter 键返回菜单..."
                ;;
            4)
                check_nexus_version
                read -p "按 Enter 键返回菜单..."
                ;;
            5)
                echo "退出脚本..."
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请输入 1-5！${NC}"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 检查依赖并运行主菜单
check_dependencies
main_menu
