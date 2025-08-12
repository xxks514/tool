#!/bin/bash

# Hysteria 2 一键安装脚本 (含配置分享链接)
# GitHub: https://github.com/apernet/hysteria

CONFIG_PATH="/etc/hysteria"
SERVICE_PATH="/etc/systemd/system"
HYSTERIA_BIN="/usr/local/bin/hysteria"

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本"
  exit 1
fi

# 检查操作系统
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  OS=$ID
else
  echo "不支持的操作系统"
  exit 1
fi

# 安装依赖
install_deps() {
  case $OS in
    "ubuntu" | "debian")
      apt update -y
      apt install -y wget openssl jq
      ;;
    "centos" | "fedora" | "rhel")
      yum install -y wget openssl jq
      ;;
    *)
      echo "不支持的 Linux 发行版: $OS"
      exit 1
      ;;
  esac
}

# 下载 Hysteria
install_hysteria() {
  LATEST_RELEASE=$(wget -qO- "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  ARCH=$(uname -m)
  
  case $ARCH in
    "x86_64")
      ARCH="amd64"
      ;;
    "aarch64")
      ARCH="arm64"
      ;;
    "armv7l")
      ARCH="arm"
      ;;
    *)
      echo "不支持的架构: $ARCH"
      exit 1
      ;;
  esac

  DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/$LATEST_RELEASE/hysteria-linux-$ARCH"
  
  echo "正在下载 Hysteria $LATEST_RELEASE ..."
  wget -q -O $HYSTERIA_BIN $DOWNLOAD_URL
  chmod +x $HYSTERIA_BIN
}

# 生成自签名证书
generate_cert() {
  mkdir -p $CONFIG_PATH
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout $CONFIG_PATH/key.pem -out $CONFIG_PATH/cert.pem \
    -subj "/CN=bing.com" -days 36500
}

# 创建配置文件
create_config() {
  cat > $CONFIG_PATH/config.yaml <<EOF
listen: :${PORT:-443}
tls:
  cert: $CONFIG_PATH/cert.pem
  key: $CONFIG_PATH/key.pem
auth:
  type: password
  password: ${PASSWORD:-your_strong_password}
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF
}

# 创建系统服务
create_service() {
  cat > $SERVICE_PATH/hysteria.service <<EOF
[Unit]
Description=Hysteria 2 Proxy Service
After=network.target

[Service]
User=root
WorkingDirectory=$CONFIG_PATH
ExecStart=$HYSTERIA_BIN server -c $CONFIG_PATH/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable hysteria
  systemctl start hysteria
}

# 生成配置分享链接
generate_links() {
  PUBLIC_IP=$(curl -4s ifconfig.co)
  SNI="bing.com"
  
  # 生成 v2rayN 格式的分享链接
  V2RAYN_CONFIG="{
    \"server\": \"${PUBLIC_IP}:${PORT:-443}\",
    \"auth\": \"${PASSWORD:-your_strong_password}\",
    \"tls\": {
      \"sni\": \"$SNI\",
      \"insecure\": true
    },
    \"quic\": {
      \"initStreamReceiveWindow\": 8388608,
      \"maxStreamReceiveWindow\": 8388608,
      \"initConnReceiveWindow\": 20971520,
      \"maxConnReceiveWindow\": 20971520
    }
  }"
  
  V2RAYN_BASE64=$(echo -n "$V2RAYN_CONFIG" | base64 -w 0)
  V2RAYN_LINK="hy2://$V2RAYN_BASE64"
  
  # 生成通用客户端配置
  CLIENT_CONFIG="server: ${PUBLIC_IP}:${PORT:-443}
auth: ${PASSWORD:-your_strong_password}
tls:
  sni: $SNI
  insecure: true
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520"
  
  # 生成一键导入链接 (base64)
  ONECLICK_BASE64=$(echo -n "$CLIENT_CONFIG" | base64 -w 0)
  ONECLICK_LINK="https://install.app/hy2#$ONECLICK_BASE64"
  
  echo ""
  echo "================= 客户端配置分享链接 ================="
  echo "1. v2rayN 分享链接 (直接导入):"
  echo "$V2RAYN_LINK"
  echo ""
  echo "2. 通用配置 (适用于所有客户端):"
  echo "$CLIENT_CONFIG" | sed 's/^/    /'
  echo ""
  echo "3. 一键导入链接 (支持部分客户端):"
  echo "$ONECLICK_LINK"
  echo ""
  echo "======================================================"
}

# 主安装流程
main() {
  # 设置参数
  if [ -n "$1" ]; then PORT=$1; fi
  if [ -n "$2" ]; then PASSWORD=$2; fi

  echo "正在安装依赖..."
  install_deps

  echo "正在安装 Hysteria 2..."
  install_hysteria

  echo "生成证书..."
  generate_cert

  echo "创建配置文件..."
  create_config

  echo "设置系统服务..."
  create_service

  echo "正在生成配置分享链接..."
  generate_links
}

main "$@"
