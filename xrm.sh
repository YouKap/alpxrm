#!/bin/bash

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 全域變數 ---
SCRIPT_URL="https://raw.githubusercontent.com/YouKap/alpxrm/main/xrm.sh"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_ASSETS="/usr/local/share/xray"

# 確保以 Root 權限執行
[[ $EUID -ne 0 ]] && echo -e "${RED}錯誤: 必須以 root 執行！${PLAIN}" && exit 1

# 自我安裝與執行環境校正
if [[ "$0" != "/usr/local/bin/xrm" ]]; then
    echo -e "${BLUE}>>> 正在同步腳本至全域環境...${PLAIN}"
    # Alpine 使用 apk 管理套件，並確保安裝必要的網路與系統工具
    apk update && apk add --no-cache curl unzip nano procps bash dnsmasq iproute2 coreutils
    curl -sSL "$SCRIPT_URL" -o /usr/local/bin/xrm
    chmod +x /usr/local/bin/xrm
    echo -e "${GREEN}>>> 安裝成功！未來可隨時輸入 'xrm' 呼叫面板。${PLAIN}"
    sleep 1
    exec /usr/local/bin/xrm
fi

# ==========================================
# 核心功能模組
# ==========================================

install_update_xray() {
    clear
    echo -e "${BLUE}=== 📦 安裝/更新 Xray-core (含數據文件) ===${PLAIN}"
    echo -e "${YELLOW}正在執行官方安裝程序...${PLAIN}"
    
    # 官方腳本支援 Alpine，但我們需要手動確保 OpenRC 腳本正確建立
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    
    # 強制覆寫/建立 OpenRC 專用的 Xray 服務檔
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

    echo -e "\n${GREEN}✅ 安裝/更新成功！(已適配 OpenRC)${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

# --- 修改：適配 Alpine 的 DNS 優化 (使用 dnsmasq 替代 systemd-resolved) ---
setup_dns_optimization() {
    clear
    echo -e "${BLUE}=== 🛡️ 系統 DNS 優化 (dnsmasq 轉發) ===${PLAIN}"
    echo -e "${YELLOW}正在檢查並安裝 dnsmasq...${PLAIN}"
    apk add --no-cache dnsmasq

    echo -e "${YELLOW}正在寫入設定檔 (/etc/dnsmasq.conf)...${PLAIN}"
    # 配置 dnsmasq 監聽本地 53 端口，並將所有請求無條件轉發給 Xray 的 5300 端口
    cat <<EOF > /etc/dnsmasq.conf
port=53
server=127.0.0.1#5300
listen-address=127.0.0.1
bind-interfaces
no-resolv
EOF

    echo -e "${YELLOW}正在接管 /etc/resolv.conf...${PLAIN}"
    # 移除軟連結並寫入本地 nameserver
    rm -f /etc/resolv.conf
    echo "nameserver 127.0.0.1" > /etc/resolv.conf

    echo -e "${YELLOW}正在啟動與應用服務...${PLAIN}"
    rc-update add dnsmasq default >/dev/null 2>&1
    rc-service dnsmasq restart

    echo -e "\n${GREEN}✅ DNS 集成優化成功！${PLAIN}"
    echo -e "目前路徑: ${CYAN}系統應用 -> dnsmasq (:53) -> Xray (:5300) -> DoH${PLAIN}"
    read -rp "按 Enter 鍵返回..." dummy < /dev/tty
}

edit_config() {
    clear
    echo -e "${BLUE}=== ⚙️ 2. 編輯 Xray 設定檔 ===${PLAIN}"
    if [ ! -f "$XRAY_BIN" ]; then echo -e "${RED}尚未安裝 Xray。${PLAIN}"; sleep 2; return; fi

    if [ ! -f "$XRAY_CONF" ] || [ $(stat -c%s "$XRAY_CONF" 2>/dev/null || echo 0) -lt 10 ]; then
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
    echo -e "\n${YELLOW}正在檢測設定檔語法...${PLAIN}"
    
    TEST_RES=$(XRAY_LOCATION_ASSET=$XRAY_ASSETS "$XRAY_BIN" -test -config "$XRAY_CONF" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 語法正確！正在重啟服務...${PLAIN}"
        rc-service xray restart
        sleep 0.5
        rc-service xray status 2>/dev/null | grep -q "started" && echo -e "${GREEN}🚀 重啟成功。${PLAIN}"
    else
        echo -e "${RED}❌ 語法檢測失敗！${PLAIN}"
        echo "$TEST_RES"
    fi
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

manage_service() {
    clear
    echo -e "${BLUE}=== ⚡ 3. 服務管理 ===${PLAIN}"
    echo -e " 1. ${GREEN}啟動${PLAIN} | 2. ${RED}停止${PLAIN} | 3. ${YELLOW}重啟${PLAIN} | 0. 返回"
    read -rp "請選擇: " s < /dev/tty
    case $s in 
        1) rc-service xray start ;; 
        2) rc-service xray stop ;; 
        3) rc-service xray restart ;; 
        0) return ;;
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
    
    # 顯示 DNS 狀態
    if rc-service dnsmasq status 2>/dev/null | grep -q "started"; then
        echo -e "DNS 優化: ${GREEN}已啟用 (dnsmasq 接管中)${PLAIN}"
    else
        echo -e "DNS 優化: ${YELLOW}未啟用${PLAIN}"
    fi
    echo "-------------------------------------------------"
    read -rp "按 Enter 返回..." dummy < /dev/tty
}

