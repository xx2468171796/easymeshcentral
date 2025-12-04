#!/bin/bash

# ===============================================
# MeshCentral 一键部署与管理脚本
# 适用系统：Debian 12 LTS
# 功能：安装/管理/卸载 MeshCentral
# ===============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="/opt/meshcentral"
CONTAINER_NAME="meshcentral"
CONFIG_FILE="$INSTALL_DIR/meshcentral-data/config.json"
PORTS_FILE="$INSTALL_DIR/.ports_config"

# 默认端口
DEFAULT_HTTP_PORT=80
DEFAULT_HTTPS_PORT=443
DEFAULT_AGENT_PORT=4433
DEFAULT_WEBRTC_PORT=8443

# 当前端口配置
HTTP_PORT=$DEFAULT_HTTP_PORT
HTTPS_PORT=$DEFAULT_HTTPS_PORT
AGENT_PORT=$DEFAULT_AGENT_PORT
WEBRTC_PORT=$DEFAULT_WEBRTC_PORT

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# 加载端口配置
load_ports_config() {
    if [ -f "$PORTS_FILE" ]; then
        source "$PORTS_FILE"
    fi
}

# 保存端口配置
save_ports_config() {
    # 确保目录存在
    mkdir -p "$INSTALL_DIR"
    
    cat > "$PORTS_FILE" << EOF
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
AGENT_PORT=$AGENT_PORT
WEBRTC_PORT=$WEBRTC_PORT
EOF
}

# 检测 MeshCentral 是否已安装
check_installed() {
    if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            return 0  # 已安装
        fi
    fi
    return 1  # 未安装
}

# 检测容器是否运行中
check_running() {
    if docker ps | grep -q "$CONTAINER_NAME"; then
        return 0  # 运行中
    fi
    return 1  # 未运行
}

# 获取服务器 IP
get_server_ip() {
    local public_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")
    local private_ip=$(hostname -I | awk '{print $1}')
    
    if [ -n "$public_ip" ]; then
        echo "$public_ip"
    else
        echo "$private_ip"
    fi
}

# 获取配置的域名
get_configured_domain() {
    if [ -f "$INSTALL_DIR/.configured_domain" ]; then
        cat "$INSTALL_DIR/.configured_domain"
    else
        get_server_ip
    fi
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本，例如：sudo bash $0"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    print_info "检查系统环境..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "debian" ]]; then
            print_warning "当前系统不是 Debian，可能存在兼容性问题"
            read -p "是否继续? (y/n): " continue_install
            if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
                exit 1
            fi
        fi
        if [[ "$VERSION_ID" != "12" ]]; then
            print_warning "当前系统不是 Debian 12，版本：$VERSION_ID"
            read -p "是否继续? (y/n): " continue_install
            if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
                exit 1
            fi
        fi
    else
        print_warning "无法检测系统版本"
        read -p "是否继续? (y/n): " continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            exit 1
        fi
    fi
    
    print_success "系统检查完成"
}

# 安装基础依赖
install_dependencies() {
    print_info "安装基础依赖 (curl, tar, ufw)..."
    
    apt-get update -y
    apt-get install -y curl tar ufw ca-certificates gnupg lsb-release
    
    print_success "基础依赖安装完成"
}

