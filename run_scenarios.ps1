<#
.SYNOPSIS
    Windows-Pendant zu run_scenarios.sh: Über welchen Proxy geht der Traffic eines Robot-Tests
    mit der Browser Library, wenn Proxy-Variablen bzw. ein RCC-Proxyprofil gesetzt sind?

.DESCRIPTION
    Proxy A = localhost:3128 (per RCC-Profil bzw. Proxy-Env-Variablen)
    Proxy B = localhost:3129 (nur explizit in der Browser Library gesetzt)

    Ohne Docker: Beide Proxies sind mitmdump-Prozesse aus einem eigenen rcc-Environment
    (mitmproxy/robot.yaml). Das Addon mitmproxy/block_loopback.py weist Ziele auf localhost mit 502 ab,
    wie es ein Proxy auf einem anderen Host täte.

    rcc wird vorausgesetzt. Ohne -Rcc dient es nur dazu, die Environments zu bauen und zu aktivieren
    (rcc ht vars ohne Profil); die Proxy-Variablen setzt das Skript selbst und robot läuft direkt.

    Ergebnisse: results\windows-<env|rcc>[-auth]\scenarioN\ und ...\summary.txt

.PARAMETER Rcc
    rcc als Unterbau: RCC-Profil erzeugen/aktivieren, robot via "rcc task script".
.PARAMETER Auth
    Proxies verlangen Benutzer/Passwort (Env-Variablen/RCC-Profil bzw. New Browser proxy=).
.PARAMETER Fail
    Zusätzlich Szenario 5: NO_PROXY fehlt. Vor Browser Library 20.4.0 scheiterte daran die interne
    gRPC-Verbindung; getestet wird nur 20.6.0.
.PARAMETER Scenario
    Nur diese Szenarien ausführen.
.PARAMETER Timeout
    Sekunden pro robot-Lauf (Default 120); ein hängender Test blockiert so nicht den ganzen Lauf.

.EXAMPLE
    .\run_scenarios.ps1
.EXAMPLE
    .\run_scenarios.ps1 -Rcc -Auth
.EXAMPLE
    .\run_scenarios.ps1 -Rcc -Fail 5
#>
[CmdletBinding()]
param(
    [switch]$Rcc,
    [switch]$Auth,
    [switch]$Fail,
    [Parameter(ValueFromRemainingArguments = $true)]
    [int[]]$Scenario = @(),
    [int]$Timeout = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Nur die Variablen dieses Skripts bzw. des RCC-Profils sollen wirken, nicht die der aufrufenden Shell
# (rcc task script vererbt die Umgebung des aufrufenden Prozesses). Windows-Env ist case-insensitiv.
$ProxyVarNames = 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY'
foreach ($name in $ProxyVarNames) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }

$ProxyUser = 'proxyuser'
$ProxyPass = 's3cr3t'
$NoProxyList = 'localhost,127.0.0.1'
$Mode = if ($Rcc) { 'rcc' } else { 'env' }
$Run = $Mode + $(if ($Auth) { '-auth' } else { '' })
$Results = Join-Path 'results' "windows-$Run"
$RobotYaml = 'robot.yaml'   # Browser Library 20.6.0 (conda.yaml)
$Space = 'proxytest'
$ProxyA = if ($Auth) { "http://${ProxyUser}:${ProxyPass}@localhost:3128" } else { 'http://localhost:3128' }

function New-Scenario($Nr, $Proxy, $NoProxy, $Resource, $Expect) {
    [pscustomobject]@{ Nr = $Nr; Proxy = $Proxy; NoProxy = $NoProxy; Resource = $Resource; Expect = $Expect }
}
$Scenarios = @(
    New-Scenario 1 'A' 'ja' 'resources/browser_noproxy.resource' 'PASS'
    New-Scenario 2 'A' 'ja' 'resources/browser_proxyB.resource'  'PASS'
    New-Scenario 3 '-' '-'  'resources/browser_noproxy.resource' 'PASS'
    New-Scenario 4 '-' '-'  'resources/browser_proxyB.resource'  'PASS'
)
if ($Fail) { $Scenarios += New-Scenario 5 'A' 'nein' 'resources/browser_noproxy.resource' 'PASS' }
if ($Scenario.Count -gt 0) { $Scenarios = @($Scenarios | Where-Object { $Scenario -contains $_.Nr }) }

# --- Hilfsfunktionen -------------------------------------------------------------------------

