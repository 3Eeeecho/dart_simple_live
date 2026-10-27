# Build SimpleLive on Windows, including the NVIDIA super-resolution changes.
# Installs Git, Flutter 3.41.9, Visual Studio C++ build tools, and Inno Setup
# when they are missing, then builds simple_live_app and an installer.
#
# From a PC that does not have the repo yet, paste this into PowerShell:
#   irm https://raw.githubusercontent.com/3Eeeecho/dart_simple_live/windows-sr-lookback/scripts/setup-and-build-windows.ps1 -OutFile $env:TEMP\setup-and-build-windows.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\setup-and-build-windows.ps1
#
# If raw.githubusercontent.com is blocked:
#   irm https://cdn.jsdelivr.net/gh/3Eeeecho/dart_simple_live@windows-sr-lookback/scripts/setup-and-build-windows.ps1 -OutFile $env:TEMP\setup-and-build-windows.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\setup-and-build-windows.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoUrl = 'https://github.com/3Eeeecho/dart_simple_live.git'
$Branch = 'windows-sr-lookback'
$FlutterVersion = '3.41.9'
$SdkRoot = Join-Path $env:LOCALAPPDATA 'SimpleLiveBuild'
$FlutterHome = Join-Path $SdkRoot 'flutter'
$LogDir = Join-Path $SdkRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ('build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Add-UserPath([string]$Directory) {
    if (-not (Test-Path $Directory)) {
        return
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) {
        $parts = $userPath.Split(';') | Where-Object { $_ -and ($_ -ne $Directory) }
    }
    $updated = (@($parts) + $Directory) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    if (($env:Path -split ';') -notcontains $Directory) {
        $env:Path = "$env:Path;$Directory"
    }
}

function Invoke-Winget([string[]]$Arguments) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget was not found. Install App Installer from the Microsoft Store, then run this script again."
    }
    & winget @Arguments
    $code = $LASTEXITCODE
    # 0 = installed. -1978335189 = no newer version / already installed.
    if ($code -ne 0 -and $code -ne -1978335189) {
        throw "winget failed ($code): winget $($Arguments -join ' ')"
    }
}

function Get-VsWherePath {
    return Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
}

function Test-VisualStudioReady {
    $vswhere = Get-VsWherePath
    if (-not (Test-Path $vswhere)) {
        return $false
    }
    $found = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -requires Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath
    return [bool]($found)
}

function Get-FlutterBat {
    $bundled = Join-Path $FlutterHome 'bin\flutter.bat'
    if (Test-Path $bundled) {
        return $bundled
    }
    $existing = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if (-not $existing) {
        $existing = Get-Command flutter -ErrorAction SilentlyContinue
    }
    if ($existing) {
        return $existing.Source
    }
    return $null
}

function Get-FlutterVersion([string]$FlutterBat) {
    $output = & $FlutterBat --version 2>&1 | Out-String
    if ($output -match 'Flutter\s+([0-9]+\.[0-9]+\.[0-9]+)') {
        return $Matches[1]
    }
    return ''
}

if (-not (Test-Administrator)) {
    Write-Step "需要管理员权限才能安装编译工具，请在弹出的窗口里允许"
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

try {

Write-Step "Log file: $LogFile"
Write-Host "第一次会安装 Visual Studio 编译工具，大约几 GB，请等到窗口自己结束。"

Update-SessionPath

Write-Step "Git"
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Invoke-Winget @(
        'install', '--id', 'Git.Git', '--exact',
        '--scope', 'machine',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    Update-SessionPath
    $gitCmd = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path $gitCmd) {
        Add-UserPath 'C:\Program Files\Git\cmd'
    }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is still not on PATH. Close this window and run the script again."
}

Write-Step "Flutter $FlutterVersion"
$flutterBat = Get-FlutterBat
$haveFlutter = $false
if ($flutterBat) {
    $current = Get-FlutterVersion $flutterBat
    if ($current -eq $FlutterVersion) {
        $haveFlutter = $true
        Write-Host "Using $flutterBat ($current)"
    } else {
        Write-Host "Found Flutter $current. This build uses the project version $FlutterVersion."
    }
}
if (-not $haveFlutter) {
    New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
    $zip = Join-Path $SdkRoot "flutter_windows_$FlutterVersion-stable.zip"
    $urls = @(
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip",
        "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
    )
    $downloaded = $false
    foreach ($url in $urls) {
        Write-Host "Downloading $url"
        & curl.exe -L --fail --retry 2 --retry-delay 2 -o $zip $url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $zip) -and ((Get-Item $zip).Length -gt 1000000)) {
            $downloaded = $true
            break
        }
        Write-Host "Download failed, trying the next address."
    }
    if (-not $downloaded) {
        throw "Could not download Flutter $FlutterVersion."
    }
    if (Test-Path $FlutterHome) {
        Remove-Item -Recurse -Force $FlutterHome
    }
    Write-Host "Extracting Flutter..."
    Expand-Archive -Path $zip -DestinationPath $SdkRoot -Force
    $flutterBat = Join-Path $FlutterHome 'bin\flutter.bat'
    if (-not (Test-Path $flutterBat)) {
        throw "Flutter archive did not contain bin\flutter.bat."
    }
    Add-UserPath (Join-Path $FlutterHome 'bin')
}