# 检查端口是否被占用
check_ports() {
    load_ports_config
    print_info "检查端口占用情况..."
    
    local ports=($HTTP_PORT $HTTPS_PORT $AGENT_PORT $WEBRTC_PORT)
    local occupied=()
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            occupied+=($port)
        fi
    done
    
    if [ ${#occupied[@]} -gt 0 ]; then
        print_warning "以下端口已被占用: ${occupied[*]}"
        print_warning "MeshCentral 需要使用端口 $HTTP_PORT, $HTTPS_PORT, $AGENT_PORT, $WEBRTC_PORT"
        read -p "是否继续? (y/n): " continue_install
        if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
            exit 1
        fi
    else
        print_success "端口检查通过，$HTTP_PORT, $HTTPS_PORT, $AGENT_PORT, $WEBRTC_PORT 均可用"
    fi
}

# 安装 Docker
install_docker() {
    print_info "检查 Docker 安装状态..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装: $(docker --version)"
    else
        print_info "开始安装 Docker..."
        
        # 移除旧版本
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # 添加 Docker 官方 GPG 密钥
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        # 添加 Docker 仓库
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # 安装 Docker
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # 启动 Docker 服务
        systemctl start docker
        systemctl enable docker
        
        if command -v docker &> /dev/null; then
            print_success "Docker 安装成功: $(docker --version)"
        else
            print_error "Docker 安装失败，请手动检查"
            exit 1
        fi
    fi
}

# 检查 Docker Compose
check_docker_compose() {
    print_info "检查 Docker Compose..."
    
    if docker compose version &> /dev/null; then
        print_success "Docker Compose 可用: $(docker compose version)"
    else
        print_error "Docker Compose 未找到，请确保已安装 docker-compose-plugin"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    print_info "创建 MeshCentral 目录结构..."
    
    mkdir -p "$INSTALL_DIR/meshcentral-data"
    mkdir -p "$INSTALL_DIR/meshcentral-files"
    mkdir -p "$INSTALL_DIR/meshcentral-backups"
    mkdir -p "$INSTALL_DIR/meshcentral-web"
    
    # 设置目录权限
    chmod -R 755 "$INSTALL_DIR"
    
    print_success "目录创建完成: $INSTALL_DIR"
}

# 配置防火墙
configure_firewall() {
    load_ports_config
    print_info "是否配置防火墙 (ufw) 开放端口 $HTTP_PORT, $HTTPS_PORT, $AGENT_PORT, $WEBRTC_PORT?"
    read -p "(y/n): " configure_ufw
    
    if [[ "$configure_ufw" == "y" || "$configure_ufw" == "Y" ]]; then
        print_info "配置防火墙规则..."
        
        ufw allow $HTTP_PORT/tcp
        ufw allow $HTTPS_PORT/tcp
        ufw allow $AGENT_PORT/tcp
        ufw allow $WEBRTC_PORT/tcp
        
        # 确保 SSH 端口开放，避免被锁在外面
        ufw allow 22/tcp
        
        # 启用防火墙（如果未启用）
        if ! ufw status | grep -q "Status: active"; then
            print_warning "防火墙当前未启用"
            read -p "是否启用防火墙? (y/n): " enable_ufw
            if [[ "$enable_ufw" == "y" || "$enable_ufw" == "Y" ]]; then
                ufw --force enable
                print_success "防火墙已启用"
            fi
        fi
        
        print_success "防火墙规则配置完成"
        ufw status
    else
        print_info "跳过防火墙配置"
    fi
}

# 配置 MeshCentral 访问地址
configure_meshcentral_domain() {
    print_info "配置 MeshCentral 访问地址 (必需步骤)"
    echo "此配置用于解决 'Invalid origin in HTTP request' 问题"
    echo "请输入您的服务器 IP 地址或域名"
    echo ""
    
    # 自动获取服务器 IP 作为默认值
    local default_ip=$(get_server_ip)
    
    while true; do
        echo "请输入访问地址 (例如: $default_ip 或 mesh.example.com):"
        read -p "访问地址 [$default_ip]: " custom_domain
        
        if [ -z "$custom_domain" ]; then
            custom_domain="$default_ip"
        fi
        
        if [ -n "$custom_domain" ]; then
            print_info "配置访问地址为: $custom_domain"
            break
        else
            print_error "访问地址不能为空，请重新输入"
        fi
    done
    
    # 等待容器首次启动生成配置文件
    print_info "等待 MeshCentral 首次启动生成配置文件..."
    sleep 15
    
    local config_file="$INSTALL_DIR/meshcentral-data/config.json"
    
    # 删除旧证书（避免证书名称不匹配问题）
    print_info "清理旧证书（如果存在）以确保证书与新地址匹配..."
    rm -f "$INSTALL_DIR/meshcentral-data/"*.pem 2>/dev/null
    rm -f "$INSTALL_DIR/meshcentral-data/"*.key 2>/dev/null  
    rm -f "$INSTALL_DIR/meshcentral-data/"*.crt 2>/dev/null
    rm -rf "$INSTALL_DIR/meshcentral-data/agents/" 2>/dev/null
    
    # 加载端口配置
    load_ports_config
    
    if [ ! -f "$config_file" ]; then
        print_warning "配置文件未找到，创建默认配置..."
        
        # 只有非默认端口时才添加 aliasPort
        local alias_config=""
        if [ "$HTTPS_PORT" != "443" ]; then
            alias_config="\"aliasPort\": $HTTPS_PORT,"
        fi
        if [ "$AGENT_PORT" != "4433" ]; then
            alias_config="$alias_config
    \"agentAliasPort\": $AGENT_PORT,"
        fi
        
        cat > "$config_file" << EOF
{
  "settings": {
    "cert": "$custom_domain",
    "port": 443,
    "redirPort": 80,
    $alias_config
    "allownewtokens": true,
    "_redirhost": "$custom_domain",
    "WebRTC": {
      "enabled": true
    },
    "domains": {
      "": {
        "title": "MeshCentral",
        "DesktopQuality": 100,
        "DesktopDownscale": false,
        "MaxDesktopResolution": 0
      }
    }
  }
}
EOF
    fi
    
    # 备份原配置
    cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 更新配置文件
    if command -v python3 &> /dev/null; then
        python3 << EOF
import json
import sys

config_file = "$config_file"
custom_domain = "$custom_domain"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # 确保 settings 存在
    if 'settings' not in config:
        config['settings'] = {}
    
    # 设置证书和允许的域名/IP
    config['settings']['cert'] = custom_domain
    config['settings']['port'] = 443
    config['settings']['redirPort'] = 80
    
    # 只有非默认端口时才添加 aliasPort
    if $HTTPS_PORT != 443:
        config['settings']['aliasPort'] = $HTTPS_PORT
    elif 'aliasPort' in config['settings']:
        del config['settings']['aliasPort']
        
    if $AGENT_PORT != 4433:
        config['settings']['agentAliasPort'] = $AGENT_PORT
    elif 'agentAliasPort' in config['settings']:
        del config['settings']['agentAliasPort']
    
    config['settings']['allownewtokens'] = True
    config['settings']['_redirhost'] = custom_domain
    
    # 启用 WebRTC - 检查是否已存在
    if 'WebRTC' not in config['settings']:
        config['settings']['WebRTC'] = {}
    elif isinstance(config['settings']['WebRTC'], bool):
        # 如果 WebRTC 是布尔值，转换为字典
        config['settings']['WebRTC'] = {'enabled': config['settings']['WebRTC']}
    
    config['settings']['WebRTC']['enabled'] = True
    
    # 配置域名优化参数 (domains 是对象，空字符串 "" 为默认域)
    if 'domains' not in config['settings']:
        config['settings']['domains'] = {}
    
    # 如果 domains 是列表（旧格式），转换为对象
    if isinstance(config['settings']['domains'], list):
        config['settings']['domains'] = {}
    
    # 确保默认域存在
    if '' not in config['settings']['domains']:
        config['settings']['domains'][''] = {}
    
    # 设置默认域的参数
    domain = config['settings']['domains']['']
    domain['title'] = "MeshCentral"
    domain['DesktopQuality'] = 100
    domain['DesktopDownscale'] = False
    domain['MaxDesktopResolution'] = 0
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("配置更新成功")
except Exception as e:
    print(f"配置更新失败: {e}")
    # 如果 Python 更新失败，创建一个新的配置文件
    print("尝试创建新的配置文件...")
    new_config = {
        "settings": {
            "cert": custom_domain,
            "port": 443,
            "redirPort": 80,
            "allownewtokens": True,
            "_redirhost": custom_domain,
            "WebRTC": {
                "enabled": True
            },
            "domains": {
                "": {
                    "title": "MeshCentral",
                    "DesktopQuality": 100,
                    "DesktopDownscale": False,
                    "MaxDesktopResolution": 0
                }
            }
        }
    }
    
    with open(config_file, 'w') as f:
        json.dump(new_config, f, indent=2)
    
    print("新配置文件创建成功")
EOF
    else
        print_warning "Python3 不可用，使用手动配置方式"
        # 手动添加配置
        sed -i "s/\"allownewtokens\": false/\"allownewtokens\": true/g" "$config_file" 2>/dev/null || true
        sed -i "s/\"_redirhost\": \"\"/\"_redirhost\": \"$custom_domain\"/g" "$config_file" 2>/dev/null || true
    fi
    
    print_success "访问地址配置完成: $custom_domain"
    print_info "删除现有容器并重新部署..."
    
    # 删除现有容器
    cd "$INSTALL_DIR"
    docker compose down
    
    # 重新启动容器
    docker compose up -d
    
    print_info "等待服务重新启动 (约 30 秒)..."
    sleep 30
    
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_success "MeshCentral 已重新部署，访问地址: https://$custom_domain/"
        # 保存配置的域名到文件，供后续使用
        echo "$custom_domain" > "$INSTALL_DIR/.configured_domain"
    else
        print_error "MeshCentral 重新部署失败"
    fi
}

# 配置 MeshCentral 性能优化
configure_meshcentral_optimization() {
    print_info "是否启用额外的 MeshCentral 性能优化?"
    echo "注意: 基础 WebRTC 和高清画质已在域名配置中启用"
    echo "额外优化包括:"
    echo "- 更激进的性能参数"
    echo "- 连接池优化"
    read -p "(y/n): " enable_optimization
    
    if [[ "$enable_optimization" == "y" || "$enable_optimization" == "Y" ]]; then
        print_info "应用额外性能优化..."
        
        local config_file="$INSTALL_DIR/meshcentral-data/config.json"
        
        if [ ! -f "$config_file" ]; then
            print_warning "配置文件未找到，跳过性能优化"
            return
        fi
        
        # 备份原配置
        cp "$config_file" "$config_file.optimization_backup.$(date +%Y%m%d_%H%M%S)"
        
        # 使用 Python 处理 JSON 配置
        if command -v python3 &> /dev/null; then
            python3 << EOF
import json

config_file = "$config_file"
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # 确保 settings 存在
    if 'settings' not in config:
        config['settings'] = {}
    
    # 额外的性能优化参数
    config['settings']['maxoldcons'] = 100
    config['settings']['maxoldgroups'] = 100
    config['settings']['sessionkey'] = "MySessionKey"
    config['settings']['allowaccountcreation'] = True
    config['settings']['allownewtokens'] = True
    
    # 优化 WebRTC 配置
    if 'WebRTC' not in config['settings']:
        config['settings']['WebRTC'] = {}
    elif isinstance(config['settings']['WebRTC'], bool):
        config['settings']['WebRTC'] = {'enabled': config['settings']['WebRTC']}
    
    config['settings']['WebRTC']['enabled'] = True
    config['settings']['WebRTC']['iceServers'] = [
        {'urls': 'stun:stun.l.google.com:19302'}
    ]
    
    # 优化域名配置 (domains 是对象格式)
    if 'domains' not in config['settings'] or isinstance(config['settings']['domains'], list):
        config['settings']['domains'] = {}
    
    if '' not in config['settings']['domains']:
        config['settings']['domains'][''] = {}
    
    domain = config['settings']['domains']['']
    domain['DesktopQuality'] = 100
    domain['DesktopDownscale'] = False
    domain['MaxDesktopResolution'] = 0
    domain['MaxFileTransferSize'] = 0
    domain['AllowFileTransfer'] = True
    domain['AllowTerminal'] = True
    domain['AllowDesktop'] = True
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("额外性能优化配置成功")
except Exception as e:
    print(f"性能优化配置失败: {e}")
EOF
        else
            print_warning "Python3 不可用，跳过额外性能优化"
        fi
        
        print_success "额外性能优化配置已应用"
        print_info "重启 MeshCentral 以应用新配置..."
        docker restart meshcentral
        
        print_info "等待服务重启 (约 20 秒)..."
        sleep 20
        
        if docker ps | grep -q "$CONTAINER_NAME"; then
            print_success "MeshCentral 已重启并启用额外性能优化"
        else
            print_error "MeshCentral 重启失败"
        fi
    else
        print_info "跳过额外性能优化配置"
    fi
}

# 启动服务
start_services() {
    print_info "拉取 MeshCentral 镜像..."
    
    cd "$INSTALL_DIR"
    docker compose pull
    
    print_info "启动 MeshCentral 服务..."
    docker compose up -d
    
    # 等待服务启动
    print_info "等待服务启动 (约 30 秒)..."
    sleep 30
    
    # 检查容器状态
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_success "MeshCentral 容器已成功启动"
    else
        print_error "MeshCentral 容器启动失败，请检查日志: docker compose logs -f"
        exit 1
    fi
}

# 显示详细配置信息
show_config_info() {
    load_ports_config
    local configured_domain=$(get_configured_domain)
    local container_status="未运行"
    
    if check_running; then
        container_status="${GREEN}运行中${NC}"
    else
        container_status="${RED}已停止${NC}"
    fi
    
    echo ""
    print_header "=============================================="
    print_header "       MeshCentral 详细配置信息"
    print_header "=============================================="
    echo ""
    echo -e "【运行状态】"
    echo -e "容器状态:       $container_status"
    echo -e "容器名称:       $CONTAINER_NAME"
    echo ""
    echo -e "【访问地址】"
    echo -e "HTTPS 地址:     ${BLUE}https://$configured_domain:$HTTPS_PORT/${NC}"
    echo -e "HTTP 地址:      ${BLUE}http://$configured_domain:$HTTP_PORT/${NC}"
    echo ""
    echo -e "【端口配置】"
    echo -e "HTTP 端口:      $HTTP_PORT (默认: 80)"
    echo -e "HTTPS 端口:     $HTTPS_PORT (默认: 443)"
    echo -e "Agent 端口:     $AGENT_PORT (默认: 4433)"
    echo -e "WebRTC 端口:    $WEBRTC_PORT (默认: 8443)"
    echo ""
    echo -e "【目录配置】"
    echo -e "安装目录:       $INSTALL_DIR/"
    echo -e "数据目录:       $INSTALL_DIR/meshcentral-data/"
    echo -e "文件目录:       $INSTALL_DIR/meshcentral-files/"
    echo -e "备份目录:       $INSTALL_DIR/meshcentral-backups/"
    echo -e "配置文件:       $CONFIG_FILE"
    echo ""
    echo -e "【管理员账户】"
    echo -e "${YELLOW}提示: 首次访问 https://$configured_domain:$HTTPS_PORT/ 时需注册管理员账户${NC}"
    echo -e "${YELLOW}      注册的第一个账户将自动成为管理员${NC}"
    echo ""
    echo -e "【常用命令】"
    echo "查看日志:       cd $INSTALL_DIR && docker compose logs -f"
    echo "重启服务:       cd $INSTALL_DIR && docker compose restart"
    echo "停止服务:       cd $INSTALL_DIR && docker compose down"
    echo "启动服务:       cd $INSTALL_DIR && docker compose up -d"
    echo "更新镜像:       cd $INSTALL_DIR && docker compose pull && docker compose up -d"
    echo ""
    print_header "=============================================="
}

# 配置端口
configure_ports() {
    echo ""
    print_header "=============================================="
    print_header "          配置端口映射"
    print_header "=============================================="
    echo ""
    
    load_ports_config
    
    echo "当前端口配置:"
    echo "  HTTP 端口:    $HTTP_PORT"
    echo "  HTTPS 端口:   $HTTPS_PORT"
    echo "  Agent 端口:   $AGENT_PORT"
    echo "  WebRTC 端口:  $WEBRTC_PORT"
    echo ""
    echo "直接回车保持当前值不变"
    echo ""
    
    read -p "HTTP 端口 [$HTTP_PORT]: " new_http
    [ -n "$new_http" ] && HTTP_PORT=$new_http
    
    read -p "HTTPS 端口 [$HTTPS_PORT]: " new_https
    [ -n "$new_https" ] && HTTPS_PORT=$new_https
    
    read -p "Agent 端口 [$AGENT_PORT]: " new_agent
    [ -n "$new_agent" ] && AGENT_PORT=$new_agent
    
    read -p "WebRTC 端口 [$WEBRTC_PORT]: " new_webrtc
    [ -n "$new_webrtc" ] && WEBRTC_PORT=$new_webrtc
    
    save_ports_config
    
    print_success "端口配置已保存"
    echo ""
    echo "新端口配置:"
    echo "  HTTP 端口:    $HTTP_PORT"
    echo "  HTTPS 端口:   $HTTPS_PORT"
    echo "  Agent 端口:   $AGENT_PORT"
    echo "  WebRTC 端口:  $WEBRTC_PORT"
    
    # 只有在已安装的情况下才更新配置并重新部署
    if [ -f "$CONFIG_FILE" ]; then
        print_info "更新 config.json 中的端口配置..."
        if command -v python3 &> /dev/null; then
            python3 << EOF
import json

config_file = "$CONFIG_FILE"
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    if 'settings' not in config:
        config['settings'] = {}
    
    # 只有非默认端口时才添加 aliasPort，否则删除
    if $HTTPS_PORT != 443:
        config['settings']['aliasPort'] = $HTTPS_PORT
    elif 'aliasPort' in config['settings']:
        del config['settings']['aliasPort']
        
    if $AGENT_PORT != 4433:
        config['settings']['agentAliasPort'] = $AGENT_PORT
    elif 'agentAliasPort' in config['settings']:
        del config['settings']['agentAliasPort']
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("端口配置已更新")
except Exception as e:
    print(f"更新失败: {e}")
EOF
        fi
        
        echo ""
        print_warning "端口修改后需要重新部署并重新下载 Agent 安装程序"
        read -p "是否立即重新部署? (y/n): " do_redeploy
        if [[ "$do_redeploy" == "y" || "$do_redeploy" == "Y" ]]; then
            redeploy_service
        fi
    fi
}

# 生成带自定义端口的 docker-compose.yml
generate_docker_compose_with_ports() {
    load_ports_config
    
    print_info "生成 docker-compose.yml 配置文件..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  meshcentral:
    image: ghcr.io/ylianst/meshcentral:latest
    container_name: meshcentral
    restart: always
    ports:
      - "$HTTP_PORT:80"
      - "$HTTPS_PORT:443"
      - "$AGENT_PORT:4433"
      - "$WEBRTC_PORT:8443"
    environment:
      - TZ=Asia/Shanghai
      - NODE_ENV=production
    volumes:
      - ./meshcentral-data:/opt/meshcentral/meshcentral-data
      - ./meshcentral-files:/opt/meshcentral/meshcentral-files
      - ./meshcentral-backups:/opt/meshcentral/meshcentral-backups
      - ./meshcentral-web:/opt/meshcentral/meshcentral-web
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    
    print_success "docker-compose.yml 生成完成"
}

# 重新部署（更新端口后使用）
redeploy_service() {
    print_info "重新部署 MeshCentral..."
    
    cd "$INSTALL_DIR"
    
    # 停止现有容器
    docker compose down
    
    # 重新生成配置
    generate_docker_compose_with_ports
    
    # 拉取最新镜像并启动
    docker compose pull
    docker compose up -d
    
    print_info "等待服务启动 (约 30 秒)..."
    sleep 30
    
    if check_running; then
        print_success "MeshCentral 已重新部署"
    else
        print_error "MeshCentral 重新部署失败"
    fi
}

# 卸载 MeshCentral
uninstall_meshcentral() {
    echo ""
    print_header "=============================================="
    print_header "          卸载 MeshCentral"
    print_header "=============================================="
    echo ""
    
    print_warning "此操作将删除 MeshCentral 容器和所有数据！"
    echo ""
    read -p "确认卸载? (输入 'yes' 确认): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "卸载已取消"
        return
    fi
    
    print_info "停止并删除容器..."
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
    
    read -p "是否删除所有数据文件? (y/n): " delete_data
    if [[ "$delete_data" == "y" || "$delete_data" == "Y" ]]; then
        print_info "删除数据目录..."
        rm -rf "$INSTALL_DIR"
        print_success "所有数据已删除"
    else
        print_info "保留数据目录: $INSTALL_DIR"
    fi
    
    print_success "MeshCentral 已卸载"
}

# 调整性能配置
adjust_performance() {
    echo ""
    print_header "=============================================="
    print_header "          调整性能配置"
    print_header "=============================================="
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        return
    fi
    
    echo "可调整的性能选项:"
    echo "1. WebRTC 开启/关闭"
    echo "2. 画质设置 (1-100)"
    echo "3. 分辨率降级开关"
    echo "4. 应用全部推荐优化"
    echo "0. 返回"
    echo ""
    
    read -p "请选择: " perf_choice
    
    case $perf_choice in
        1)
            read -p "启用 WebRTC? (y/n): " enable_webrtc
            local webrtc_val="true"
            [[ "$enable_webrtc" != "y" && "$enable_webrtc" != "Y" ]] && webrtc_val="false"
            
            python3 << EOF
import json
config_file = "$CONFIG_FILE"
with open(config_file, 'r') as f:
    config = json.load(f)
if 'settings' not in config:
    config['settings'] = {}
config['settings']['WebRTC'] = {'enabled': $webrtc_val}
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print("WebRTC 配置已更新")
EOF
            ;;
        2)
            read -p "画质 (1-100, 推荐100): " quality
            [ -z "$quality" ] && quality=100
            
            python3 << EOF
import json
config_file = "$CONFIG_FILE"
with open(config_file, 'r') as f:
    config = json.load(f)
if 'settings' not in config:
    config['settings'] = {}
if 'domains' not in config['settings'] or isinstance(config['settings']['domains'], list):
    config['settings']['domains'] = {}
if '' not in config['settings']['domains']:
    config['settings']['domains'][''] = {}
config['settings']['domains']['']['DesktopQuality'] = $quality
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print("画质配置已更新")
EOF
            ;;
        3)
            read -p "禁用分辨率降级? (y/n): " disable_downscale
            local downscale_val="false"
            [[ "$disable_downscale" != "y" && "$disable_downscale" != "Y" ]] && downscale_val="true"
            
            python3 << EOF
