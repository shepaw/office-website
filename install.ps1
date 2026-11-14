# Shepaw CLI 安装脚本。
# Windows PowerShell:
#   irm https://shepaw.com/install.ps1 | iex
#
# 装到 $env:SHEPAW_INSTALL_DIR，缺省是 %LOCALAPPDATA%\Shepaw\bin（与 App 的 CliHost / CliBundle 对齐）。
# 发布清单来自 $env:SHEPAW_RELEASE_BASE，缺省是 https://release.shepaw.com；
# 覆盖时必须是 https://，或本机回环 http://127.0.0.1:PORT（仅本地联调）。
# 设 SHEPAW_NO_PATH=1 时不改用户 PATH。
# 这个文件会被 iex 在当前会话里执行，所以用 throw，不用 exit。
#
# 完整性：清单必须是 v2（schemaVersion=2 + 平台/架构匹配 + 未撤回 + 未过期），
# checksum 必须是 sha256:<64 hex>，fileSize 与下载字节数强比对，downloadUrl 只允许
# 三端一致的 host 白名单，两个签名必须存在且格式合法。
# 注意：脚本本身**不做 ed25519 密码学验签**（Windows 没有可靠的 Ed25519 原语）。
# 首次安装的信任锚是官网 HTTPS + 清单内 sha256；装好后的 `shepaw update` 会用
# 内置公钥对后续替换做真正的清单签名 + 包签名校验。详见 README「首次安装」。

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

function Test-AllowedUrl([string]$Url, [string]$ReleaseBase) {
    # 白名单放在函数内，避免依赖 `& { }` scriptblock 的作用域查找。
    # 与 App / 主机 CLI / 发布门禁一致。
    $allowlist = @(
        'release.shepaw.com', 'github.com',
        'objects.githubusercontent.com', 'release-assets.githubusercontent.com'
    )
    if ([string]::IsNullOrEmpty($Url)) { return $false }
    if ($Url -match '[\s\r\n]') { return $false }
    # 回环 http 只用于 SHEPAW_RELEASE_BASE 显式指向本机的本地联调。
    if ($ReleaseBase -match '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?/?$') {
        if ($Url -match '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/.*)?$') {
            return $true
        }
    }
    $parsed = [regex]::Match($Url, '^https://([^/@:?#]+)(?::([0-9]+))?(/[^#]*)?$')
    if (-not $parsed.Success) { return $false }
    $hostName = $parsed.Groups[1].Value.ToLowerInvariant()
    $port = if ($parsed.Groups[2].Success) { $parsed.Groups[2].Value } else { '443' }
    if ($port -ne '443') { return $false }
    if ($hostName.EndsWith('.')) { return $false }
    $allowed = @($allowlist)
    $baseMatch = [regex]::Match($ReleaseBase, '^https://([^/@:?#]+)')
    if ($baseMatch.Success) { $allowed += $baseMatch.Groups[1].Value.ToLowerInvariant() }
    return ($allowed -contains $hostName)
}

function Test-Ed25519Signature([string]$Value) {
    if (-not $Value -or -not $Value.StartsWith('ed25519:')) { return $false }
    try {
        $bytes = [Convert]::FromBase64String($Value.Substring(8))
        return ($bytes.Length -eq 64)
    } catch {
        return $false
    }
}

