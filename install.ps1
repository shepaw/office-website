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
    if ([regex]::IsMatch($Url, '[\s\r\n]')) { return $false }
    # 回环 http 只用于 SHEPAW_RELEASE_BASE 显式指向本机的本地联调。
    # 用 [regex]::IsMatch（大小写敏感），不用默认 IgnoreCase 的 -match。
    if ([regex]::IsMatch($ReleaseBase, '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?/?$')) {
        if ([regex]::IsMatch($Url, '^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/.*)?$')) {
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
    return ($allowed -ccontains $hostName)
}

function Test-Ed25519Signature([string]$Value) {
    # PowerShell 的 StartsWith 重载默认大小写敏感；这里显式指定 Ordinal，
    # 并先过滤 base64 字符集，避免 FromBase64String 忽略内嵌空白/换行。
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    if (-not $Value.StartsWith('ed25519:', [StringComparison]::Ordinal)) { return $false }
    $raw = $Value.Substring(8)
    if (-not [regex]::IsMatch($raw, '^[A-Za-z0-9+/]+={0,2}$')) { return $false }
    try {
        $bytes = [Convert]::FromBase64String($raw)
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
        'packageSignature','isMandatory','rollout','yanked','description')) {
        # -cnotcontains：PowerShell 的 -contains/-notcontains 默认忽略大小写，
        # 会让 SCHEMAVERSION 之类非契约字段名蒙混过关。
        if ($names -cnotcontains $required) { throw "更新清单缺少 $required" }
    }
    foreach ($numeric in @('schemaVersion','seq','fileSize','rollout')) {
        # 必须是 JSON 整数：Invoke-RestMethod 把 2.0 解析成 decimal/double，
        # 字符串化后同样是 "2"，不能靠字符串化判断（bash 侧 is_int 会拒绝）。
        $v = $Manifest.$numeric
        if (-not ($v -is [int] -or $v -is [long])) {
            throw "$numeric 必须是 JSON 整数"
        }
    }
    foreach ($flag in @('isMandatory','yanked')) {
        if ($Manifest.$flag -isnot [bool]) { throw "$flag 必须是 bool" }
    }
    foreach ($text in @('description','releaseDate','downloadUrl','checksum','signature','packageSignature','version','buildNumber','platform','arch','channel')) {
        if ($Manifest.$text -isnot [string]) { throw "$text 必须是 string" }
    }
    if ($Manifest.schemaVersion -ne 2) { throw 'schemaVersion 必须是整数 2' }
    if (@('stable','beta') -cnotcontains $Manifest.channel) { throw 'channel 必须是 stable / beta' }
    if ($Manifest.platform -cne 'windows') { throw 'platform 必须是 windows' }
    $archOk = ($Manifest.arch -ceq $ArchName) -or ($AllowX64Fallback -and ($Manifest.arch -ceq 'x86_64'))
    if (-not $archOk) { throw "arch 与本机不匹配（期望 $ArchName）" }
    # 所有正则用 [regex]::IsMatch（大小写敏感）并以 \z 收尾，避免 PowerShell
    # 默认 IgnoreCase 与 .NET `$` 允许末尾换行的双重放宽。
    if (-not [regex]::IsMatch($Manifest.version, '^[0-9]+\.[0-9]+\.[0-9]+\z')) {
        throw 'version 必须是 x.y.z'
    }
    if (-not [regex]::IsMatch($Manifest.buildNumber, '^[0-9]+\z')) {
        throw 'buildNumber 必须是十进制字符串'
    }
    if ($Manifest.seq -le 0) { throw 'seq 必须是正整数' }
    if ($Manifest.fileSize -le 0) { throw 'fileSize 必须是正整数' }
    if ($Manifest.rollout -lt 0 -or $Manifest.rollout -gt 100) { throw 'rollout 必须在 0–100' }
    if (-not [regex]::IsMatch($Manifest.checksum, '^sha256:[0-9a-fA-F]{64}\z')) {
        throw 'checksum 必须是 sha256:<64 hex>'
    }
    if (-not (Test-Ed25519Signature $Manifest.signature)) {
        throw 'signature 必须是 ed25519:<64 字节 base64>'
    }
    if (-not (Test-Ed25519Signature $Manifest.packageSignature)) {
        throw 'packageSignature 必须是 ed25519:<64 字节 base64>'
    }
    if ($Manifest.yanked) { throw '该版本已撤回（yanked=true）' }
    $expiry = [string]$Manifest.expiry
    if ($expiry) {
        if (-not [regex]::IsMatch($expiry, '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z\z')) {
            throw 'expiry 必须是 ISO8601 UTC'
        }
        # InvariantCulture：佛历/回历区域的 yyyy 会输出 2569/1448，导致
        # 未过期清单被判过期或过期清单通过；CompareOrdinal 避免区域排序规则。
        $nowUtc = [datetime]::UtcNow.ToString('yyyy-MM-dd\THH:mm:ss\Z',
            [Globalization.CultureInfo]::InvariantCulture)
        $expiryKey = $expiry.Substring(0, 19) + 'Z'
        if ([string]::CompareOrdinal($expiryKey, $nowUtc) -le 0) {
            throw "expiry 已过期（$expiry）"
        }
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

    # checksum 必填且必须带小写 sha256: 前缀 + 64 位 hex；签名不能替代校验和。
    # 用 [regex]::IsMatch（-notmatch 默认忽略大小写，会放过 SHA256:）。
    if (-not $checksum) { throw '更新清单缺少 checksum（必须 sha256:<64 hex>）' }
    $checksum = $checksum.Trim()
    if (-not [regex]::IsMatch($checksum, '^sha256:[0-9a-fA-F]{64}\z')) {
        throw "checksum 格式不合法，必须 sha256:<64 hex>: $checksum"
    }
    $expect = $checksum.Substring(7).ToLowerInvariant()

    # v2 清单必带 fileSize：下载后强比对字节数，防截断包被当成完整包安装。
    if (-not $fileSize) { throw '更新清单缺少 fileSize（v2 必填）' }
    if (-not [regex]::IsMatch($fileSize, '^[0-9]+\z')) {
        throw "fileSize 必须是十进制正整数: $fileSize"
    }
    $expectedLength = [long]$fileSize
    # 下载前就按清单声明拒绝超大包，别等写满磁盘才发现。
    if ($expectedLength -gt $maxBytes) {
        throw "清单声明的 fileSize $expectedLength 超过 $maxBytes 字节上限"
    }

    # 临时文件放目标目录内：同一卷内 Move-Item 才是原子替换，不会留下半成品。
    $destDir = if ($env:SHEPAW_INSTALL_DIR) { $env:SHEPAW_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Shepaw\bin' }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir 'shepaw.exe'
    $tmp = Join-Path $destDir ('.shepaw.download.' + [guid]::NewGuid().ToString('n'))
    try {
        Write-Host "下载 shepaw $version"
        # Windows 侧无法逐跳重验白名单，因此 fail closed：不允许自动重定向，
        # 3xx 直接失败（README 已写明 downloadUrl 必须是直链）。
        # 用 HttpWebRequest 流式读取并在写入时累计字节，超上限立即中止；
        # 不再用 Invoke-WebRequest -OutFile 把整个响应无界落盘后再检查长度。
        $request = [Net.WebRequest]::Create($download)
        $request.Method = 'GET'
        $request.AllowAutoRedirect = $false
        $request.Timeout = 60000
        $request.ReadWriteTimeout = 60000
        $response = $null
        $stream = $null
        $outStream = $null
        try {
            $response = $request.GetResponse()
            $status = [int]$response.StatusCode
            if ($status -ne 200) {
                throw "下载地址返回 $status（不允许重定向，请确认 downloadUrl 是直链）"
            }
            $stream = $response.GetResponseStream()
            $outStream = [IO.File]::Create($tmp)
            $buffer = New-Object byte[] 65536
            $total = [long]0
            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $total += $read
                if ($total -gt $maxBytes) {
                    throw "安装包超过 $maxBytes 字节上限"
                }
                $outStream.Write($buffer, 0, $read)
            }
            $outStream.Flush()
        } finally {
            if ($outStream) { $outStream.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($response) { $response.Dispose() }
        }
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