import json
config_file = "$CONFIG_FILE"
with open(config_file, 'r') as f:
    config = json.load(f)
if 'settings' not in config:
    config['settings'] = {}
if 'domains' not in config['settings'] or isinstance(config['settings']['domains'], list):
    config['settings']['domains'] = {}
if '' not in config['settings']['domains']:
    config['settings']['domains'][''] = {}
config['settings']['domains']['']['DesktopDownscale'] = $downscale_val
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print("分辨率降级配置已更新")
EOF
            ;;
        4)
            print_info "应用全部推荐优化..."
            python3 << EOF
import json
config_file = "$CONFIG_FILE"
with open(config_file, 'r') as f:
    config = json.load(f)
if 'settings' not in config:
    config['settings'] = {}
config['settings']['WebRTC'] = {'enabled': True}
config['settings']['allownewtokens'] = True
if 'domains' not in config['settings'] or isinstance(config['settings']['domains'], list):
    config['settings']['domains'] = {}
if '' not in config['settings']['domains']:
    config['settings']['domains'][''] = {}
domain = config['settings']['domains']['']
domain['DesktopQuality'] = 100
domain['DesktopDownscale'] = False
domain['MaxDesktopResolution'] = 0
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print("全部推荐优化已应用")
EOF
            ;;
        0)
            return
            ;;
        *)
            print_error "无效选项"
            return
            ;;
    esac
    
    print_info "重启服务以应用配置..."
    docker restart $CONTAINER_NAME
    print_success "配置已更新并重启服务"
}