function Invoke-Rcc {
    # rcc schreibt Fortschritt nach stderr; in Windows PowerShell 5.1 wäre das mit 'Stop' ein Fehler.
    param([string[]]$Arguments, [switch]$StdoutOnly)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($StdoutOnly) { $out = & rcc @Arguments 2>$null } else { $out = & rcc @Arguments 2>&1 }
        $out | ForEach-Object { "$_" }
    } finally { $ErrorActionPreference = $old }
}

function Get-RccProfile {
    $line = Invoke-Rcc @('config', 'switch') | Where-Object { $_ -match '^Currently active profile is: ' } | Select-Object -First 1
    if ($line) { $line -replace '^Currently active profile is: ', '' } else { '' }
}

function Get-HolotreeEnv {
    # robot.yaml + space -> Hashtable der Variablen, mit denen rcc das Environment aktiviert (baut es bei Bedarf)
    param([string]$RobotYaml, [string]$Space)
    $json = (Invoke-Rcc @('ht', 'vars', '-r', $RobotYaml, '--space', $Space, '--json') -StdoutOnly) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $json) { throw "rcc ht vars für $RobotYaml fehlgeschlagen" }
    $vars = @{}
    $parsed = $json | ConvertFrom-Json
    if ($parsed -is [array]) {
        foreach ($item in $parsed) { $vars[$item.key] = $item.value }
    } else {
        foreach ($prop in $parsed.PSObject.Properties) { $vars[$prop.Name] = $prop.Value }
    }
    foreach ($name in $ProxyVarNames) { $vars.Remove($name) }
    $vars
}

function ConvertTo-CmdArg([string]$Arg) {
    if ($Arg -match '[\s"]') { '"' + ($Arg -replace '"', '\"') + '"' } else { $Arg }
}

function Start-WithEnv {
    # Startet ein Kommando über cmd.exe mit Umleitung in eine Logdatei und gezielt gesetzter Umgebung.
    param([string]$Command, [string[]]$Arguments, [hashtable]$Environment, [string]$LogFile)
    $cmdline = (@($Command) + $Arguments | ForEach-Object { ConvertTo-CmdArg $_ }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = "/d /s /c `"$cmdline > `"$LogFile`" 2>&1`""
    $psi.WorkingDirectory = $PSScriptRoot   # Process.Start folgt nicht Set-Location
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($name in $ProxyVarNames) { $psi.EnvironmentVariables.Remove($name) }
    if ($Environment) {
        foreach ($key in $Environment.Keys) { $psi.EnvironmentVariables[$key] = [string]$Environment[$key] }
    }
    [System.Diagnostics.Process]::Start($psi)
}

function Stop-Tree($Process) {
    # Prozess samt Kindern (cmd -> rcc -> robot -> node -> chromium) beenden
    if ($Process -and -not $Process.HasExited) { & taskkill.exe /PID $Process.Id /T /F 2>&1 | Out-Null }
}

function Wait-Port([int]$Port) {
    for ($i = 0; $i -lt 120; $i++) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect('127.0.0.1', $Port)
            $client.Close()
            return
        } catch { Start-Sleep -Milliseconds 500 }
    }
    throw "Proxy auf Port $Port startet nicht"
}

