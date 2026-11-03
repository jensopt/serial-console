# Serial console picker for Fortinet devices, on top of SerialTerm.
#   serial            pick device type, then COM port, then connect
#   serial --help     help
# Extra arguments go to SerialTerm, e.g. serial --log boot.log

$script:Devices = @(
    [pscustomobject]@{ Name = 'FortiGate';   Baud = 9600 }
    [pscustomobject]@{ Name = 'FortiSwitch'; Baud = 115200 }
    [pscustomobject]@{ Name = 'FortiAP';     Baud = 9600 }
    [pscustomobject]@{ Name = 'Other (115200)'; Baud = 115200 }
    [pscustomobject]@{ Name = 'Other (9600)';   Baud = 9600 }
)

# In-session SerialTerm keys (Ctrl+A, then key). ESP32/PICO-only keys left out.
$script:SessionKeys = @(
    @('q', 'quit'),            @('l', 'log on/off'),        @('s', 'send text file'),
    @('b', 'send break'),      @('#', 'change baud'),       @('d', 'disconnect/reconnect'),
    @('i', 'port settings'),   @('f', 'freeze screen'),     @('v', 'hex view'),
    @('o', 'local echo'),      @('c', 'clear screen'),      @('t', 'DTR/RTS lines'),
    @('1-9', 'send macro'),    @('?', 'key help'),          @('Ctrl+A', 'literal Ctrl+A')
)

function Format-SerialKeys {
    param([string]$Indent = '  ')
    for ($i = 0; $i -lt $script:SessionKeys.Count; $i += 3) {
        $Indent + (($script:SessionKeys[$i..([Math]::Min($i + 2, $script:SessionKeys.Count - 1))] |
            ForEach-Object { '{0,-7}{1,-22}' -f $_[0], $_[1] }) -join '')
    }
}

function Get-SerialTermExe {
    $cmd = Get-Command SerialTerm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @("$env:LOCALAPPDATA\Programs\SerialTerm\SerialTerm.exe")
    if ($env:ASPIDA_VAULT) { $candidates += Join-Path $env:ASPIDA_VAULT 'bin\SerialTerm.exe' }
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-SerialPorts {
    param([string]$Exe)
    & $Exe list 2>$null | ForEach-Object {
        if ($_ -match '^\s*\d+\s+(COM\d+)\s+(.*)$') {
            [pscustomobject]@{ Port = $Matches[1]; Device = $Matches[2].Trim(); Bluetooth = $Matches[2] -match 'Bluetooth' }
        }
    } | Sort-Object Bluetooth, { [int]($_.Port -replace '\D') }
}

# Minimal list picker: returns the chosen index, -1 on Esc, -2 on R (refresh) when -Refresh is set.
function Select-SerialItem {
    param([string]$Title, [string[]]$Rows, [string]$Footer, [switch]$Refresh)
    $esc = [char]27; $index = 0
    [Console]::Write("$esc[?1049h$esc[?25l")
    try {
        while ($true) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add(''); $lines.Add("  $esc[1m$Title$esc[0m"); $lines.Add('  ' + ('─' * 60))
            for ($i = 0; $i -lt $Rows.Count; $i++) {
                $row = '{0} {1}' -f $(if ($i -eq $index) { '>' } else { ' ' }), $Rows[$i]
                $lines.Add($(if ($i -eq $index) { "  $esc[7m$row$esc[0m" } else { "  $row" }))
            }
            if (-not $Rows) { $lines.Add("  $esc[90m(nothing found)$esc[0m") }
            $lines.Add(''); $lines.Add("  $esc[90m$Footer$esc[0m")
            $lines.Add(''); $lines.Add("  $esc[1mDuring the session: Ctrl+A, then$esc[0m")
            foreach ($l in (Format-SerialKeys -Indent '  ')) { $lines.Add("$esc[90m$l$esc[0m") }
            [Console]::Write("$esc[H$esc[J" + ($lines -join "`n"))
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                'UpArrow'   { if ($index -gt 0) { $index-- } }
                'DownArrow' { if ($index -lt $Rows.Count - 1) { $index++ } }
                'Escape'    { return -1 }
                'Enter'     { if ($Rows) { return $index } }
                'R'         { if ($Refresh) { return -2 } }
                default     { if ($k.KeyChar -match '[1-9]' -and [int]"$($k.KeyChar)" -le $Rows.Count) { return [int]"$($k.KeyChar)" - 1 } }
            }
        }
    }
    finally { [Console]::Write("$esc[?25h$esc[?1049l") }
}

function Show-SerialHelp {
    $b = "$([char]27)[1m"; $r = "$([char]27)[0m"
    @"

${b}serial — serial console picker (SerialTerm)${r}

  serial             pick device type, then COM port, then connect
  serial --help      this help (also -h, -?, help)
  Extra arguments go to SerialTerm:  serial --log boot.log   serial --timestamp abs

${b}DEVICE TYPES${r}
$(($script:Devices | ForEach-Object { '  {0,-16} {1} baud' -f $_.Name, $_.Baud }) -join "`n")

${b}KEYS${r}
  Picker     Up/Down or 1-9 · Enter select · R refresh ports (after plugging in) · Esc back/cancel

${b}DURING THE SESSION${r}  (Ctrl+A, then key)
$((Format-SerialKeys) -join "`n")

  Ports are sorted USB/real first, Bluetooth links last.
  SerialTerm is found on PATH, in %LOCALAPPDATA%\Programs\SerialTerm or in <vault>\bin.

"@ | Write-Host
}

function serial {
    if ($args.Count -and $args[0] -in '--help', '-h', '-?', '/?', 'help') { Show-SerialHelp; return }
    $exe = Get-SerialTermExe
    if (-not $exe) { Write-Warning 'SerialTerm.exe not found (PATH, %LOCALAPPDATA%\Programs\SerialTerm, <vault>\bin).'; return }

    while ($true) {
        $d = Select-SerialItem -Title 'Serial console – device type' -Footer 'Up/Down or 1-9 · Enter select · Esc cancel' `
            -Rows ($script:Devices | ForEach-Object { '{0,-16} {1,6} baud' -f $_.Name, $_.Baud })
        if ($d -lt 0) { return }
        $device = $script:Devices[$d]

        while ($true) {
            $ports = @(Get-SerialPorts -Exe $exe)
            $p = Select-SerialItem -Title "Serial console – $($device.Name) – COM port" -Refresh `
                -Footer 'Up/Down or 1-9 · Enter connect · R refresh · Esc back' `
                -Rows ($ports | ForEach-Object { '{0,-6} {1}' -f $_.Port, $_.Device })
            if ($p -eq -2) { continue }
            break
        }
        if ($p -lt 0) { continue }   # Esc on ports: back to device type
        $port = $ports[$p]
        Write-Host "Serial · $($device.Name) · $($port.Port) @ $($device.Baud) · Ctrl+A q quit · Ctrl+A ? keys" -ForegroundColor Cyan
        & $exe --port $port.Port --baud $device.Baud --status-line @args
        return
    }
}

Export-ModuleMember -Function serial