# 显示管理菜单
show_management_menu() {
    while true; do
        echo ""
        print_header "=============================================="
        print_header "       MeshCentral 管理菜单"
        print_header "=============================================="
        echo ""
        echo "1. 查看详细配置"
        echo "2. 调整性能设置"
        echo "3. 修改端口配置"
        echo "4. 重新部署服务"
        echo "5. 启动/停止服务"
        echo "6. 查看日志"
        echo "7. 更新镜像"
        echo "8. 修改访问地址"
        echo "9. 卸载 MeshCentral"
        echo "0. 退出"
        echo ""
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                show_config_info
                ;;
            2)
                adjust_performance
                ;;
            3)
                configure_ports
                read -p "是否立即应用新端口配置? (y/n): " apply_now
                if [[ "$apply_now" == "y" || "$apply_now" == "Y" ]]; then
                    redeploy_service
                fi
                ;;
            4)
                redeploy_service
                ;;
            5)
                if check_running; then
                    read -p "服务运行中，是否停止? (y/n): " stop_svc
                    if [[ "$stop_svc" == "y" || "$stop_svc" == "Y" ]]; then
                        cd "$INSTALL_DIR" && docker compose down
                        print_success "服务已停止"
                    fi
                else
                    read -p "服务已停止，是否启动? (y/n): " start_svc
                    if [[ "$start_svc" == "y" || "$start_svc" == "Y" ]]; then
                        cd "$INSTALL_DIR" && docker compose up -d
                        print_success "服务已启动"
                    fi
                fi
                ;;
            6)
                print_info "按 Ctrl+C 退出日志查看"
                sleep 2
                cd "$INSTALL_DIR" && docker compose logs -f --tail=100
                ;;
            7)
                print_info "更新镜像..."
                cd "$INSTALL_DIR"
                docker compose pull
                docker compose up -d
                print_success "镜像已更新"
                ;;
            8)
                configure_meshcentral_domain
                ;;
            9)
                uninstall_meshcentral
                if [ ! -d "$INSTALL_DIR" ]; then
                    exit 0
                fi
                ;;
            0)
                print_info "退出管理菜单"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择"
                ;;
        esac
    done
}