function Start-Proxy([string]$Name, [int]$Port, [string]$Dir) {
    $mitmArgs = @('--listen-host', '127.0.0.1', '--listen-port', "$Port", '-s', (Resolve-Path 'mitmproxy/block_loopback.py').Path)
    if ($Auth) { $mitmArgs += @('--proxyauth', "${ProxyUser}:${ProxyPass}") }
    $proc = Start-WithEnv -Command 'mitmdump' -Arguments $mitmArgs -Environment $script:MitmEnv `
        -LogFile (Join-Path $Dir "$Name.log")
    Wait-Port $Port
    $proc
}

function Get-Hosts([string]$LogFile) {
    if (-not (Test-Path $LogFile)) { return '' }
    $targets = Select-String -Path $LogFile -Pattern ': (GET|POST|CONNECT) (\S+)' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique
    $targets -join ' '
}

function Get-407Count([string]$LogFile) {
    if (-not (Test-Path $LogFile)) { return 0 }
    @(Select-String -Path $LogFile -Pattern '<< 407').Count
}

function Write-RccProfile([string]$NoProxy) {
    # Schreibt profiles/<name>.yaml (UTF-8 ohne BOM), importiert es und gibt den Profilnamen zurück
    $name = 'proxytest-a'
    if ($Auth) { $name += '-auth' }
    if ($NoProxy -eq 'nein') { $name += '-nonoproxy' }
    $desc = 'RCC-Proxyprofil -> mitmproxy A (localhost:3128), erzeugt von run_scenarios.ps1'
    $lines = @("name: $name", "description: $desc", 'settings:', '  certificates:', '    verify-ssl: false', '  network:')
    if ($NoProxy -eq 'ja') { $lines += "    no-proxy: '$NoProxyList'" }
    $lines += @("    https-proxy: '$ProxyA'", "    http-proxy: '$ProxyA'", '  meta:', "    name: $name",
                "    description: $desc", '    source: Robotmk')
    New-Item -ItemType Directory -Force profiles | Out-Null
    $file = Join-Path (Resolve-Path profiles).Path "$name.yaml"
    [IO.File]::WriteAllLines($file, [string[]]$lines)
    Invoke-Rcc @('config', 'import', '-f', $file) | Out-Null
    $name
}

function Get-SystemProxyInfo {
    # Ohne proxy= in New Browser nutzt Chromium unter Windows die WinINET-Einstellungen des Benutzers.
    $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $enable = if ($is.PSObject.Properties['ProxyEnable']) { $is.ProxyEnable } else { 0 }
    $server = if ($is.PSObject.Properties['ProxyServer']) { $is.ProxyServer } else { '' }
    $pac = if ($is.PSObject.Properties['AutoConfigURL']) { $is.AutoConfigURL } else { '' }
    $winhttp = (& netsh.exe winhttp show proxy | Where-Object { $_ -match '\S' } | Select-Object -Skip 1) -join ' '
    "WinINET (HKCU): ProxyEnable=$enable ProxyServer='$server' AutoConfigURL='$pac' | WinHTTP: $($winhttp.Trim())"
}

# --- Vorbereitung ----------------------------------------------------------------------------

New-Item -ItemType Directory -Force $Results | Out-Null
$Summary = Join-Path $Results 'summary.txt'
Set-Content -Path $Summary -Value $null -Encoding utf8
function Write-Summary([string]$Text) { Write-Host $Text; Add-Content -Path $Summary -Value $Text -Encoding utf8 }

$OrigProfile = Get-RccProfile
$proxies = @()
try {
    # Environments ohne Profil bauen/aktivieren: Ein Proxyprofil zeigte jetzt auf noch nicht laufende Proxies.
    Invoke-Rcc @('config', 'switch', '-n') | Out-Null
    Write-Host 'Environments vorbereiten (rcc ht vars, beim ersten Mal dauert das) ...'
    $script:MitmEnv = Get-HolotreeEnv -RobotYaml 'mitmproxy/robot.yaml' -Space 'proxytest-mitmproxy'
    $script:MitmEnv['PYTHONUNBUFFERED'] = '1'   # Log-Zeilen sofort schreiben, mitmdump wird hart beendet
    $BaseRobotEnv = Get-HolotreeEnv -RobotYaml $RobotYaml -Space $Space
    $browserVersion = if ((Get-Content 'conda.yaml' -Raw) -match 'robotframework-browser==([0-9.]+)') { $Matches[1] } else { '?' }

    Write-Summary "Lauf: windows-$Run | Proxy A: $ProxyA | Proxy B: http://localhost:3129$(if ($Auth) { " (Auth ${ProxyUser}:${ProxyPass})" })"
    Write-Summary (Get-SystemProxyInfo)
    Write-Summary ''

    # --- Szenarien ---------------------------------------------------------------------------

    foreach ($s in $Scenarios) {
        $dir = Join-Path $Results "scenario$($s.Nr)"
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
        New-Item -ItemType Directory -Force $dir | Out-Null
        $resourceName = Split-Path $s.Resource -Leaf
        Write-Host "=== Szenario $($s.Nr): Proxy A=$($s.Proxy), NO_PROXY=$($s.NoProxy), Browser $browserVersion, $resourceName ==="

        $robotArgs = @('-v', "BROWSER_RESOURCE:$($s.Resource)", '-d', $dir, '--console', 'verbose')
        if ($Auth) { $robotArgs += @('-v', "PROXY_USER:$ProxyUser", '-v', "PROXY_PASS:$ProxyPass") }
        $robotArgs += 'proxy.robot'

        $proxies = @((Start-Proxy 'proxyA' 3128 $dir), (Start-Proxy 'proxyB' 3129 $dir))
        $console = Join-Path $dir 'robot_console.txt'

        if ($Rcc) {
            if ($s.Proxy -eq 'A') {
                $profileName = Write-RccProfile $s.NoProxy
                Invoke-Rcc @('config', 'switch', '-p', $profileName) | Out-Null
            }
            else { Invoke-Rcc @('config', 'switch', '-n') | Out-Null }
            Invoke-Rcc @('config', 'switch') | Set-Content (Join-Path $dir 'rcc_profile.txt') -Encoding utf8
            Invoke-Rcc @('ht', 'vars', '-r', $RobotYaml, '--space', $Space) | Set-Content (Join-Path $dir 'htvars.txt') -Encoding utf8
            $proc = Start-WithEnv -Command 'rcc' -LogFile $console `
                -Arguments (@('task', 'script', '-r', $RobotYaml, '--space', $Space, '--silent', '--', 'robot') + $robotArgs)
        } else {
            # Environment wie von rcc aktiviert, aber ohne Profil; die Proxy-Variablen setzt das Skript selbst
            $robotEnv = $BaseRobotEnv.Clone()
            if ($s.Proxy -eq 'A') {
                $robotEnv['HTTP_PROXY'] = $ProxyA
                $robotEnv['HTTPS_PROXY'] = $ProxyA
                if ($s.NoProxy -eq 'ja') { $robotEnv['NO_PROXY'] = $NoProxyList }
            }
            $ProxyVarNames | Where-Object { $robotEnv.ContainsKey($_) } | ForEach-Object { "$_=$($robotEnv[$_])" } |
                Set-Content (Join-Path $dir 'proxy_env.txt') -Encoding utf8
            $proc = Start-WithEnv -Command 'robot' -Arguments $robotArgs -Environment $robotEnv -LogFile $console
        }

        if ($proc.WaitForExit($Timeout * 1000)) {
            $rc = $proc.ExitCode
        } else {
            Stop-Tree $proc
            $proc.WaitForExit()
            Add-Content -Path $console -Value "### Abgebrochen nach ${Timeout}s (run_scenarios.ps1)"
            $rc = 124
        }
        foreach ($p in $proxies) { Stop-Tree $p }
        $proxies = @()

        $result = if ($rc -eq 0) { 'PASS' } else { 'FAIL' }
        $verdict = if ($result -eq $s.Expect) { 'wie erwartet' } else { "UNERWARTET (erwartet $($s.Expect))" }
        if ($rc -eq 124) { $result = "FAIL (Timeout ${Timeout}s)" }
        $envLines = (Select-String -Path $console -Pattern '(HTTPS?_PROXY|NO_PROXY)=(<nicht gesetzt>|\S*)' -CaseSensitive -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }) -join ' '
        Write-Summary "Szenario $($s.Nr) | Proxy A: $($s.Proxy) | NO_PROXY: $($s.NoProxy) | Browser $browserVersion | $resourceName"
        Write-Summary "  Ergebnis:         $result, $verdict"
        Write-Summary "  Env im Test:      $envLines"
        Write-Summary "  Test -> Proxy A:  $(Get-Hosts (Join-Path $dir 'proxyA.log'))"
        Write-Summary "  Test -> Proxy B:  $(Get-Hosts (Join-Path $dir 'proxyB.log'))"
        if ($Auth) {
            Write-Summary "  407 (ohne Auth):  Proxy A $(Get-407Count (Join-Path $dir 'proxyA.log'))x, Proxy B $(Get-407Count (Join-Path $dir 'proxyB.log'))x"
        }
        $grpc = Select-String -Path $console -Pattern 'Could not connect to the playwright process at [0-9.:]*[0-9]' | Select-Object -First 1
        if ($grpc) { Write-Summary "  gRPC-Fehler:      $($grpc.Matches[0].Value)" }
        Write-Summary ''
    }
} finally {
    foreach ($p in $proxies) { Stop-Tree $p }
    if ($OrigProfile -and $OrigProfile -ne 'default') { Invoke-Rcc @('config', 'switch', '-p', $OrigProfile) | Out-Null }
    else { Invoke-Rcc @('config', 'switch', '-n') | Out-Null }
    Write-Host "RCC-Profil zurückgesetzt auf: $(if ($OrigProfile) { $OrigProfile } else { '<keins>' })"
}
