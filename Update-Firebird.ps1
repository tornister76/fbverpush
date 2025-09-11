param(
  [string]$ServiceName = "FirebirdServerDefaultInstance",
  [string]$DownloadUrl = "https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-3.0.13.33818-0-x64.exe",
  [string]$Tasks       = "UseSuperServerTask,UseServiceTask,AutoStartTask,CopyFbClientToSysTask,CopyFbClientAsGds32Task",

  # Domyślnie POMIŃ sprawdzanie podpisu
  [switch]$NoSignatureCheck = $true,

  # Opcjonalnie: włącz weryfikację SHA256 (zamiast podpisu)
  [switch]$VerifySha256,
  [string]$ExpectedSha256 = '6e53bb7642a390027118f576669f7913ea7a652eca7d2dc41c86e2be94d3fb06',

  # === CLIENT INSTALLATION ===
  [switch]$InstallClientOnly = $false,
  [string]$ClientTasks = "CopyFbClientToSysTask,CopyFbClientAsGds32Task",

  # === FBVERPUSH ===
  [switch]$RunFbVerPush = $true,
  [string]$FbVerPushUrl = 'https://github.com/tornister76/fbverpush/blob/main/fbverpush.ps1',
  [string[]]$FbVerPushArgs
)

# --- Admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run PowerShell as Administrator."
  exit 1
}

# === INSTALL GATE: proceed only if Firebird v3 is installed AND < 3.0.13 ===
$didInstall = $false  # zostanie ustawione na $true po udanym upgrade

function Get-FBInstallInfo {
  $obj = [PSCustomObject]@{ Path=$null; Exe=$null; Version=$null; VersionString=$null }
  $regPath = 'HKLM:\SOFTWARE\Firebird Project\Firebird Server\Instances'
  $val = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue)."DefaultInstance"
  if ($val -and (Test-Path $val)) {
    $obj.Path = $val
    $exe = Join-Path $val 'fbserver.exe'
    if (-not (Test-Path $exe)) { $exe = Join-Path $val 'firebird.exe' }
    if (Test-Path $exe) {
      $obj.Exe = $exe
      $verStr = (Get-Item $exe).VersionInfo.ProductVersion
      $obj.VersionString = $verStr
      try {
        # wytnij nienumeryczny ogon, zostaw tylko X.Y.Z.W
        $obj.Version = [Version]($verStr -replace '[^\d\.].*$','')
      } catch { }
    }
  }
  return $obj
}

$fb = Get-FBInstallInfo
$target = [Version]'3.0.13.0'

if (-not $fb.Version) {
  Write-Host "Skip: Firebird 3 not found on this machine. No action." -ForegroundColor Yellow
  return
}
if ($fb.Version.Major -ne 3) {
  Write-Host ("Skip: Installed Firebird is v{0} (not 3.x). No action." -f $fb.VersionString) -ForegroundColor Yellow
  return
}
# Determine installation type
$isClientOnlyInstall = $false
$needsServerUpgrade = $false

if ($fb.Version -ge $target) {
  Write-Host ("Firebird 3 is already {0} (>= 3.0.13). Installing client components..." -f $fb.VersionString) -ForegroundColor Cyan
  $isClientOnlyInstall = $true
} else {
  Write-Host ("Upgrade required: current {0} < 3.0.13. Will upgrade server and then install client..." -f $fb.VersionString) -ForegroundColor Cyan
  $needsServerUpgrade = $true
}

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# --- TLS 1.2 ---
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Paths ---
$downloadDir  = Join-Path $env:TEMP "firebird-install"
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
$installerFile = Join-Path $downloadDir ([System.IO.Path]::GetFileName(($DownloadUrl -split '\?')[0]))

# --- Stop service (for both server upgrade and client installation) ---
$serviceWasRunning = $false
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
  $service = Get-Service -Name $ServiceName
  if ($service.Status -eq 'Running') {
    $serviceWasRunning = $true
    Write-Host ("Stopping service {0}..." -f $ServiceName) -ForegroundColor Cyan
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    (Get-Service -Name $ServiceName).WaitForStatus('Stopped',[TimeSpan]::FromMinutes(1))
  } else {
    Write-Host ("Service {0} is already stopped." -f $ServiceName) -ForegroundColor Yellow
  }
} else {
  Write-Host ("Service {0} not found (continuing)..." -f $ServiceName) -ForegroundColor Yellow
}

