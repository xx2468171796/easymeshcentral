# MeshCentral 企业级一键部署脚本Docker

## 📋 脚本介绍

这是一个专为 Debian/ubuntu 设计的 MeshCentral 企业级一键Docker部署脚本，提供完整的远程控制服务器解决方案。

### ✨ 主要功能

- **🚀 一键部署** - 自动完成所有安装步骤
- **🔌 端口自定义** - 支持自定义端口映射，解决端口冲突
- **🛡️ 防火墙配置** - 自动配置 UFW 防火墙规则
- **⚡ 性能优化** - 启用 WebRTC、高清画质等优化选项
- **🔐 证书管理** - 智能证书生成和管理
- **🌐 域名配置** - 支持 IP 和域名访问配置
- **🔄 服务管理** - 完整的启动/停止/重启功能

### 🎯 适用场景

- 企业远程桌面管理
- IT 运维团队远程支持
- 教育机构远程教学
- 个人远程设备管理

## 📋 系统要求

- **操作系统**: Debian 12 LTS
- **硬件要求**: 最低 2GB RAM，推荐 4GB+
- **网络要求**: 公网 IP 或内网可访问
- **权限要求**: root 或 sudo 权限

## 🚀 快速开始

### 1. 下载脚本

```bash
wget https://raw.githubusercontent.com/xx2468171796/easymeshcentral/main/easymeshcentral.sh
chmod +x easymeshcentral.sh
./easymeshcentral.sh
```
### 2. 运行安装

```bash
./install_meshcentral.sh
```

### 3. 配置访问地址

- 输入服务器 IP 或域名（如：192.168.1.100 或 mesh.example.com）
- 选择是否使用默认端口
- 等待安装完成

### 4. 访问管理界面

打开浏览器访问：`https://your-ip-or-domain`

## 📝 功能详解

### 端口配置

脚本支持自定义端口映射，避免端口冲突：

- **HTTP 端口**: Web 界面访问（默认 80）
- **HTTPS 端口**: Web 界面安全访问（默认 443）
- **Agent 端口**: 客户端连接端口（默认 4433）
- **WebRTC 端口**: P2P 连接端口（默认 8443）

### 防火墙配置

自动配置 UFW 防火墙规则：
```bash
# 开放必要端口
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 4433/tcp  # Agent
ufw allow 8443/tcp  # WebRTC
```

### 性能优化

启用以下优化选项：
- ✅ WebRTC 支持（P2P 连接）
- ✅ 高清画质（100% 质量）
- ✅ 文件传输支持
- ✅ 终端访问支持
- ✅ 桌面远程控制

## 🔧 管理功能

安装完成后，脚本提供完整的管理菜单：

```
==============================================
       MeshCentral 管理菜单
==============================================
1. 查看详细配置
2. 调整性能设置
3. 修改端口配置
4. 重新部署服务
5. 启动/停止服务
6. 查看日志
7. 更新镜像
8. 修改访问地址
9. 卸载 MeshCentral
0. 退出
```

## 📁 目录结构

```
/opt/meshcentral/
├── docker-compose.yml          # Docker 编排文件
├── .ports_config              # 端口配置文件
├── meshcentral-data/          # 数据目录
│   ├── config.json           # 主配置文件
│   ├── *.pem                 # TLS 证书文件
│   └── agents/               # Agent 数据
└── logs/                     # 日志目录
```

## 🔒 安全特性

- **TLS 加密**: 自动生成 TLS 证书
- **访问控制**: 支持用户权限管理
- **防火墙**: 自动配置安全规则
- **数据隔离**: Docker 容器隔离运行

## 🐛 故障排除

### 常见问题

1. **客户端连接失败**
   - 检查防火墙配置
   - 确认端口映射正确
   - 重新下载 Agent 安装包

2. **Web 界面无法访问**
   - 检查容器状态：`docker ps`
   - 查看容器日志：`docker logs meshcentral`
   - 确认证书配置正确

3. **证书错误**
   - 删除旧证书：`rm -f /opt/meshcentral/meshcentral-data/*.pem`
   - 重新配置访问地址
   - 重启服务

### 日志查看

```bash
# 查看容器日志
docker logs meshcentral --tail 100

# 实时查看日志
docker logs meshcentral -f
```

## 📞 技术支持

- **作者**: 孤独制作
- **电报群**: https://t.me/+RZMe7fnvvUg1OWJl

## 📄 许可证

本脚本遵循 MIT 许可证，可自由使用和修改。

## ⭐ 更新日志

### v2.0.0
- ✨ 新增端口自定义功能
- ✨ 新增智能证书管理
- ✨ 优化安装流程
- 🐛 修复客户端连接问题

### v1.0.0
- 🎉 初始版本发布
- ✅ 基础安装功能
- ✅ 防火墙配置
- ✅ 性能优化

---

**注意**: 使用本脚本前请确保已备份重要数据，作者不对因使用本脚本造成的任何损失负责。