# v2 清单整体校验：只校验「声明与格式」，密码学验签由装好后的 CLI 负责。
# $AllowX64Fallback 用于 ARM64 Windows 回退到 x86_64 清单的场景。
function Assert-ManifestV2($Manifest, [string]$ArchName, [bool]$AllowX64Fallback) {
    if ($null -eq $Manifest) { throw '更新清单为空' }
    $names = @($Manifest.PSObject.Properties.Name)
    foreach ($required in @(
        'schemaVersion','channel','platform','arch','version','buildNumber','seq',
        'releaseDate','downloadUrl','fileSize','checksum','signature',
        'packageSignature','isMandatory','rollout','yanked')) {
        if ($names -notcontains $required) { throw "更新清单缺少 $required" }
    }
    foreach ($numeric in @('schemaVersion','seq','fileSize','rollout')) {
        $v = $Manifest.$numeric
        if ($v -is [string] -or $v -is [bool] -or $v -is [array]) {
            throw "$numeric 必须是 JSON 数字"
        }
    }
    foreach ($flag in @('isMandatory','yanked')) {
        if ($Manifest.$flag -isnot [bool]) { throw "$flag 必须是 bool" }
    }
    if ("$($Manifest.schemaVersion)" -ne '2') { throw 'schemaVersion 必须是整数 2' }
    if (@('stable','beta') -notcontains $Manifest.channel) { throw 'channel 必须是 stable / beta' }
    if ($Manifest.platform -ne 'windows') { throw 'platform 必须是 windows' }
    $archOk = ($Manifest.arch -eq $ArchName) -or ($AllowX64Fallback -and $Manifest.arch -eq 'x86_64')
    if (-not $archOk) { throw "arch 与本机不匹配（期望 $ArchName）" }
    if ($Manifest.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw 'version 必须是 x.y.z' }
    if ("$($Manifest.buildNumber)" -notmatch '^[0-9]+$') { throw 'buildNumber 必须是十进制字符串' }
    if ("$($Manifest.seq)" -notmatch '^[1-9][0-9]*$') { throw 'seq 必须是正整数' }
    if ("$($Manifest.fileSize)" -notmatch '^[1-9][0-9]*$') { throw 'fileSize 必须是正整数' }
    if ("$($Manifest.rollout)" -notmatch '^[0-9]+$' -or [int]$Manifest.rollout -gt 100) {
        throw 'rollout 必须在 0–100'
    }
    if ($Manifest.checksum -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw 'checksum 必须是 sha256:<64 hex>'
    }
    if (-not (Test-Ed25519Signature ([string]$Manifest.signature))) {
        throw 'signature 必须是 ed25519:<64 字节 base64>'
    }
    if (-not (Test-Ed25519Signature ([string]$Manifest.packageSignature))) {
        throw 'packageSignature 必须是 ed25519:<64 字节 base64>'
    }
    if ("$($Manifest.yanked)" -eq 'True') { throw '该版本已撤回（yanked=true）' }
    $expiry = [string]$Manifest.expiry
    if ($expiry) {
        if ($expiry -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$') {
            throw 'expiry 必须是 ISO8601 UTC'
        }
        # 同格式 ISO8601 UTC 的字典序即时间序，避免依赖本机区域设置。
        $nowUtc = [datetime]::UtcNow.ToString('yyyy-MM-dd\THH:mm:ss\Z')
        if (($expiry.Substring(0, 19) + 'Z') -le $nowUtc) { throw "expiry 已过期（$expiry）" }
    }
}

function Stop-ShepawHub {
    $shepaw = Get-Command shepaw -ErrorAction SilentlyContinue
    if (-not $shepaw) {
        Write-Host '警告: 未找到 shepaw 命令，跳过 shepaw stop'
        return
    }
    try {
        $global:LASTEXITCODE = 0
        & ($shepaw.Source) stop 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '已停止正在运行的 shepaw Hub'
        } else {
            Write-Host '警告: shepaw stop 未成功（可能没有运行中的 Hub），继续替换'
        }
    } catch {
        Write-Host '警告: shepaw stop 执行失败，继续替换'
    }
}

