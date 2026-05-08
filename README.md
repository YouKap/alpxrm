# 🚀 Xray-core 部署與管理面板 (xrm)

專為 alpine 環境設計的 Xray Manager 一鍵部署與管理工具。支援自動配置標準化 YAML、Systemd 守護進程，以及乾淨的無痕卸載。

## 🚀 一鍵安裝

請使用 `root` 權限在終端機執行以下命令：

```
apk update && apk add --no-cache bash curl ca-certificates && curl -sSL https://raw.githubusercontent.com/YouKap/alpxrm/main/xrm.sh -o /usr/local/bin/xrm && chmod +x /usr/local/bin/xrm && xrm
```