# Kill possible processes (important for both scenarios)
"fbserver","fbguard","firebird","fb_inet_server" | ForEach-Object {
  Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# --- Download installer (retry) ---
for ($i=1; $i -le 3; $i++) {
  try {
    Write-Host ("Downloading installer (attempt {0}/3)..." -f $i) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerFile -UseBasicParsing
    if ((Test-Path $installerFile) -and ((Get-Item $installerFile).Length -gt 1MB)) { break }
    throw "Downloaded file size suspicious."
  } catch {
    if ($i -eq 3) { throw }
    Start-Sleep -Seconds 3
  }
}

# --- Trust gate ---
if ($VerifySha256) {
  $hash = (Get-FileHash -Path $installerFile -Algorithm SHA256).Hash.ToLower()
  if ($hash -ne $ExpectedSha256.ToLower()) {
    throw ("Checksum mismatch! expected {0}, got {1}" -f $ExpectedSha256, $hash)
  }
  Write-Host ("SHA256 ok: {0}" -f $hash) -ForegroundColor Green
} elseif (-not $NoSignatureCheck) {
  $sig = Get-AuthenticodeSignature -FilePath $installerFile
  if ($sig.Status -ne 'Valid') {
    Write-Warning ("Installer Authenticode status: {0}" -f $sig.Status)
    throw "Aborting due to signature status."
  }
}

# --- Silent install (Inno Setup) ---
if ($isClientOnlyInstall) {
  # Client-only installation
  $arguments = @(
    '/SILENT',
    '/NORESTART',
    '/COMPONENTS="ClientComponent"',
    ('/TASKS="{0}"' -f $ClientTasks)
  )
  Write-Host "Installing Firebird client components only..." -ForegroundColor Cyan

  Write-Host ("Running installer: {0} {1}" -f (Split-Path $installerFile -Leaf), ($arguments -join ' ')) -ForegroundColor Cyan
  $proc = Start-Process -FilePath $installerFile -ArgumentList $arguments -Wait -PassThru
  $exitCode = $proc.ExitCode
  if ($exitCode -ne 0) { throw ("Installer exit code: {0}" -f $exitCode) }
  $didInstall = $true

} else {
  # Full server installation/upgrade FOLLOWED BY client installation
  Write-Host "Step 1: Installing/upgrading Firebird server..." -ForegroundColor Cyan
  $serverArguments = @(
    '/SILENT',
    '/NORESTART',
    ('/TASKS="{0}"' -f $Tasks)
  )

  Write-Host ("Running server installer: {0} {1}" -f (Split-Path $installerFile -Leaf), ($serverArguments -join ' ')) -ForegroundColor Cyan
  $proc = Start-Process -FilePath $installerFile -ArgumentList $serverArguments -Wait -PassThru
  $exitCode = $proc.ExitCode
  if ($exitCode -ne 0) { throw ("Server installer exit code: {0}" -f $exitCode) }

  # Now install client components
  Write-Host "Step 2: Installing Firebird client components..." -ForegroundColor Cyan
  $clientArguments = @(
    '/SILENT',
    '/NORESTART',
    '/COMPONENTS="ClientComponent"',
    ('/TASKS="{0}"' -f $ClientTasks)
  )

  Write-Host ("Running client installer: {0} {1}" -f (Split-Path $installerFile -Leaf), ($clientArguments -join ' ')) -ForegroundColor Cyan
  $proc2 = Start-Process -FilePath $installerFile -ArgumentList $clientArguments -Wait -PassThru
  $clientExitCode = $proc2.ExitCode
  if ($clientExitCode -ne 0) { throw ("Client installer exit code: {0}" -f $clientExitCode) }

  $didInstall = $true
}

# --- Start service ---
$svcStartOk = $false
if ($isClientOnlyInstall) {
  # For client-only installation, start service only if it was running before
  if ($serviceWasRunning) {
    try {
      Write-Host ("Restarting service {0} (was running before client installation)..." -f $ServiceName) -ForegroundColor Cyan
      Start-Service -Name $ServiceName
      (Get-Service -Name $ServiceName).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
      $svcStartOk = $true
    } catch {
      Write-Warning ("Could not restart service {0}: {1}" -f $ServiceName, $_.Exception.Message)
    }
  } else {
    Write-Host ("Service {0} was not running before client installation - leaving stopped." -f $ServiceName) -ForegroundColor Yellow
    $svcStartOk = $true  # Consider this OK since we're not trying to start it
  }
} else {
  # For server upgrade, always try to start the service
  try {
    Write-Host ("Starting service {0}..." -f $ServiceName) -ForegroundColor Cyan
    Start-Service -Name $ServiceName
    (Get-Service -Name $ServiceName).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    $svcStartOk = $true
  } catch {
    Write-Warning ("Could not start service {0}: {1}" -f $ServiceName, $_.Exception.Message)
  }
}

# --- Detect installed version ---
function Get-FirebirdInstallPath {
  $regPath = 'HKLM:\SOFTWARE\Firebird Project\Firebird Server\Instances'
  $val = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue)."DefaultInstance"
  if ($val -and (Test-Path $val)) { return $val }
  foreach ($c in @("C:\Program Files\Firebird\Firebird_3_0","C:\Program Files (x86)\Firebird\Firebird_3_0")) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

$fbPath = Get-FirebirdInstallPath
$version = $null
if ($fbPath) {
  $exe = Join-Path $fbPath "fbserver.exe"
  if (-not (Test-Path $exe)) { $exe = Join-Path $fbPath "firebird.exe" }
  if (Test-Path $exe) { $version = (Get-Item $exe).VersionInfo.ProductVersion }
}

# --- SUMMARY ---
$svcStatus = "unknown"
try { $svcStatus = (Get-Service -Name $ServiceName -ErrorAction Stop).Status } catch {}

Write-Host ""
Write-Host "== SUMMARY ==" -ForegroundColor Green
if ($isClientOnlyInstall) {
  Write-Host "Installation type: CLIENT COMPONENTS ONLY" -ForegroundColor Cyan
} else {
  Write-Host "Installation type: SERVER UPGRADE + CLIENT COMPONENTS" -ForegroundColor Cyan
}
Write-Host ("Service: {0} -> {1}" -f $ServiceName, $svcStatus)
Write-Host ("Installer: {0}" -f $installerFile)
if ($version) { Write-Host ("Detected version: {0}" -f $version) }
Write-Host ("Completed successfully (installer exit code = {0})." -f $exitCode) -ForegroundColor Green

if (-not $svcStartOk) {
  if ($fbPath) {
    $log = Join-Path $fbPath "firebird.log"
    if (Test-Path $log) {
      Write-Host "`nLast 80 lines of firebird.log:" -ForegroundColor Yellow
      Get-Content $log -Tail 80
    }
  }
}

# === FBVERPUSH (download & run at the end) ===
if ($RunFbVerPush -and $didInstall) {
function ConvertTo-RawGithubUrl {
  param([Parameter(Mandatory=$true)][string]$Url)
  if ($Url -match '^https?://github\.com/.+?/blob/.+$') {
    return $Url -replace '^https?://github\.com/','https://raw.githubusercontent.com/' -replace '/blob/','/'
  }
  return $Url
}

if ($RunFbVerPush) {
  try {
    $rawUrl = ConvertTo-RawGithubUrl -Url $FbVerPushUrl
    $fbVerPushPath = Join-Path $downloadDir "fbverpush.ps1"
    Write-Host ("Downloading fbverpush from: {0}" -f $rawUrl) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $rawUrl -OutFile $fbVerPushPath -UseBasicParsing

    if (-not (Test-Path $fbVerPushPath) -or (Get-Item $fbVerPushPath).Length -lt 1KB) {
      throw "fbverpush.ps1 download looks suspicious (size < 1KB)."
    }

    # Zbuduj bezpieczny łańcuch argumentów (PS 5.1 nie lubi nulli w ArgumentList)
    $fbArgsSafe = @()
    if ($null -ne $FbVerPushArgs) {
      $fbArgsSafe = $FbVerPushArgs | Where-Object { $_ -ne $null -and $_ -ne '' }
    }

    # Escaping parametrów (spacje/cudzysłowy)
    $quotedArgs = $fbArgsSafe | ForEach-Object {
      if ($_ -match '[\s"`]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
    }

    $argStr = '-NoProfile -ExecutionPolicy Bypass -File ' + ('"{0}"' -f $fbVerPushPath)
    if ($quotedArgs.Count -gt 0) { $argStr += ' ' + ($quotedArgs -join ' ') }

    Write-Host ("Running fbverpush.ps1 {0}" -f ($quotedArgs -join ' ')) -ForegroundColor Cyan
    $p2 = Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -Wait -PassThru
    Write-Host ("fbverpush exit code: {0}" -f $p2.ExitCode) -ForegroundColor Green
  } catch {
    Write-Warning ("fbverpush failed: {0}" -f $_.Exception.Message)
  }
}
} else {
  Write-Host "Skipping fbverpush (no install performed or disabled)." -ForegroundColor Yellow
}