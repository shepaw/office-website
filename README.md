# Shepaw 官网

Shepaw 产品站：首页、文档、下载。对照 [paseo.sh](https://paseo.sh/) 的信息架构，内容对齐三个仓库：

| 层 | 仓库 | 官网怎么讲 |
|---|---|---|
| App | `../shepaw` | 手机 / 桌面控制面，本地 LLM + 远端编码 Agent |
| Hub | `../shepaw-cli` | 本机多项目 Hub，扫码配对，拉起 Claude Code / Codex / Cursor … |
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

`/install` 和 `/install.ps1` 必须按 `text/plain; charset=utf-8` 返回，否则 Windows 的 `irm | iex` 不会把正文当脚本执行。Caddyfile 已按路径覆盖 Content-Type。Nginx 需要：

```nginx
location = /install {
	default_type text/plain;
	charset utf-8;
}
location = /install.ps1 {
	default_type text/plain;
	charset utf-8;
}
```

## 更新发布（release.shepaw.com）

`release.shepaw.com` 是纯静态托管，没有动态后端；站点块见 `Caddyfile`。App 自动更新、
`shepaw update`、`/install` 与 `/install.ps1` 都从这里读清单。

| 路径 | 内容 |
|---|---|
| `/api/v1/latest-{platform}.json` | App 更新清单，`platform` = `macos` / `windows` / `linux` / `android` / `ios`；macOS 的 `arch` 固定 `universal`（x86_64 + arm64） |
| `/api/v1/latest-cli-{os}-{arch}.json` | CLI 二进制清单，两个安装脚本按本机平台读取；发布矩阵为 `macos-aarch64`、`macos-x86_64`、`windows-x86_64`、`linux-x86_64` |
| `/download/*` | 安装包本体（macOS `.tar.gz`、Windows `.zip`、APK …），清单里的 `downloadUrl` 指向这里 |
| `/api/v1/check-update?platform=macos` | 旧客户端动态入口，Caddy 用 `{query.platform}` 占位符 rewrite 到 `/api/v1/latest-{platform}.json` |

磁盘目录与请求路径一一对应（`root /var/www/shepaw-release`），因此 `latest-*.json` 不需要 rewrite：

```
/var/www/shepaw-release/
├── api/v1/
│   ├── latest-macos.json
│   ├── latest-android.json
│   ├── latest-cli-macos-aarch64.json
│   └── latest-cli-windows-x86_64.json
└── download/
    ├── shepaw-1.0.23-macos-release.tar.gz
    └── shepaw-1.0.23-windows.zip
```

清单响应必须是 `Content-Type: application/json; charset=utf-8` 且 `Cache-Control: no-store`：
撤回（`yanked`）和强制更新不能被浏览器或 CDN 缓存住。`/download/*` 按扩展名由静态服务器
自行推断类型。旧客户端的 `check-update` 只处理已知平台值，其余应返回 404。

**清单必须同时带签名与校验和**：`signature`（`ed25519:<base64>`，覆盖规范载荷）与
`checksum`（`sha256:<64 hex>`，覆盖下载到的文件字节）都是必填；字段定义、规范载荷、平台/架构
能力表和发布门禁见 App 仓库
[`docs/release/MANIFEST_V2.md`](../shepaw/docs/release/MANIFEST_V2.md)。清单由 App 仓库的
`tool/write_update_manifest.sh`、`tool/write_cli_manifests.sh` 生成并签发，发布时先传安装包、
最后覆盖清单。

### 首次安装的信任边界（务必如实理解）

两个安装脚本**不做 ed25519 密码学验签**：Windows 上没有可靠的 Ed25519 原语，macOS 自带的
LibreSSL 也不支持 `openssl pkeyutl -verify -rawin`，强行「探测到就验、探测不到就跳过」等于
静默降级。因此脚本做的是：

- 强制 v2 清单（`schemaVersion=2`、platform/arch 与本机匹配、`seq`、`expiry` 未过期、
  `yanked=false`、`rollout`、`signature` / `packageSignature` 存在且格式合法）；
- `checksum` 必须是 `sha256:<64 hex>`，`fileSize` 与下载字节数强比对，魔数检查；
- `downloadUrl`、清单地址与 `SHEPAW_RELEASE_BASE` 只允许 HTTPS + 四域名白名单 + 默认端口。
  例外两处：用户显式把 `SHEPAW_RELEASE_BASE` 设为自建 https 源时，该源的 host 也被允许承载
  `downloadUrl`（此时首次安装的信任锚还包含「用户自己指定的 RELEASE_BASE」）；以及本机联调时
  基址与地址可同为回环 `http://127.0.0.1:PORT`。
  bash 逐跳跟随重定向并每跳重验白名单，PowerShell 因无法逐跳重验而对清单请求用
  `-MaximumRedirection 0`、对下载用 `AllowAutoRedirect = false`，**直接拒绝 3xx**
  （所以 Windows 一键安装要求 `downloadUrl` 是直链，GitHub Release 资产需先镜像）；
- 校验通过后才在同目录原子替换，并尽力 `shepaw stop` / 清 quarantine。

**首次安装的信任锚 = 官网 HTTPS（脚本来源） + 清单 HTTPS（发布源） + 清单内 sha256**；
它不提供「发布源被完全攻陷」场景下的密码学身份保证。装好之后，`shepaw update` 才会用
内置 Ed25519 公钥对**后续每次替换**同时验证清单签名（`signature`）与二进制签名
（`packageSignature`）。App 欢迎页的「一键安装」只是把 `curl … | bash` / `irm … | iex`
复制到剪贴板，不承担任何下载或验签职责。

若部署方要求首次安装也做密码学验签，需要为用户提供带验签能力的引导程序（例如签名的
`.pkg` / `.msi`，或自带 openssl 3 的独立校验器），而不是在本脚本里假装验过。

### 安装脚本的托管位置

`/install` 与 `/install.ps1` 只在 `shepaw.com` 主站托管（`text/plain; charset=utf-8`），
`release.shepaw.com` 只放 `api/v1/` 清单与 `download/` 产物。客户端和文档里的安装命令必须写
`https://shepaw.com/install` / `https://shepaw.com/install.ps1`，不要写成
`release.shepaw.com/install.sh`（会 404，而 `sh` 收到空输入会静默成功）。

## 页面

- `/` 产品首页
- `/install` macOS / Linux 安装脚本（`curl -fsSL https://shepaw.com/install | bash`，装到 `~/.shepaw/bin`）
- `/install.ps1` Windows 安装脚本（`irm https://shepaw.com/install.ps1 | iex`，装到 `%LOCALAPPDATA%\Shepaw\bin`）
- `/download/` 客户端 + CLI + Channel
- `/docs/` 快速开始、配对、Hub、引擎、CLI、Channel、安全、自托管、FAQ
- `release.shepaw.com` 更新清单与安装包（见上节）

导航右上角可切换中 / 英。
