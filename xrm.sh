#!/bin/bash

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 全域變數 ---
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_ASSETS="/usr/local/share/xray"

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# ==========================================
# 核心功能模組
# ==========================================

install_update_xray() {
    clear
    echo -e "${BLUE}=== 📦 安裝/更新 Xray-core (Alpine 手動版) ===${PLAIN}"
    
    # 1. 偵測架構
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64)  PLATFORM="64" ;;
        aarch64) PLATFORM="arm64-v8a" ;;
        *) echo -e "${RED}不支援的架構: ${ARCH}${PLAIN}"; sleep 2; return ;;
    esac

    # 安裝解壓工具
    apk add --no-cache unzip curl > /dev/null 2>&1

    echo -e "${YELLOW}正在獲取最新版本號...${PLAIN}"
    VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
    [[ -z "$VERSION" ]] && VERSION="v24.11.30"
    
    echo -e "${YELLOW}正在下載 Xray-core ${VERSION} (${ARCH})...${PLAIN}"
    mkdir -p /tmp/xray
    curl -L "https://github.com/XTLS/Xray-core/releases/download/${VERSION}/Xray-linux-${PLATFORM}.zip" -o /tmp/xray/xray.zip
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下載失敗，請檢查網路連線。${PLAIN}"
        sleep 2; return
    fi

    echo -e "${YELLOW}正在解壓並安裝...${PLAIN}"
    unzip -o /tmp/xray/xray.zip -d /tmp/xray/
    
    mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray
    mv -f /tmp/xray/xray /usr/local/bin/xray
    mv -f /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat
    mv -f /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat
    chmod +x /usr/local/bin/xray
    rm -rf /tmp/xray

    # 2. 建立 OpenRC 服務腳本
    echo -e "${YELLOW}正在配置 OpenRC 服務...${PLAIN}"
    cat <<EOF > /etc/init.d/xray
#!/sbin/openrc-run
name="xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -c ${XRAY_CONF}"
command_background="yes"
pidfile="/run/xray.pid"
output_log="/var/log/xray.log"
error_log="/var/log/xray_error.log"

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default >/dev/null 2>&1
    
    echo -e "\n${GREEN}✅ Xray-core 安裝完成！${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

setup_dns_optimization() {
    clear
    echo -e "${BLUE}=== 🛡️ 系統 DNS 優化 (dnsmasq) ===${PLAIN}"
    apk add --no-cache dnsmasq
    
    cat <<EOF > /etc/dnsmasq.conf
port=53
server=127.0.0.1#5300
listen-address=127.0.0.1
bind-interfaces
no-resolv
EOF

    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    rc-update add dnsmasq default >/dev/null 2>&1
    rc-service dnsmasq restart
    echo -e "\n${GREEN}✅ DNS 集成優化成功 (53 -> 5300)${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

edit_config() {
    clear
    echo -e "${BLUE}=== ⚙️ 2. 編輯 Xray 設定檔 ===${PLAIN}"
    if [ ! -f "$XRAY_BIN" ]; then echo -e "${RED}尚未安裝 Xray。${PLAIN}"; sleep 2; return; fi
    
    # 若檔案不存在則寫入預設配置
    if [ ! -f "$XRAY_CONF" ]; then
        mkdir -p /usr/local/etc/xray
        cat <<EOF > "$XRAY_CONF"
{
  "log": {
    "loglevel": "none"
  },
  "dns": {
    "servers": [
      "https://1.1.1.1/dns-query",
      "https://8.8.8.8/dns-query"
    ],
    "queryStrategy": "UseIPv4",
    "tag": "dns-internal"
  },
  "inbounds": [
    {
      "tag": "dns-in",
      "port": 5300,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "1.1.1.1",
        "port": 53,
        "network": "udp"
      }
    },
    {
      "port": 52880,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "1cb88fed-057a-40d0-9341-94e53f3c5371"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/2UdBFrva7BrM1zLxT"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns"
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "none"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["dns-in"],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "protocol": ["dns"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "port": 443,
        "network": "udp",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
    fi

    nano "$XRAY_CONF" < /dev/tty
    rc-service xray restart
    read -rp "配置已保存並嘗試重啟，按 Enter 返回..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== ⚡ 3. 服務管理 ===${PLAIN}"
    echo -e " 1. ${GREEN}啟動${PLAIN} | 2. ${RED}停止${PLAIN} | 3. ${YELLOW}重啟${PLAIN} | 0. 返回"
    read -rp "選擇: " s < /dev/tty
    case $s in 
        1) rc-service xray start ;; 
        2) rc-service xray stop ;; 
        3) rc-service xray restart ;; 
    esac
}

show_status() {
    clear
    echo -e "${BLUE}=== 📊 4. 運行狀態監控 ===${PLAIN}"
    if rc-service xray status 2>/dev/null | grep -q "started"; then
        echo -e "Xray 狀態: ${GREEN}執行中${PLAIN}"
    else
        echo -e "Xray 狀態: ${RED}停止${PLAIN}"
    fi
    read -rp "按 Enter 返回..." dummy < /dev/tty
}

# --- 主選單 ---
while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS="${GREEN}(已安裝)${PLAIN}" || STATUS="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "   🚀 ${CYAN}Xray 管理面板 (xrm) [Alpine 2版]${PLAIN}   $STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 安裝/更新 Xray" 
    echo -e "${YELLOW} 2.${PLAIN} 編輯 Xray 設定"
    echo -e "${YELLOW} 3.${PLAIN} 服務管理" 
    echo -e "${YELLOW} 4.${PLAIN} 狀態監控"
    echo -e "${GREEN} 6. 系統 DNS 優化 (dnsmasq)${PLAIN}"
    echo -e "${YELLOW} 0.${PLAIN} 退出"
    read -rp "請選擇: " choice < /dev/tty
    case $choice in
        1) install_update_xray ;; 
        2) edit_config ;; 
        3) manage_service ;; 
        4) show_status ;; 
        6) setup_dns_optimization ;;
        0) exit 0 ;;
    esac
done
