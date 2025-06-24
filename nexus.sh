#!/bin/bash
# 一键安装和管理 Nexus CLI 的脚本

# 设置错误处理
set -e

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查依赖
check_dependencies() {
    # 检查 curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}错误：未找到 curl，请先安装 curl！${NC}"
        exit 1
    fi

    # 检查 Docker
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker 未安装，正在安装 Docker...${NC}"
        sudo apt update
        sudo apt install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Docker 安装并启动成功！${NC}"
        else
            echo -e "${RED}Docker 安装失败，请检查网络或权限！${NC}" >&2
            exit 1
        fi
    else
        echo -e "${GREEN}Docker 已安装，版本：$(docker --version)${NC}"
    fi
}

# 检查是否已安装 Nexus CLI
check_nexus_installed() {
    # 检查 nexus-network 是否在 PATH 或 ~/.nexus/bin 中
    if command -v nexus-network >/dev/null 2>&1 || [ -x ~/.nexus/bin/nexus-network ]; then
        return 0
    else
        return 1
    fi
}

# 检查 Nexus CLI 版本
check_nexus_version() {
    if check_nexus_installed; then
        echo "当前 Nexus CLI 版本："
        # 确保 PATH 包含 ~/.nexus/bin
        export PATH=$PATH:$HOME/.nexus/bin
        nexus-network --version || echo -e "${YELLOW}无法获取版本信息${NC}"
    else
        echo -e "${YELLOW}Nexus CLI 未安装${NC}"
    fi
}

# 检查 Docker 中是否有 Nexus 相关容器
check_docker_conflict() {
    if docker ps -a | grep -q "nexus"; then
        echo -e "${YELLOW}警告：检测到 Nexus 相关的 Docker 容器，可能导致冲突！${NC}"
        read -p "是否停止并删除这些容器？(y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            docker ps -a | grep "nexus" | awk '{print $1}' | xargs -r docker stop
            docker ps -a | grep "nexus" | awk '{print $1}' | xargs -r docker rm
            echo -e "${GREEN}Nexus 相关容器已停止并删除！${NC}"
        else
            echo -e "${YELLOW}已跳过 Docker 容器清理，请确保无冲突！${NC}"
        fi
    fi
}

# 安装 Nexus CLI 并启动节点
install_and_start_nexus() {
    check_dependencies
    check_docker_conflict

    if check_nexus_installed; then
        echo -e "${YELLOW}Nexus CLI 已安装，跳过安装步骤。${NC}"
    else
        echo -e "${YELLOW}注意：即将通过 curl 下载并执行安装脚本，请确保信任来源！${NC}"
        read -p "是否继续安装？(y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "安装已取消。"
            return 0
        fi
        echo "开始安装 Nexus CLI..."
        # 使用 Nexus 官方安装脚本
        curl -s https://cli.nexus.xyz/ | bash -s -- -y

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Nexus CLI 安装成功！${NC}"
            # 确保 PATH 包含 ~/.nexus/bin
            if [ -d "$HOME/.nexus/bin" ] && ! echo $PATH | grep -q "$HOME/.nexus/bin"; then
                export PATH=$PATH:$HOME/.nexus/bin
                case "$SHELL" in
                    */zsh)
                        echo 'export PATH=$PATH:$HOME/.nexus/bin' >> ~/.zshrc
                        echo "已将 PATH 更新写入 ~/.zshrc"
                        echo "请运行以下命令更新 PATH 或重启终端："
                        echo "  source ~/.zshrc"
                        ;;
                    */bash)
                        echo 'export PATH=$PATH:$HOME/.nexus/bin' >> ~/.bashrc
                        echo "已将 PATH 更新写入 ~/.bashrc"
                        echo "请运行以下命令更新 PATH 或重启终端："
                        echo "  source ~/.bashrc"
                        ;;
                    *)
                        echo "请手动将以下内容添加到您的 shell 配置文件："
                        echo "  export PATH=\$PATH:$HOME/.nexus/bin"
                        ;;
                esac
                # 应用当前会话的 PATH
                source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null || true
            fi
        else
            echo -e "${RED}安装失败，请检查网络或脚本权限。${NC}" >&2
            exit 1
        fi
    fi

    # 提示用户输入 node-id 并启动节点
    read -p "请输入您的 node-id: " node_id
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误：node-id 不能为空！${NC}"
        return 1
    fi

    echo "正在启动 Nexus 节点..."
    # 确保 PATH 包含 nexus-network
    export PATH=$PATH:$HOME/.nexus/bin
    if ! command -v nexus-network >/dev/null 2>&1; then
        echo -e "${RED}错误：nexus-network 命令未找到，请检查安装！${NC}"
        return 1
    fi
    # 使用 screen 后台运行节点
    screen -dmS nexus nexus-network start --node-id "$node_id"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}节点已在 screen 会话 'nexus' 中启动！使用 'screen -r nexus' 查看。${NC}"
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
    # 优先尝试 nexus-network logs，如果失败则回退到 tail -f
    export PATH=$PATH:$HOME/.nexus/bin
    nexus-network logs --follow || tail -f ~/nexus.log
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
    # 停止节点和 screen 会话
    screen -S nexus -X quit >/dev/null 2>&1 || true
    nexus-network stop >/dev/null 2>&1 || true
    # 删除 Nexus CLI 二进制文件
    nexus_path=$(command -v nexus-network 2>/dev/null || echo "$HOME/.nexus/bin/nexus-network")
    if [ -f "$nexus_path" ]; then
        rm -f "$nexus_path" 2>/dev/null || true
    fi
    # 删除配置文件和数据目录
    rm -rf ~/.nexus 2>/dev/null || true
    # 清理可能的 Docker 容器
    check_docker_conflict

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
                install_and_start_nexus
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