check_dns_health() {
    clear
    echo -e "${BLUE}=== 🔍 DNS 系統集成自檢 (正在執行實時檢測...) ===${PLAIN}"
    local errors=0

    # 1. 檢查 Xray 監聽
    echo -n "1. 檢查 Xray DNS 監聽 (5300): "
    if netstat -nlpu 2>/dev/null | grep -q ":5300"; then
        echo -e "${GREEN}正常 (偵測到 Xray 正在運行)${PLAIN}"
    else
        echo -e "${RED}異常 (Xray 未在 5300 監聽)${PLAIN}"
        ((errors++))
    fi

    # 2. 檢查 dnsmasq 設定
    echo -n "2. 檢查 dnsmasq 配置文件: "
    if grep -q "server=127.0.0.1#5300" /etc/dnsmasq.conf 2>/dev/null; then
        echo -e "${GREEN}正確 (已指向 127.0.0.1:5300)${PLAIN}"
    else
        echo -e "${RED}異常 (未檢測到正確的 dnsmasq 轉發設定)${PLAIN}"
        ((errors++))
    fi

    # 3. 測試解析鏈路 (確保鏈路通暢)
    echo -n "3. 正在發起實時解析測試 (google.com)... "
    
    # 使用 nslookup 進行測試 (Alpine 內建工具)
    if nslookup google.com 127.0.0.1 > /dev/null 2>&1; then
        echo -e "${GREEN}成功 (dnsmasq -> Xray 轉發正常)${PLAIN}"
    else
        if nslookup cloudflare.com 127.0.0.1 > /dev/null 2>&1; then
            echo -e "${GREEN}成功 (dnsmasq -> Xray 轉發正常)${PLAIN}"
        else
            echo -e "${RED}失敗 (dnsmasq 無法從 Xray 獲取數據)${PLAIN}"
            ((errors++))
        fi
    fi

    echo -e "-------------------------------------------------"
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}🎉 自檢通過！系統運作正常。${PLAIN}"
    else
        echo -e "${RED}❌ 檢測到 $errors 處異常。${PLAIN}"
    fi
    read -rp "按 Enter 鍵返回主選單..." dummy < /dev/tty
}

uninstall_xray() {
    clear
    echo -e "${RED}=== ⚠️ 解除安裝 Xray ===${PLAIN}"
    read -rp "確定要刪除嗎？(y/N): " c < /dev/tty
    if [[ "$c" == "y" || "$c" == "Y" ]]; then
        rc-service xray stop 2>/dev/null
        rc-update del xray default 2>/dev/null
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) remove --purge
        rm -rf /usr/local/etc/xray /usr/local/share/xray /etc/init.d/xray
        echo -e "${GREEN}✅ 已移除。${PLAIN}"
        sleep 2; exit 0
    fi
}

while true; do
    clear
    [[ -f "$XRAY_BIN" ]] && STATUS="${GREEN}(已安裝)${PLAIN}" || STATUS="${RED}(未安裝)${PLAIN}"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "   🚀 ${CYAN}Xray 管理面板 (xrm) [Alpine 版]${PLAIN}   $STATUS"
    echo -e "${BLUE}=================================================${PLAIN}"
    echo -e "${YELLOW} 1.${PLAIN} 安裝/更新 Xray" 
    echo -e "${YELLOW} 2.${PLAIN} 編輯 Xray 設定"
    echo -e "${YELLOW} 3.${PLAIN} 服務管理" 
    echo -e "${YELLOW} 4.${PLAIN} 狀態監控"
    echo -e "${GREEN} 6. 系統 DNS 優化 (集成 dnsmasq 轉發)${PLAIN}"
    echo -e "${YELLOW} 7.${PLAIN} 一鍵診斷 DNS 狀態"
    echo -e "-------------------------------------------------"
    echo -e "${RED} 5.${PLAIN} 徹底卸載"
    echo -e "${YELLOW} 0.${PLAIN} 退出"
    
    read -rp "請選擇: " choice < /dev/tty
    
    case $choice in
        1) install_update_xray ;; 
        2) edit_config ;; 
        3) manage_service ;; 
        4) show_status ;; 
        5) uninstall_xray ;; 
        6) setup_dns_optimization ;; 
        7) check_dns_health ;;
        0) clear; exit 0 ;;
    esac
done
