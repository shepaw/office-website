# Shepaw 官网

Shepaw 产品站：首页、文档、下载。对照 [paseo.sh](https://paseo.sh/) 的信息架构，内容对齐三个仓库：

| 层 | 仓库 | 官网怎么讲 |
|---|---|---|
| App | `../shepaw` | 手机 / 桌面控制面，本地 LLM + 远端编码 Agent |
| Hub | `../agent-bridge` | 本机多项目网关，扫码配对，拉起 Claude Code / Codex / Cursor … |
| Relay | `../channel` | 可选：密文收件箱 + NAT 隧道 |

纯静态，无构建步骤。品牌色来自 App 主题：橘 `#EE7A1E`、肉垫粉、暖黑背景。

## 本地预览

```bash
cd website
python3 -m http.server 4173
# 打开 http://127.0.0.1:4173
```

路径按站点根计算（`/docs/`、`/assets/`），不要用 `file://` 打开。

## 部署

把本目录原样放到静态托管（Cloudflare Pages、GitHub Pages、Caddy、Nginx）。

Caddy 示例见 `Caddyfile`。GitHub Pages 若不是仓库根，需要改成相对路径，或把本目录作为独立仓库的根。

## 页面

- `/` 产品首页
- `/download/` 客户端 + Hub + Channel
- `/docs/` 快速开始、配对、Hub、引擎、CLI、Channel、安全、自托管、FAQ

导航右上角可切换中 / 英。