function Install-Shepaw {
    $releaseBase = if ($env:SHEPAW_RELEASE_BASE) { $env:SHEPAW_RELEASE_BASE.TrimEnd('/') } else { 'https://release.shepaw.com' }
    $maxBytes = 128MB

    if (-not (Test-AllowedUrl $releaseBase $releaseBase)) {
        throw '发布地址必须是 https://（本机联调可用 http://127.0.0.1:PORT）'
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        'aarch64'
    } elseif ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
        'x86_64'
    } else {
        throw "不支持的架构: $env:PROCESSOR_ARCHITECTURE"
    }

    # 发布矩阵里暂时没有 windows-aarch64 产物。设计文档约定：ARM64 清单返回 404
    # 时回退到 x86_64（x64 二进制可在 ARM64 Windows 上模拟运行）。两份都没有才报错。
    $manifestNames = @("latest-cli-windows-$arch.json")
    if ($arch -eq 'aarch64') { $manifestNames += 'latest-cli-windows-x86_64.json' }

    $manifest = $null
    foreach ($name in $manifestNames) {
        if ($manifest) { break }
        $manifestUrl = "$releaseBase/api/v1/$name"
        Write-Host "读取 $manifestUrl"
        try {
            $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing `
                -MaximumRedirection 0 -TimeoutSec 60
        } catch {
            $response = $_.Exception.Response
            $status = if ($response) { [int]$response.StatusCode } else { 0 }
            if ($status -ne 404) {
                throw "无法读取发布清单: $manifestUrl"
            }
            Write-Host "没有 ${name}（404），尝试下一个清单"
        }
    }
    if (-not $manifest) {
        throw "还没有 windows-$arch 的安装包（已尝试: $($manifestNames -join ', ')）"
    }

    # v2 契约整体校验（platform/arch、seq、expiry、yanked、两个签名的格式），
    # 只认 v2 字段名，不认 v1 的 download_url / sha256 别名。
    Assert-ManifestV2 $manifest $arch ($arch -eq 'aarch64')
    $version = [string]$manifest.version
    $download = [string]$manifest.downloadUrl
    $checksum = [string]$manifest.checksum
    $fileSize = [string]$manifest.fileSize
    if (-not (Test-AllowedUrl $download $releaseBase)) {
        throw '下载地址必须是 https:// 白名单地址，且端口为 443（本机联调除外）'
    }

    # checksum 必填且必须带 sha256: 前缀 + 64 位 hex；签名不能替代校验和。
    if (-not $checksum) { throw '更新清单缺少 checksum（必须 sha256:<64 hex>）' }
    $checksum = $checksum.Trim()
    if ($checksum -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw "checksum 格式不合法，必须 sha256:<64 hex>: $checksum"
    }
    $expect = $checksum.Substring(7).ToLowerInvariant()

    # v2 清单必带 fileSize：下载后强比对字节数，防截断包被当成完整包安装。
    if (-not $fileSize) { throw '更新清单缺少 fileSize（v2 必填）' }
    if ($fileSize -notmatch '^[0-9]+$') { throw "fileSize 必须是十进制正整数: $fileSize" }
    $expectedLength = [long]$fileSize

    # 临时文件放目标目录内：同一卷内 Move-Item 才是原子替换，不会留下半成品。
    $destDir = if ($env:SHEPAW_INSTALL_DIR) { $env:SHEPAW_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Shepaw\bin' }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir 'shepaw.exe'
    $tmp = Join-Path $destDir ('.shepaw.download.' + [guid]::NewGuid().ToString('n'))
    try {
        Write-Host "下载 shepaw $version"
        # HEAD 预检能让无 Content-Length 之外的超大响应尽早被拒绝；服务器不支持
        # HEAD 时只警告，后面仍有 fileSize 与实际长度强比对兜底。
        $tooBig = $false
        try {
            $head = Invoke-WebRequest -Uri $download -Method Head -UseBasicParsing `
                -MaximumRedirection 0 -TimeoutSec 30
            $declared = $head.Headers['Content-Length']
            if ($declared -and [long]$declared -gt $maxBytes) { $tooBig = $true }
        } catch {
            Write-Host "警告: HEAD 预检不可用: $($_.Exception.Message)"
        }
        if ($tooBig) { throw "安装包超过 $maxBytes 字节上限" }
        # 不允许自动重定向：脚本无法逐跳重验白名单，遇到 3xx 直接失败（fail closed）。
        Invoke-WebRequest -Uri $download -OutFile $tmp -UseBasicParsing `
            -MaximumRedirection 0 -TimeoutSec 60
        $length = (Get-Item $tmp).Length
        if ($length -le 0 -or $length -gt $maxBytes) {
            throw '安装包大小不对'
        }
        if ($length -ne $expectedLength) {
            throw "文件大小不匹配，期望 ${expectedLength}，实际 ${length}"
        }
        # MZ 魔数：确认拿到的是 PE 可执行文件，不是 404 页面 / HTML。
        $head = ([IO.File]::ReadAllBytes($tmp))[0..1]
        if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
            throw '下载到的不是 Windows 可执行文件'
        }
        $actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
        if ($expect -ne $actual) {
            throw "校验和不匹配，期望 ${expect}，实际 ${actual}"
        }

        # 替换前尽力停掉运行中的 Hub：命令不存在或失败只 warn，不阻断。
        Stop-ShepawHub

        try {
            Move-Item -Force -Path $tmp -Destination $dest
        } catch {
            throw "无法替换 ${dest}。先执行 shepaw stop，再重新安装。"
        }

        # 去掉 Mark-of-the-Web，避免 SmartScreen / Defender 对未签名 exe 的额外拦截。
        try {
            Unblock-File -Path $dest -ErrorAction Stop
        } catch {
            Write-Host "警告: Unblock-File 失败: $($_.Exception.Message)"
        }

        Write-Host "已安装 shepaw $version"
        Write-Host "  $dest"
        Add-ShepawPath $destDir
        Write-Host '下一步:'
        Write-Host '  shepaw start'
        Write-Host '  shepaw pair'
    } finally {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Add-ShepawPath([string]$Dir) {
    if ($env:Path -split ';' | Where-Object { $_ -eq $Dir }) {
        return
    }
    if ($env:SHEPAW_NO_PATH -eq '1') {
        Write-Host "把 $Dir 加到 PATH"
        return
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = @($userPath -split ';' | Where-Object { $_ }) }
    if ($parts -notcontains $Dir) {
        $updated = (@($parts) + $Dir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
        Write-Host '已写入用户 PATH。新开的终端会生效。'
    }
    $env:Path = "$env:Path;$Dir"
}

Install-Shepaw
}
