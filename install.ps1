# serial-console installer / updater:
#   irm https://raw.githubusercontent.com/jensopt/serial-console/main/install.ps1 | iex
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo     = 'https://raw.githubusercontent.com/jensopt/serial-console/main'
    $exeDir   = Join-Path $env:LOCALAPPDATA 'Programs\SerialTerm'
    $profDir  = Join-Path $env:APPDATA 'SerialTerm\profiles'
    $profiles = 'fortigate', 'fortiswitch', 'fortiap'
    $docs     = [Environment]::GetFolderPath('MyDocuments')
    $tmp      = Join-Path ([IO.Path]::GetTempPath()) ('serial-console-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $tmp | Out-Null

    try {
        # 1. SerialTerm: latest GitHub release for this CPU, verified against the release's SHA256 digest.
        $arch = if ("$([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" -eq 'Arm64') { 'arm64' } else { 'x64' }
        $rel = Invoke-RestMethod 'https://api.github.com/repos/AdamKeher/SerialTerm/releases/latest' -Headers @{ 'User-Agent' = 'serial-console-installer' }
        $asset = $rel.assets | Where-Object { $_.name -eq "SerialTerm-win-$arch.zip" }
        if (-not $asset) { throw "Release $($rel.tag_name) has no SerialTerm-win-$arch.zip." }

        Write-Host "Downloading SerialTerm $($rel.tag_name) ($arch)..."
        $zip = Join-Path $tmp $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
        if ("$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') {
            if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $Matches[1]) { throw 'SHA256 mismatch on the SerialTerm download; nothing installed.' }
            Write-Host '  SHA256 verified'
        } else { Write-Warning 'Release has no SHA256 digest; download not verified.' }
        Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'st')
        $exe = Get-ChildItem (Join-Path $tmp 'st') -Recurse -Filter 'SerialTerm.exe' | Select-Object -First 1
        if (-not $exe) { throw 'SerialTerm.exe not found in the release zip.' }

        New-Item -ItemType Directory -Force $exeDir | Out-Null
        try { Copy-Item $exe.FullName $exeDir -Force }
        catch { throw 'SerialTerm.exe is in use. Close all serial sessions and run the installer again.' }
        Write-Host "  SerialTerm.exe  -> $exeDir"

        # 2. Add SerialTerm to the user PATH (kept as REG_EXPAND_SZ), so 'SerialTerm @fortigate' works too.
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        $userPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if (($userPath -split ';') -notcontains $exeDir) {
            $key.SetValue('Path', ((@($userPath.TrimEnd(';'), $exeDir) | Where-Object { $_ }) -join ';'), 'ExpandString')
            # Broadcast the change so new terminals pick it up.
            [Environment]::SetEnvironmentVariable('SERIAL_CONSOLE_TMP', '1', 'User')
            [Environment]::SetEnvironmentVariable('SERIAL_CONSOLE_TMP', $null, 'User')
            Write-Host "  user PATH       += $exeDir"
        }
        $key.Close()
        if (($env:Path -split ';') -notcontains $exeDir) { $env:Path += ";$exeDir" }

        # 3. PowerShell module, for PowerShell 7 and Windows PowerShell 5.1.
        foreach ($f in 'SerialConsole.psm1', 'SerialConsole.psd1') {
            Invoke-WebRequest "$repo/SerialConsole/$f" -OutFile (Join-Path $tmp $f) -UseBasicParsing
        }
        foreach ($ps in 'PowerShell', 'WindowsPowerShell') {
            $modDir = Join-Path $docs "$ps\Modules\SerialConsole"
            New-Item -ItemType Directory -Force $modDir | Out-Null
            Copy-Item (Join-Path $tmp 'SerialConsole.ps*1') $modDir -Force
            Write-Host "  module          -> $modDir"
        }

        # 4. SerialTerm profiles; existing ones are never overwritten.
        New-Item -ItemType Directory -Force $profDir | Out-Null
        foreach ($p in $profiles) {
            $dst = Join-Path $profDir "$p.rsp"
            if (Test-Path $dst) { Write-Host "  profile @$p kept (already exists)"; continue }
            Invoke-WebRequest "$repo/profiles/$p.rsp" -OutFile $dst -UseBasicParsing
            Write-Host "  profile @$p     -> $dst"
        }

        Import-Module SerialConsole -Global -Force
        Write-Host "`nDone. Type 'serial' to start, 'serial --help' for help. No PowerShell profile was changed." -ForegroundColor Green
    }
    catch { Write-Host "`nInstall failed: $($_.Exception.Message)" -ForegroundColor Red }
    finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
