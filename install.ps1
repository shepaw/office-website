# Shepaw CLI 安装脚本。
# Windows PowerShell:
#   irm https://shepaw.com/install.ps1 | iex
#
# 装到 $env:SHEPAW_INSTALL_DIR，缺省是 %LOCALAPPDATA%\shepaw\bin。
# 发布清单来自 $env:SHEPAW_RELEASE_BASE，缺省是 https://release.shepaw.com。
# 设 SHEPAW_NO_PATH=1 时不改用户 PATH。
# 这个文件会被 iex 在当前会话里执行，所以用 throw，不用 exit。

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

function Install-Shepaw {
    $releaseBase = if ($env:SHEPAW_RELEASE_BASE) { $env:SHEPAW_RELEASE_BASE.TrimEnd('/') } else { 'https://release.shepaw.com' }
    $maxBytes = 128MB

    function Test-AllowedUrl([string]$Url) {
        if ($Url -like 'https://*') { return $true }
        $loopback = $releaseBase -like 'http://127.0.0.1:*' -or $releaseBase -like 'http://localhost:*'
        if ($loopback -and ($Url -like 'http://127.0.0.1:*' -or $Url -like 'http://localhost:*')) {
            return $true
        }
        return $false
    }

    if (-not (Test-AllowedUrl $releaseBase)) {
        throw '发布地址必须是 https://'
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        'aarch64'
    } elseif ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
        'x86_64'
    } else {
        throw "不支持的架构: $env:PROCESSOR_ARCHITECTURE"
    }

    $manifestUrl = "$releaseBase/api/v1/latest-cli-windows-$arch.json"
    Write-Host "读取 $manifestUrl"
    try {
        $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing
    } catch {
        $response = $_.Exception.Response
        if ($response -and [int]$response.StatusCode -eq 404) {
            throw "还没有 windows-$arch 的安装包: $manifestUrl"
        }
        throw "无法读取发布清单: $manifestUrl"
    }

    $version = [string]$manifest.version
    $download = [string]$(if ($manifest.downloadUrl) { $manifest.downloadUrl } else { $manifest.download_url })
    $checksum = [string]$(if ($manifest.checksum) { $manifest.checksum } else { $manifest.sha256 })
    $signature = [string]$manifest.signature
    if (-not $version) { throw '更新清单缺少 version' }
    if (-not $download) { throw '更新清单没有下载地址' }
    if (-not (Test-AllowedUrl $download)) { throw '下载地址必须是 https://' }

    $work = Join-Path ([IO.Path]::GetTempPath()) ("shepaw-install-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $work | Out-Null
    $bin = Join-Path $work 'shepaw.exe'
    try {
        Write-Host "下载 shepaw $version"
        Invoke-WebRequest -Uri $download -OutFile $bin -UseBasicParsing
        $length = (Get-Item $bin).Length
        if ($length -le 0 -or $length -gt $maxBytes) {
            throw '安装包大小不对'
        }
        $head = [IO.File]::ReadAllBytes($bin)[0..1]
        if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
            throw '下载到的不是 Windows 可执行文件'
        }
        if ($checksum) {
            $expect = $checksum.Trim().ToLowerInvariant()
            if ($expect.StartsWith('sha256:')) { $expect = $expect.Substring(7) }
            $actual = (Get-FileHash -Algorithm SHA256 -Path $bin).Hash.ToLowerInvariant()
            if ($expect -ne $actual) {
                throw "校验和不匹配，期望 $expect，实际 $actual"
            }
        } elseif (-not $signature) {
            throw '安装包清单没有校验和，也没有签名'
        } else {
            Write-Host '清单没有校验和。文件经 HTTPS 下载，签名会在 shepaw update 时校验。'
        }

        $destDir = if ($env:SHEPAW_INSTALL_DIR) { $env:SHEPAW_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'shepaw\bin' }
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        $dest = Join-Path $destDir 'shepaw.exe'
        try {
            Move-Item -Force -Path $bin -Destination $dest
        } catch {
            throw "无法替换 $dest。先执行 shepaw stop，再重新安装。"
        }

        Write-Host "已安装 shepaw $version"
        Write-Host "  $dest"
        Add-ShepawPath $destDir
        Write-Host '下一步:'
        Write-Host '  shepaw start'
        Write-Host '  shepaw pair'
    } finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
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