# 新安装流程
do_fresh_install() {
    echo ""
    print_header "=============================================="
    print_header "       MeshCentral 新安装"
    print_header "=============================================="
    echo ""
    
    # 配置端口
    echo "【步骤 1/6】配置端口映射"
    echo ""
    echo "默认端口配置:"
    echo "  HTTP:    80"
    echo "  HTTPS:   443"
    echo "  Agent:   4433"
    echo "  WebRTC:  8443"
    echo ""
    read -p "是否使用默认端口? (y/n): " use_default_ports
    
    if [[ "$use_default_ports" != "y" && "$use_default_ports" != "Y" ]]; then
        configure_ports
    else
        save_ports_config
    fi
    
    echo ""
    
    # 执行安装步骤
    print_info "【步骤 2/6】检查系统环境..."
    check_system
    install_dependencies
    
    print_info "【步骤 3/6】安装 Docker..."
    install_docker
    check_docker_compose
    
    print_info "【步骤 4/6】创建目录结构..."
    create_directories
    generate_docker_compose_with_ports
    
    print_info "【步骤 5/6】配置防火墙..."
    configure_firewall
    
    print_info "【步骤 6/6】启动服务..."
    start_services
    
    # 配置域名
    configure_meshcentral_domain
    
    # 可选性能优化
    configure_meshcentral_optimization
    
    # 显示配置信息
    show_config_info
    
    print_success "MeshCentral 安装完成！"
}

# 主函数
main() {
    check_root
    load_ports_config
    
    echo ""
    print_header "=============================================="
    print_header "   MeshCentral 一键部署与管理脚本"
    print_header "   适用系统: Debian 12 LTS"
    print_header "=============================================="
    echo ""
    
    # 检测是否已安装
    if check_installed; then
        print_success "检测到 MeshCentral 已安装"
        echo ""
        
        # 直接显示详细配置
        show_config_info
        
        # 进入管理菜单
        show_management_menu
    else
        print_info "未检测到 MeshCentral 安装"
        echo ""
        read -p "是否开始安装 MeshCentral? (y/n): " start_install
        
        if [[ "$start_install" != "y" && "$start_install" != "Y" ]]; then
            print_info "安装已取消"
            exit 0
        fi
        
        do_fresh_install
    fi
}

# 执行主函数
main