Write-Step "Visual Studio C++ build tools"
if (Test-VisualStudioReady) {
    Write-Host "Visual Studio C++ tools are already installed."
} else {
    Write-Host "正在安装 Visual Studio 2022 编译工具，这一步最慢。"
    $override = '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.CMake.Project --includeRecommended'
    Invoke-Winget @(
        'install', '--id', 'Microsoft.VisualStudio.2022.BuildTools', '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity',
        '--override', $override
    )
    if (-not (Test-VisualStudioReady)) {
        throw "Visual Studio finished but the C++ tools are still missing. Reboot Windows and run this script again."
    }
}

Write-Step "Inno Setup"
$isccCandidates = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    Invoke-Winget @(
        'install', '--id', 'JRSoftware.InnoSetup', '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    $iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

Write-Step "Source"
$scriptDir = Split-Path -Parent $PSCommandPath
$repoFromScript = Split-Path -Parent $scriptDir
$pubspecFromScript = Join-Path $repoFromScript 'simple_live_app\pubspec.yaml'
if (Test-Path $pubspecFromScript) {
    $repo = $repoFromScript
    Write-Host "Building the copy that contains this script: $repo"
} else {
    $repo = Join-Path $env:USERPROFILE 'SimpleLive'
    if (-not (Test-Path (Join-Path $repo '.git'))) {
        Write-Host "Cloning $Branch into $repo"
        & git clone --branch $Branch --single-branch $RepoUrl $repo
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed."
        }
    } else {
        Write-Host "Updating $repo"
        & git -C $repo fetch origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed." }
        & git -C $repo checkout $Branch
        if ($LASTEXITCODE -ne 0) { throw "git checkout failed." }
        & git -C $repo pull --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git pull failed." }
    }
}

$app = Join-Path $repo 'simple_live_app'
if (-not (Test-Path (Join-Path $app 'pubspec.yaml'))) {
    throw "simple_live_app\pubspec.yaml was not found in $repo"
}

Write-Step "flutter build windows --release"
& $flutterBat config --no-analytics | Out-Host
& $flutterBat config --enable-windows-desktop | Out-Host
Push-Location $app
try {
    & $flutterBat pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
    & $flutterBat build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed." }
} finally {
    Pop-Location
}

$releaseCandidates = @(
    (Join-Path $app 'build\windows\x64\runner\Release'),
    (Join-Path $app 'build\windows\runner\Release')
)
$releaseDir = $releaseCandidates | Where-Object { Test-Path (Join-Path $_ 'simple_live_app.exe') } | Select-Object -First 1
if (-not $releaseDir) {
    throw "The Windows release folder was not found."
}
$exe = Join-Path $releaseDir 'simple_live_app.exe'

$version = '1.13.3'
foreach ($line in Get-Content (Join-Path $app 'pubspec.yaml')) {
    if ($line -match '^version:\s*(\S+)') {
        $version = $Matches[1].Split('+')[0]
        break
    }
}

$setup = $null
if ($iscc) {
    Write-Step "Installer"
    $distDir = Join-Path $app 'build\dist'
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    $outputName = "SimpleLive-Windows-v$version-Setup"
    $iss = Join-Path $app 'windows\packaging\inno_setup\SimpleLive_Setup.iss'
    & $iscc "/DMyAppVersion=$version" "/DSourceDir=$releaseDir" "/DOutputDir=$distDir" "/DOutputFilename=$outputName" $iss
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installer build failed. The runnable program is still at $exe" -ForegroundColor Yellow
    } else {
        $setup = Join-Path $distDir "$outputName.exe"
    }
} else {
    Write-Host "Inno Setup was not found. The runnable program is at $exe" -ForegroundColor Yellow
}

Write-Step "完成"
Write-Host "程序：$exe"
if ($setup -and (Test-Path $setup)) {
    Write-Host "安装包：$setup"
    Start-Process explorer.exe "/select,`"$setup`""
} else {
    Start-Process explorer.exe "/select,`"$exe`""
}
Write-Host "安装后打开直播间设置，打开 NVIDIA 超分，设置回看上限，然后重新进入直播间。"
Write-Host "日志：$LogFile"
Write-Host ""
Write-Host "按回车关闭窗口。"
try { [void](Read-Host) } catch {}
exit 0
} catch {
    Write-Host ""
    Write-Host "构建失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "日志：$LogFile"
    Write-Host "按回车关闭窗口。"
    try { [void](Read-Host) } catch {}
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
