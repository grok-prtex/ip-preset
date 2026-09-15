#Requires -Version 5.1
<#
.SYNOPSIS
  IPプリセット — ネットワークアダプターのIPv4設定をプリセットで切り替える WinForms GUI（PowerShell）

.DESCRIPTION
  配布の主成果物です。署名なし .exe の SmartScreen を避けるため PowerShell + .cmd で起動します。
  起動時に UAC（管理者）確認があります。

.NOTES
  presets.json は本スクリプトと同じフォルダに保存します（C# 版と同一スキーマ）。
#>
[CmdletBinding()]
param(
    [switch]$ApplyOnly,
    [ValidateSet('Dhcp', 'Static')]
    [string]$Mode,
    [int]$IfIndex = -1,
    [string]$IpAddress = '',
    [int]$PrefixLength = -1,
    [string]$Gateway = '',
    [string]$Dns = '',
    [string]$ResultFile = '',
    [string]$Preset = '',
    [switch]$ListPresets
)

$ErrorActionPreference = 'Stop'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:ScriptDir) { $script:ScriptDir = $PSScriptRoot }
$script:PresetsPath = Join-Path $script:ScriptDir 'presets.json'
$script:ScriptPath = $MyInvocation.MyCommand.Path
if (-not $script:ScriptPath) { $script:ScriptPath = $PSCommandPath }

# ---------------------------------------------------------------------------
# Apply-only path (elevated child process)
# ---------------------------------------------------------------------------
function Remove-ExistingIPv4Address {
    param([int]$InterfaceIndex)
    Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
}

function Invoke-IpApplyCore {
    param(
        [Parameter(Mandatory)][ValidateSet('Dhcp', 'Static')][string]$Mode,
        [Parameter(Mandatory)][int]$IfIndex,
        [string]$IpAddress = '',
        [int]$PrefixLength = -1,
        [string]$Gateway = '',
        [string]$Dns = ''
    )

    if ($Mode -eq 'Static') {
        if ([string]::IsNullOrWhiteSpace($IpAddress)) {
            throw 'IPv4アドレスが指定されていません。'
        }
        if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
            throw 'プレフィックス長が不正です。'
        }

        Remove-ExistingIPv4Address -InterfaceIndex $IfIndex

        Get-NetRoute -InterfaceIndex $IfIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        Set-NetIPInterface -InterfaceIndex $IfIndex -Dhcp Disabled -ErrorAction SilentlyContinue

        if ([string]::IsNullOrWhiteSpace($Gateway)) {
            New-NetIPAddress -InterfaceIndex $IfIndex -IPAddress $IpAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
        }
        else {
            New-NetIPAddress -InterfaceIndex $IfIndex -IPAddress $IpAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction Stop | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($Dns)) {
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses
        }
        else {
            $dnsList = $Dns -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $dnsList
        }
    }
    else {
        Remove-ExistingIPv4Address -InterfaceIndex $IfIndex
        Set-NetIPInterface -InterfaceIndex $IfIndex -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses
    }

    return 'RESULT_OK'
}

if ($ApplyOnly) {
    try {
        $out = Invoke-IpApplyCore -Mode $Mode -IfIndex $IfIndex -IpAddress $IpAddress `
            -PrefixLength $PrefixLength -Gateway $Gateway -Dns $Dns
        if ($ResultFile) {
            Set-Content -LiteralPath $ResultFile -Value $out -Encoding UTF8
        }
        else {
            Write-Output $out
        }
        exit 0
    }
    catch {
        $msg = $_.Exception.Message
        if ($ResultFile) {
            Set-Content -LiteralPath $ResultFile -Value $msg -Encoding UTF8
        }
        else {
            Write-Error $msg
        }
        exit 1
    }
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Always require admin on launch (skip for -ApplyOnly elevated child)
# ---------------------------------------------------------------------------
if (-not (Test-IsElevated)) {
    function Quote-Arg([string]$s) {
        if ($null -eq $s) { $s = '' }
        return '"' + ($s.Replace('"', '""')) + '"'
    }
    # UseShellExecute/Verb=RunAs では ArgumentList の空文字が欠落しやすいため、1本の引数文字列にする
    $argParts = New-Object System.Collections.Generic.List[string]
    foreach ($a in @('-NoProfile', '-ExecutionPolicy Bypass', '-STA', '-File', (Quote-Arg $script:ScriptPath))) {
        [void]$argParts.Add($a)
    }
    foreach ($key in $PSBoundParameters.Keys) {
        $val = $PSBoundParameters[$key]
        if ($val -is [System.Management.Automation.SwitchParameter]) {
            if ($val) { [void]$argParts.Add("-$key") }
        }
        else {
            [void]$argParts.Add("-$key")
            [void]$argParts.Add((Quote-Arg ([string]$val)))
        }
    }
    $arguments = $argParts -join ' '
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show(
                '管理者権限の承認が必要です。UAC で許可してください。',
                'IPプリセット',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } catch { }
        exit 1
    }
    if ($null -eq $proc) { exit 1 }
    exit $proc.ExitCode
}

# ---------------------------------------------------------------------------
# GUI requires STA
# ---------------------------------------------------------------------------
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    # $args drops named parameters; rebuild from $PSBoundParameters so -Preset etc. survive
    $relaunch = New-Object System.Collections.Generic.List[string]
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $MyInvocation.MyCommand.Path)) {
        [void]$relaunch.Add($a)
    }
    foreach ($key in $PSBoundParameters.Keys) {
        $val = $PSBoundParameters[$key]
        if ($val -is [System.Management.Automation.SwitchParameter]) {
            if ($val) { [void]$relaunch.Add("-$key") }
        }
        else {
            [void]$relaunch.Add("-$key")
            [void]$relaunch.Add([string]$val)
        }
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $relaunch.ToArray() -Wait
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
$script:AccentColor = [System.Drawing.ColorTranslator]::FromHtml('#FF6B2C')
$script:ErrorColor = [System.Drawing.ColorTranslator]::FromHtml('#B3261E')
# Subtle panel tones (status / presets / log) — not flashy
$script:StatusPanelBg = [System.Drawing.Color]::FromArgb(245, 246, 248)
$script:PresetPanelBg = [System.Drawing.SystemColors]::Window
$script:LogPanelBg = [System.Drawing.Color]::FromArgb(250, 250, 251)
$script:MutedText = [System.Drawing.SystemColors]::GrayText
$script:Hairline = [System.Drawing.Color]::FromArgb(220, 222, 226)


function Get-AppFont {
    param([float]$Size = 9.5, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    foreach ($name in @('Yu Gothic UI', 'Meiryo UI', 'Segoe UI')) {
        try {
            return New-Object System.Drawing.Font($name, $Size, $Style)
        }
        catch { }
    }
    return New-Object System.Drawing.Font('Microsoft Sans Serif', $Size, $Style)
}

function Test-ValidIPv4 {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$ip)) { return $false }
    return $ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function ConvertFrom-SubnetMaskToPrefix {
    param([string]$Mask)
    if (-not (Test-ValidIPv4 $Mask)) { return $null }
    $addr = [System.Net.IPAddress]::Parse($Mask)
    $bytes = $addr.GetAddressBytes()
    [uint32]$value = ([uint32]$bytes[0] -shl 24) -bor ([uint32]$bytes[1] -shl 16) -bor ([uint32]$bytes[2] -shl 8) -bor $bytes[3]
    $zeros = 0
    $seenZero = $false
    for ($i = 31; $i -ge 0; $i--) {
        $bit = ($value -shr $i) -band 1
        if ($bit -eq 0) {
            $seenZero = $true
            $zeros++
        }
        elseif ($seenZero) {
            return $null
        }
    }
    return (32 - $zeros)
}

function Resolve-PrefixLength {
    param($Preset)
    # 未指定時は一般的な /24（255.255.255.0）を既定にする
    if ($null -ne $Preset.prefixLength -and "$($Preset.prefixLength)" -ne '') {
        $pl = [int]$Preset.prefixLength
        if ($pl -ge 0 -and $pl -le 32) { return $pl }
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Preset.subnetMask)) {
        $fromMask = ConvertFrom-SubnetMaskToPrefix -Mask ([string]$Preset.subnetMask)
        if ($null -ne $fromMask) { return $fromMask }
        return $null
    }
    return 24
}

function Test-PresetValid {
    param($Preset)
    $errors = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace([string]$Preset.name)) {
        [void]$errors.Add('プリセット名を入力してください。')
    }
    $mode = ([string]$Preset.mode).ToLowerInvariant()
    if ($mode -eq 'static') {
        if (-not (Test-ValidIPv4 ([string]$Preset.ipv4))) {
            [void]$errors.Add('IPv4アドレスの形式が正しくありません（例: 192.168.1.50）。')
        }
        if ($null -eq (Resolve-PrefixLength $Preset)) {
            [void]$errors.Add('サブネットの指定が不正です。空欄、24、または 255.255.255.0 などを指定してください。')
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Preset.gateway) -and -not (Test-ValidIPv4 ([string]$Preset.gateway))) {
            [void]$errors.Add('デフォルトゲートウェイの形式が正しくありません。')
        }
        $dnsList = @()
        if ($Preset.dns) { $dnsList = @($Preset.dns) }
        foreach ($d in $dnsList) {
            if (-not (Test-ValidIPv4 ([string]$d))) {
                [void]$errors.Add("DNSサーバーの形式が正しくありません: $d")
            }
        }
    }
    return $errors
}

function Get-DefaultPresets {
    @(
        [pscustomobject]@{
            name = '自動取得（DHCP）'
            mode = 'dhcp'
            note = '通常のオフィス・自宅ネットワークなど、DHCPサーバーがある環境向けです。'
        }
        [pscustomobject]@{
            name         = '工場ライン例（静的IP）'
            mode         = 'static'
            ipv4         = '192.168.10.50'
            prefixLength = 24
            gateway      = '192.168.10.1'
            dns          = @('192.168.10.1')
            note         = 'サンプルです。現場のIP体系に合わせて編集してください。'
        }
    )
}

function ConvertTo-PresetObject {
    param($Raw)
    $mode = ([string]$Raw.mode).ToLowerInvariant()
    if ($mode -ne 'static') { $mode = 'dhcp' }
    $dns = @()
    if ($Raw.dns) { $dns = @($Raw.dns | ForEach-Object { [string]$_ }) }
    $obj = [ordered]@{
        name = [string]$Raw.name
        mode = $mode
    }
    if ($mode -eq 'static') {
        if ($Raw.ipv4) { $obj.ipv4 = [string]$Raw.ipv4 }
        if ($null -ne $Raw.prefixLength -and "$($Raw.prefixLength)" -ne '') {
            $obj.prefixLength = [int]$Raw.prefixLength
        }
        elseif ($Raw.subnetMask) {
            $obj.subnetMask = [string]$Raw.subnetMask
        }
        if ($Raw.gateway) { $obj.gateway = [string]$Raw.gateway }
        $obj.dns = $dns
    }
    if ($Raw.note) { $obj.note = [string]$Raw.note }
    return [pscustomobject]$obj
}

function Read-Presets {
    if (-not (Test-Path -LiteralPath $script:PresetsPath)) {
        $seed = @(Get-DefaultPresets)
        Write-Presets -Presets $seed
        return $seed
    }
    $json = Get-Content -LiteralPath $script:PresetsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $raw = $json | ConvertFrom-Json
    $list = @()
    foreach ($item in @($raw)) {
        $list += ConvertTo-PresetObject $item
    }
    return $list
}

function Write-Presets {
    param([object[]]$Presets)
    $normalized = @()
    foreach ($p in $Presets) {
        $normalized += ConvertTo-PresetObject $p
    }
    $json = $normalized | ConvertTo-Json -Depth 6
    if ($normalized.Count -eq 1) {
        # ConvertTo-Json emits a single object when Count=1; wrap as array
        $json = '[' + ($normalized[0] | ConvertTo-Json -Depth 6) + ']'
    }
    elseif ($normalized.Count -eq 0) {
        $json = '[]'
    }
    $tmp = $script:PresetsPath + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Copy($tmp, $script:PresetsPath, $true)
    [System.IO.File]::Delete($tmp)
}

function Get-AdapterList {
    $adapters = @()
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.HardwareInterface -eq $true -or $_.InterfaceDescription -notmatch 'Loopback|Tunnel|Pseudo' } |
            Sort-Object { if ($_.Status -eq 'Up') { 0 } else { 1 } }, Name)
    }
    catch {
        # fallback: all adapters except loopback names
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'Loopback' } |
            Sort-Object Name)
    }
    return $adapters
}

function Get-CurrentConfigText {
    param($Adapter)
    if (-not $Adapter) { return '（アダプターを選択してください）' }
    $ifIndex = [int]$Adapter.ifIndex
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("アダプター: $($Adapter.Name)")
    [void]$lines.Add("状態: $($Adapter.Status)")
    [void]$lines.Add("MAC: $($Adapter.MacAddress)")

    $ip = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1
    $iface = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $dhcp = if ($iface -and $iface.Dhcp -eq 'Enabled') { 'DHCP（自動取得）' } else { '静的' }
    [void]$lines.Add("モード: $dhcp")
    if ($ip) {
        [void]$lines.Add("IPv4: $($ip.IPAddress)/$($ip.PrefixLength)")
    }
    else {
        [void]$lines.Add('IPv4: （なし）')
    }
    $gw = Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty NextHop
    [void]$lines.Add("ゲートウェイ: $(if ($gw) { $gw } else { '（なし）' })")
    $dnsServers = @(Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ServerAddresses)
    $dnsText = if ($dnsServers.Count -gt 0) { ($dnsServers -join ', ') } else { '（なし）' }
    [void]$lines.Add("DNS: $dnsText")
    return ($lines -join "`r`n")
}

function Invoke-ApplyPreset {
    param(
        [Parameter(Mandatory)][int]$IfIndex,
        [Parameter(Mandatory)]$Preset
    )

    $mode = if (([string]$Preset.mode).ToLowerInvariant() -eq 'static') { 'Static' } else { 'Dhcp' }
    $prefix = -1
    $ip = ''
    $gw = ''
    $dnsCsv = ''
    if ($mode -eq 'Static') {
        $ip = [string]$Preset.ipv4
        $prefix = Resolve-PrefixLength $Preset
        if ($null -eq $prefix) { throw 'プレフィックス長を解決できませんでした。' }
        if ($Preset.gateway) { $gw = [string]$Preset.gateway }
        if ($Preset.dns) { $dnsCsv = (@($Preset.dns) -join ',') }
    }

    if (Test-IsElevated) {
        return (Invoke-IpApplyCore -Mode $mode -IfIndex $IfIndex -IpAddress $ip -PrefixLength $prefix -Gateway $gw -Dns $dnsCsv)
    }

    $resultFile = Join-Path $env:TEMP ("ippreset-apply-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    function Quote-Arg([string]$s) {
        if ($null -eq $s) { $s = '' }
        return '"' + ($s.Replace('"', '""')) + '"'
    }
    # UseShellExecute/Verb=RunAs では ArgumentList の空文字が欠落しやすいため、1本の引数文字列にする
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy Bypass'
        '-File'
        (Quote-Arg $script:ScriptPath)
        '-ApplyOnly'
        '-Mode'
        (Quote-Arg $mode)
        '-IfIndex'
        (Quote-Arg "$IfIndex")
        '-IpAddress'
        (Quote-Arg $ip)
        '-PrefixLength'
        (Quote-Arg "$prefix")
        '-Gateway'
        (Quote-Arg $gw)
        '-Dns'
        (Quote-Arg $dnsCsv)
        '-ResultFile'
        (Quote-Arg $resultFile)
    ) -join ' '

    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    }
    catch {
        # UAC cancel often surfaces as Win32 exception
        throw '管理者権限の承認がキャンセルされました。'
    }

    $output = ''
    if (Test-Path -LiteralPath $resultFile) {
        $output = Get-Content -LiteralPath $resultFile -Raw -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }

    if ($proc.ExitCode -ne 0 -or ($output -notmatch 'RESULT_OK')) {
        $detail = if ($output) { $output.Trim() } else { "終了コード $($proc.ExitCode)" }
        throw "適用に失敗しました: $detail"
    }
    return 'RESULT_OK'
}

function Show-PresetEditDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        $Initial
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'プリセットの編集'
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.ClientSize = New-Object System.Drawing.Size(460, 560)
    $dlg.Font = Get-AppFont
    $dlg.ShowInTaskbar = $false
    $dlg.Padding = New-Object System.Windows.Forms.Padding(0)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.AutoScroll = $true
    $layout.ColumnCount = 2
    $layout.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 8)
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 128)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $nameBox.ImeMode = [System.Windows.Forms.ImeMode]::Hiragana
    $dhcpRadio = New-Object System.Windows.Forms.RadioButton
    $dhcpRadio.Text = 'DHCP（自動取得）'
    $dhcpRadio.AutoSize = $true
    $staticRadio = New-Object System.Windows.Forms.RadioButton
    $staticRadio.Text = '静的（手動設定）'
    $staticRadio.AutoSize = $true
    $ipv4Box = New-Object System.Windows.Forms.TextBox
    $ipv4Box.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $subnetBox = New-Object System.Windows.Forms.TextBox
    $subnetBox.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $gatewayBox = New-Object System.Windows.Forms.TextBox
    $gatewayBox.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $dnsBox = New-Object System.Windows.Forms.TextBox
    $dnsBox.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $noteBox = New-Object System.Windows.Forms.TextBox
    $noteBox.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
    $noteBox.ImeMode = [System.Windows.Forms.ImeMode]::Hiragana
    $errorLabel = New-Object System.Windows.Forms.Label
    $errorLabel.ForeColor = $script:ErrorColor
    $errorLabel.AutoSize = $true
    $errorLabel.MaximumSize = New-Object System.Drawing.Size(290, 0)
    $errorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)

    function Add-LabeledRow([string]$labelText, [System.Windows.Forms.Control]$control, [string]$hint = $null) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $labelText
        $lbl.AutoSize = $true
        $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Left
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)
        [void]$layout.Controls.Add($lbl)
        $control.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 2)
        $control.Height = 28
        [void]$layout.Controls.Add($control)
        if ($hint) {
            $hintLbl = New-Object System.Windows.Forms.Label
            $hintLbl.Text = $hint
            $hintLbl.AutoSize = $true
            $hintLbl.ForeColor = $script:MutedText
            $hintLbl.Font = Get-AppFont -Size 8
            $hintLbl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
            [void]$layout.Controls.Add((New-Object System.Windows.Forms.Label))
            [void]$layout.Controls.Add($hintLbl)
        }
    }

    Add-LabeledRow 'プリセット名:' $nameBox
    $modePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $modePanel.AutoSize = $true
    $modePanel.WrapContents = $false
    $modePanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $modePanel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)
    $dhcpRadio.Margin = New-Object System.Windows.Forms.Padding(0, 4, 20, 4)
    $staticRadio.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    [void]$modePanel.Controls.Add($dhcpRadio)
    [void]$modePanel.Controls.Add($staticRadio)
    $modeLbl = New-Object System.Windows.Forms.Label
    $modeLbl.Text = 'モード:'
    $modeLbl.AutoSize = $true
    $modeLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $modeLbl.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)
    [void]$layout.Controls.Add($modeLbl)
    [void]$layout.Controls.Add($modePanel)

    Add-LabeledRow 'IPv4アドレス:' $ipv4Box '例: 192.168.1.50'
    Add-LabeledRow 'サブネット:' $subnetBox '任意。空欄なら 255.255.255.0（24）'
    Add-LabeledRow 'ゲートウェイ:' $gatewayBox '任意。例: 192.168.1.1'
    Add-LabeledRow 'DNSサーバー:' $dnsBox '任意。カンマ区切り（例: 8.8.8.8, 1.1.1.1）'
    Add-LabeledRow 'メモ:' $noteBox '任意'
    [void]$layout.Controls.Add((New-Object System.Windows.Forms.Label))
    [void]$layout.Controls.Add($errorLabel)

    $updateStatic = {
        $en = $staticRadio.Checked
        $ipv4Box.Enabled = $en
        $subnetBox.Enabled = $en
        $gatewayBox.Enabled = $en
        $dnsBox.Enabled = $en
    }.GetNewClosure()
    $dhcpRadio.Add_CheckedChanged($updateStatic)
    $staticRadio.Add_CheckedChanged($updateStatic)

    # load
    $nameBox.Text = [string]$Initial.name
    if (([string]$Initial.mode).ToLowerInvariant() -eq 'static') {
        $staticRadio.Checked = $true
    }
    else {
        $dhcpRadio.Checked = $true
    }
    $ipv4Box.Text = [string](if ($Initial.ipv4) { [string]$Initial.ipv4 } else { '' })
    if ($null -ne $Initial.prefixLength -and "$($Initial.prefixLength)" -ne '') {
        $subnetBox.Text = [string]$Initial.prefixLength
    }
    elseif ($Initial.subnetMask) {
        $subnetBox.Text = [string]$Initial.subnetMask
    }
    else {
        $subnetBox.Text = ''
    }
    $gatewayBox.Text = [string](if ($Initial.gateway) { [string]$Initial.gateway } else { '' })
    $dnsBox.Text = [string](if ($Initial.dns) { (@($Initial.dns) -join ', ') } else { '' })
    $noteBox.Text = [string](if ($Initial.note) { [string]$Initial.note } else { '' })
    & $updateStatic

    $btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $btnPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $btnPanel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 14)
    $btnPanel.Height = 60
    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'OK'
    $okBtn.Width = 96
    $okBtn.Height = 32
    $okBtn.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'キャンセル'
    $cancelBtn.Width = 96
    $cancelBtn.Height = 32
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$btnPanel.Controls.Add($cancelBtn)
    [void]$btnPanel.Controls.Add($okBtn)

    # GetNewClosure() creates a dynamic module; $script: vars there are invisible outside.
    # Capture a hashtable (reference type) so the OK handler can return the result.
    $editState = @{ Result = $null }
    $okBtn.Add_Click({
        [string]$mode = if ($staticRadio.Checked) { 'static' } else { 'dhcp' }
        $p = [ordered]@{
            name = $nameBox.Text.Trim()
            mode = $mode
        }
        if ($mode -eq 'static') {
            $p.ipv4 = $ipv4Box.Text.Trim()
            $subnetInput = $subnetBox.Text.Trim()
            if ($subnetInput -match '^\d{1,2}$' -and [int]$subnetInput -ge 0 -and [int]$subnetInput -le 32) {
                $p.prefixLength = [int]$subnetInput
            }
            elseif ($subnetInput) {
                $p.subnetMask = $subnetInput
            }
            if (-not [string]::IsNullOrWhiteSpace($gatewayBox.Text)) {
                $p.gateway = $gatewayBox.Text.Trim()
            }
            $dnsParts = @($dnsBox.Text -split '[, \t]+' | Where-Object { $_ -ne '' } | ForEach-Object { [string]$_ })
            $p.dns = [string[]]@($dnsParts)
        }
        if (-not [string]::IsNullOrWhiteSpace($noteBox.Text)) {
            $p.note = $noteBox.Text.Trim()
        }
        $obj = [pscustomobject]$p
        $errs = Test-PresetValid $obj
        if ($errs.Count -gt 0) {
            $errorLabel.Text = ($errs -join "`r`n")
            return
        }
        $editState.Result = ConvertTo-PresetObject $obj
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    }.GetNewClosure())

    # AcceptButton は付けない（日本語IMEの確定EnterがOKに吸われて名前入力できなくなる）
    $dlg.CancelButton = $cancelBtn
    # Dock Bottom first, then Fill — Fill added first would cover the buttons
    $dlg.Controls.Add($btnPanel)
    $dlg.Controls.Add($layout)

    $dlg.Add_Shown({
        $nameBox.Focus()
        $nameBox.SelectAll()
    }.GetNewClosure())

    $dr = $dlg.ShowDialog($Owner)
    if ($dr -eq [System.Windows.Forms.DialogResult]::OK) {
        return $editState.Result
    }
    return $null
}

function Show-AdapterPickDialog {
    param(
        [Parameter(Mandatory)][object[]]$Adapters,
        [string]$PresetName = ''
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'どのアダプターに適用しますか？'
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dlg.ClientSize = New-Object System.Drawing.Size(500, 390)
    $dlg.Font = Get-AppFont
    $dlg.ShowInTaskbar = $true

    $info = New-Object System.Windows.Forms.Label
    $info.Dock = [System.Windows.Forms.DockStyle]::Top
    $info.AutoSize = $false
    $info.Height = 56
    $info.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 8)
    $info.Font = Get-AppFont -Size 10
    $info.Text = [string](if ($PresetName) {
        "プリセット「$PresetName」を適用するアダプターを選んでください。"
    }
    else {
        '適用するアダプターを選んでください。'
    })

    $listHost = New-Object System.Windows.Forms.Panel
    $listHost.Dock = [System.Windows.Forms.DockStyle]::Fill
    $listHost.Padding = New-Object System.Windows.Forms.Padding(16, 4, 16, 4)
    $listHost.BackColor = $script:PresetPanelBg

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = [System.Windows.Forms.DockStyle]::Fill
    $list.IntegralHeight = $false
    $list.Font = Get-AppFont -Size 10
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    for ($i = 0; $i -lt $Adapters.Count; $i++) {
        $a = $Adapters[$i]
        [void]$list.Items.Add("[$($i + 1)] $($a.Name)  [$($a.Status)]")
    }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    $listHost.Controls.Add($list)

    $btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $btnPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $btnPanel.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 14)
    $btnPanel.Height = 60
    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text = '適用'
    $applyBtn.Width = 104
    $applyBtn.Height = 34
    $applyBtn.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $applyBtn.BackColor = $script:AccentColor
    $applyBtn.ForeColor = [System.Drawing.Color]::White
    $applyBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $applyBtn.FlatAppearance.BorderSize = 0
    $applyBtn.Font = Get-AppFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
    $applyBtn.UseVisualStyleBackColor = $false
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'キャンセル'
    $cancelBtn.Width = 104
    $cancelBtn.Height = 34
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$btnPanel.Controls.Add($cancelBtn)
    [void]$btnPanel.Controls.Add($applyBtn)

    # GetNewClosure() dynamic-module workaround: return via hashtable
    $pickState = @{ Result = $null }
    $applyBtn.Add_Click({
        if ($list.SelectedIndex -lt 0) { return }
        $pickState.Result = $Adapters[$list.SelectedIndex]
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    }.GetNewClosure())

    $list.Add_DoubleClick({
        if ($list.SelectedIndex -lt 0) { return }
        $pickState.Result = $Adapters[$list.SelectedIndex]
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    }.GetNewClosure())

    $dlg.AcceptButton = $applyBtn
    $dlg.CancelButton = $cancelBtn
    # Dock Bottom/Top before Fill — Fill added first would cover the buttons
    $dlg.Controls.Add($btnPanel)
    $dlg.Controls.Add($info)
    $dlg.Controls.Add($listHost)

    $null = $dlg.ShowDialog()
    if ($dlg.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $pickState.Result
    }
    return $null
}

# ---------------------------------------------------------------------------
# CLI: -ListPresets / -Preset (before main GUI)
# ---------------------------------------------------------------------------
if ($ListPresets) {
    try {
        $listPresets = @(Read-Presets)
    }
    catch {
        Write-Error "presets.json の読み込みに失敗しました: $($_.Exception.Message)"
        exit 1
    }
    foreach ($p in $listPresets) {
        $modeTag = if (([string]$p.mode).ToLowerInvariant() -eq 'static') { '静的' } else { 'DHCP' }
        Write-Output ("{0}  ({1})" -f [string]$p.name, $modeTag)
    }
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($Preset)) {
    try {
        $allPresets = @(Read-Presets)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "presets.json の読み込みに失敗しました: $($_.Exception.Message)",
            'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }

    $want = $Preset.Trim()
    $exact = @($allPresets | Where-Object { [string]$_.name -ieq $want })
    $chosen = $null
    if ($exact.Count -eq 1) {
        $chosen = $exact[0]
    }
    elseif ($exact.Count -gt 1) {
        $msg = "プリセット名が重複しています: $want"
        Write-Error $msg
        [System.Windows.Forms.MessageBox]::Show($msg, 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
    else {
        $prefix = @($allPresets | Where-Object {
                ([string]$_.name).StartsWith($want, [System.StringComparison]::OrdinalIgnoreCase)
            })
        if ($prefix.Count -eq 1) {
            $chosen = $prefix[0]
        }
        elseif ($prefix.Count -eq 0) {
            $msg = "プリセットが見つかりません: $want"
            Write-Error $msg
            [System.Windows.Forms.MessageBox]::Show($msg, 'IPプリセット',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            exit 1
        }
        else {
            $names = ($prefix | ForEach-Object { [string]$_.name }) -join ', '
            $msg = "プリセット名が曖昧です（複数一致）: $want`r`n候補: $names"
            Write-Error $msg
            [System.Windows.Forms.MessageBox]::Show($msg, 'IPプリセット',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            exit 1
        }
    }

    $errs = Test-PresetValid $chosen
    if ($errs.Count -gt 0) {
        $msg = ($errs -join "`r`n")
        Write-Error $msg
        [System.Windows.Forms.MessageBox]::Show($msg, '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }

    try {
        $adapters = @(Get-AdapterList)
    }
    catch {
        $adapters = @()
    }
    if ($adapters.Count -eq 0) {
        $msg = 'ネットワークアダプターが見つかりませんでした。'
        Write-Error $msg
        [System.Windows.Forms.MessageBox]::Show($msg, 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }

    $adapter = Show-AdapterPickDialog -Adapters $adapters -PresetName ([string]$chosen.name)
    if (-not $adapter) {
        exit 0
    }

    try {
        [void](Invoke-ApplyPreset -IfIndex ([int]$adapter.ifIndex) -Preset $chosen)
        [System.Windows.Forms.MessageBox]::Show(
            "プリセット「$([string]$chosen.name)」を「$($adapter.Name)」に適用しました。",
            'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        exit 0
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            '適用エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Main form
# ---------------------------------------------------------------------------
$script:Presets = @()
$script:Adapters = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'IPプリセット'
$form.ClientSize = New-Object System.Drawing.Size(800, 780)
$form.MinimumSize = New-Object System.Drawing.Size(720, 700)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = Get-AppFont
$form.BackColor = [System.Drawing.SystemColors]::Control

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount = 5
$root.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 14)
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 250)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 168)))

# Title (slightly stronger hierarchy, no chrome)
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'IPプリセット'
$titleLabel.AutoSize = $true
$titleLabel.Font = Get-AppFont -Size 14 -Style ([System.Drawing.FontStyle]::Bold)
$titleLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$titleHint = New-Object System.Windows.Forms.Label
$titleHint.Text = 'ネットワークアダプターの IPv4 設定をプリセットで切り替え'
$titleHint.AutoSize = $true
$titleHint.ForeColor = $script:MutedText
$titleHint.Font = Get-AppFont -Size 8.5
$titleHint.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$titleBlock = New-Object System.Windows.Forms.FlowLayoutPanel
$titleBlock.Dock = [System.Windows.Forms.DockStyle]::Fill
$titleBlock.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$titleBlock.WrapContents = $false
$titleBlock.AutoSize = $true
$titleBlock.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
[void]$titleBlock.Controls.Add($titleLabel)
[void]$titleBlock.Controls.Add($titleHint)

# Adapter row
$adapterRow = New-Object System.Windows.Forms.TableLayoutPanel
$adapterRow.Dock = [System.Windows.Forms.DockStyle]::Top
$adapterRow.AutoSize = $true
$adapterRow.ColumnCount = 3
$adapterRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
[void]$adapterRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$adapterRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$adapterRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

$adapterLabel = New-Object System.Windows.Forms.Label
$adapterLabel.Text = 'ネットワークアダプター:'
$adapterLabel.AutoSize = $true
$adapterLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 10, 0)

$adapterCombo = New-Object System.Windows.Forms.ComboBox
$adapterCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$adapterCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$adapterCombo.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 0)

$refreshAdapterBtn = New-Object System.Windows.Forms.Button
$refreshAdapterBtn.Text = '更新'
$refreshAdapterBtn.AutoSize = $true
$refreshAdapterBtn.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
$refreshAdapterBtn.MinimumSize = New-Object System.Drawing.Size(72, 28)

[void]$adapterRow.Controls.Add($adapterLabel, 0, 0)
[void]$adapterRow.Controls.Add($adapterCombo, 1, 0)
[void]$adapterRow.Controls.Add($refreshAdapterBtn, 2, 0)

# Current status
$statusGroup = New-Object System.Windows.Forms.GroupBox
$statusGroup.Text = '現在の状態'
$statusGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$statusGroup.Font = Get-AppFont -Size 9.5 -Style ([System.Drawing.FontStyle]::Bold)
$statusGroup.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)

$statusInner = New-Object System.Windows.Forms.TableLayoutPanel
$statusInner.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusInner.ColumnCount = 1
$statusInner.RowCount = 2
$statusInner.Padding = New-Object System.Windows.Forms.Padding(4, 6, 4, 2)
$statusInner.Font = Get-AppFont
[void]$statusInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$statusInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$currentConfigText = New-Object System.Windows.Forms.TextBox
$currentConfigText.Multiline = $true
$currentConfigText.ReadOnly = $true
$currentConfigText.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$currentConfigText.BackColor = $script:StatusPanelBg
$currentConfigText.Dock = [System.Windows.Forms.DockStyle]::Fill
$currentConfigText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$currentConfigText.WordWrap = $true
$currentConfigText.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$currentConfigText.Text = '（アダプターを選択してください）'
$currentConfigText.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

$refreshConfigBtn = New-Object System.Windows.Forms.Button
$refreshConfigBtn.Text = '再取得'
$refreshConfigBtn.AutoSize = $true
$refreshConfigBtn.MinimumSize = New-Object System.Drawing.Size(80, 28)

$configBtnRow = New-Object System.Windows.Forms.FlowLayoutPanel
$configBtnRow.Dock = [System.Windows.Forms.DockStyle]::Fill
$configBtnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$configBtnRow.AutoSize = $true
$configBtnRow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
[void]$configBtnRow.Controls.Add($refreshConfigBtn)

[void]$statusInner.Controls.Add($currentConfigText, 0, 0)
[void]$statusInner.Controls.Add($configBtnRow, 0, 1)
$statusGroup.Controls.Add($statusInner)

# Presets group
$presetGroup = New-Object System.Windows.Forms.GroupBox
$presetGroup.Text = 'プリセット'
$presetGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$presetGroup.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$presetGroup.Font = Get-AppFont -Size 9.5 -Style ([System.Drawing.FontStyle]::Bold)
$presetGroup.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)

$presetLayout = New-Object System.Windows.Forms.TableLayoutPanel
$presetLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$presetLayout.ColumnCount = 2
$presetLayout.RowCount = 1
$presetLayout.Padding = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)
$presetLayout.Font = Get-AppFont
[void]$presetLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$presetLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 176)))

$presetList = New-Object System.Windows.Forms.ListBox
$presetList.Dock = [System.Windows.Forms.DockStyle]::Fill
$presetList.Font = Get-AppFont -Size 10
$presetList.IntegralHeight = $false
$presetList.DisplayMember = 'Display'
$presetList.BackColor = $script:PresetPanelBg
$presetList.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$presetList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)

$buttonPanel = New-Object System.Windows.Forms.TableLayoutPanel
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttonPanel.ColumnCount = 1
$buttonPanel.RowCount = 7
$buttonPanel.Margin = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
for ($i = 0; $i -lt 4; $i++) {
    [void]$buttonPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
}
[void]$buttonPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$buttonPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$buttonPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$addBtn = New-Object System.Windows.Forms.Button
$addBtn.Text = '追加(&A)'
$editBtn = New-Object System.Windows.Forms.Button
$editBtn.Text = '編集(&E)'
$deleteBtn = New-Object System.Windows.Forms.Button
$deleteBtn.Text = '削除(&D)'
foreach ($b in @($addBtn, $editBtn, $deleteBtn)) {
    $b.Dock = [System.Windows.Forms.DockStyle]::Top
    $b.Height = 34
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
}

# Thin separator above apply
$applySep = New-Object System.Windows.Forms.Label
$applySep.AutoSize = $false
$applySep.Height = 1
$applySep.Dock = [System.Windows.Forms.DockStyle]::Top
$applySep.BackColor = $script:Hairline
$applySep.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)

$applyBtn = New-Object System.Windows.Forms.Button
$applyBtn.Text = '適用'
$applyBtn.Dock = [System.Windows.Forms.DockStyle]::Bottom
$applyBtn.Height = 52
$applyBtn.BackColor = $script:AccentColor
$applyBtn.ForeColor = [System.Drawing.Color]::White
$applyBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$applyBtn.FlatAppearance.BorderSize = 0
$applyBtn.Font = Get-AppFont -Size 12 -Style ([System.Drawing.FontStyle]::Bold)
$applyBtn.UseVisualStyleBackColor = $false
$applyBtn.Margin = New-Object System.Windows.Forms.Padding(0)

[void]$buttonPanel.Controls.Add($addBtn, 0, 0)
[void]$buttonPanel.Controls.Add($editBtn, 0, 1)
[void]$buttonPanel.Controls.Add($deleteBtn, 0, 2)
[void]$buttonPanel.Controls.Add($applySep, 0, 5)
[void]$buttonPanel.Controls.Add($applyBtn, 0, 6)
[void]$presetLayout.Controls.Add($presetList, 0, 0)
[void]$presetLayout.Controls.Add($buttonPanel, 1, 0)
$presetGroup.Controls.Add($presetLayout)

# Log
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = 'ログ'
$logGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$logGroup.Font = Get-AppFont -Size 9.5 -Style ([System.Drawing.FontStyle]::Bold)
$logGroup.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 10)
$logText = New-Object System.Windows.Forms.TextBox
$logText.Multiline = $true
$logText.ReadOnly = $true
$logText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logText.Dock = [System.Windows.Forms.DockStyle]::Fill
$logText.Font = New-Object System.Drawing.Font('Consolas', 9)
$logText.BackColor = $script:LogPanelBg
$logText.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$logText.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)
$logGroup.Controls.Add($logText)

[void]$root.Controls.Add($titleBlock, 0, 0)
[void]$root.Controls.Add($adapterRow, 0, 1)
[void]$root.Controls.Add($statusGroup, 0, 2)
[void]$root.Controls.Add($presetGroup, 0, 3)
[void]$root.Controls.Add($logGroup, 0, 4)
$form.Controls.Add($root)

function Append-Log {
    param([string]$Message, [switch]$IsError)
    $ts = Get-Date -Format 'HH:mm:ss'
    $prefix = if ($IsError) { '[エラー]' } else { '[情報]' }
    $logText.AppendText("$ts $prefix $Message`r`n")
}

function Get-SelectedAdapter {
    if ($adapterCombo.SelectedIndex -lt 0) { return $null }
    return $script:Adapters[$adapterCombo.SelectedIndex]
}

function Get-SelectedPreset {
    if ($presetList.SelectedIndex -lt 0) { return $null }
    return $script:Presets[$presetList.SelectedIndex]
}

function Update-CurrentConfig {
    $adapter = Get-SelectedAdapter
    try {
        $currentConfigText.Text = Get-CurrentConfigText -Adapter $adapter
    }
    catch {
        $currentConfigText.Text = '現在の状態の取得中にエラーが発生しました。'
        Append-Log "状態取得エラー: $($_.Exception.Message)" -IsError
    }
}

function Refresh-AdapterList {
    param([switch]$PreserveSelection)
    $prevName = $null
    if ($PreserveSelection) {
        $sel = Get-SelectedAdapter
        if ($sel) { $prevName = $sel.Name }
    }
    try {
        $script:Adapters = @(Get-AdapterList)
    }
    catch {
        $script:Adapters = @()
        Append-Log "アダプター一覧の取得に失敗しました: $($_.Exception.Message)" -IsError
    }
    $adapterCombo.Items.Clear()
    for ($i = 0; $i -lt $script:Adapters.Count; $i++) {
        $a = $script:Adapters[$i]
        [void]$adapterCombo.Items.Add("[$($i + 1)] $($a.Name)  [$($a.Status)]")
    }
    if ($script:Adapters.Count -eq 0) {
        Append-Log 'ネットワークアダプターが見つかりませんでした。' -IsError
        return
    }
    $idx = 0
    if ($prevName) {
        for ($i = 0; $i -lt $script:Adapters.Count; $i++) {
            if ($script:Adapters[$i].Name -eq $prevName) { $idx = $i; break }
        }
    }
    $adapterCombo.SelectedIndex = $idx
}

function Refresh-PresetList {
    $prevName = $null
    $sel = Get-SelectedPreset
    if ($sel) { $prevName = [string]$sel.name }
    $presetList.Items.Clear()
    foreach ($p in $script:Presets) {
        $modeTag = if (([string]$p.mode).ToLowerInvariant() -eq 'static') { '静的' } else { 'DHCP' }
        [void]$presetList.Items.Add("$($p.name)  ·  $modeTag")
    }
    if ($prevName) {
        for ($i = 0; $i -lt $script:Presets.Count; $i++) {
            if ([string]$script:Presets[$i].name -eq $prevName) {
                $presetList.SelectedIndex = $i
                break
            }
        }
    }
}

function Load-PresetsIntoUi {
    try {
        $script:Presets = @(Read-Presets)
    }
    catch {
        $script:Presets = @()
        Append-Log "presets.json の読み込みに失敗しました: $($_.Exception.Message)" -IsError
    }
    Refresh-PresetList
}

function Save-PresetsFromUi {
    try {
        Write-Presets -Presets $script:Presets
    }
    catch {
        Append-Log "presets.json の保存に失敗しました: $($_.Exception.Message)" -IsError
    }
}

function Set-Busy {
    param([bool]$Busy)
    $form.Cursor = if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    $applyBtn.Enabled = -not $Busy
    $addBtn.Enabled = -not $Busy
    $editBtn.Enabled = -not $Busy
    $deleteBtn.Enabled = -not $Busy
    $adapterCombo.Enabled = -not $Busy
    $refreshAdapterBtn.Enabled = -not $Busy
}

$adapterCombo.Add_SelectedIndexChanged({ Update-CurrentConfig })
$refreshAdapterBtn.Add_Click({ Refresh-AdapterList -PreserveSelection; Update-CurrentConfig })
$refreshConfigBtn.Add_Click({ Update-CurrentConfig })

$addBtn.Add_Click({
    $initial = [pscustomobject]@{ name = '新しいプリセット'; mode = 'dhcp' }
    $result = Show-PresetEditDialog -Owner $form -Initial $initial
    if ($null -eq $result) { return }
    $script:Presets += $result
    Save-PresetsFromUi
    Refresh-PresetList
    Append-Log "プリセット「$($result.name)」を追加しました。"
})

$editSelected = {
    $sel = Get-SelectedPreset
    if (-not $sel) {
        [System.Windows.Forms.MessageBox]::Show($form, '編集するプリセットを選択してください。', 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $idx = $presetList.SelectedIndex
    $result = Show-PresetEditDialog -Owner $form -Initial $sel
    if ($null -eq $result) { return }
    # 固定長 Object[] の要素差し替えが効かない環境向けに配列を作り直す
    $next = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $script:Presets.Count; $i++) {
        if ($i -eq $idx) { [void]$next.Add($result) } else { [void]$next.Add($script:Presets[$i]) }
    }
    $script:Presets = @($next)
    Save-PresetsFromUi
    Refresh-PresetList
    if ($idx -ge 0 -and $idx -lt $presetList.Items.Count) {
        $presetList.SelectedIndex = $idx
    }
    Append-Log "プリセット「$($result.name)」を更新しました。"
}
$editBtn.Add_Click($editSelected)
$presetList.Add_DoubleClick($editSelected)

$deleteBtn.Add_Click({
    $sel = Get-SelectedPreset
    if (-not $sel) {
        [System.Windows.Forms.MessageBox]::Show($form, '削除するプリセットを選択してください。', 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $form,
        "プリセット「$($sel.name)」を削除しますか？`r`nこの操作は元に戻せません。",
        '削除の確認',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $idx = $presetList.SelectedIndex
    $name = [string]$sel.name
    $list = New-Object System.Collections.ArrayList
    if ($null -ne $script:Presets) {
        [void]$list.AddRange(@($script:Presets))
    }
    [void]$list.RemoveAt($idx)
    $script:Presets = @($list)
    Save-PresetsFromUi
    Refresh-PresetList
    Append-Log "プリセット「$name」を削除しました。"
})

$applyBtn.Add_Click({
    $adapter = Get-SelectedAdapter
    if (-not $adapter) {
        [System.Windows.Forms.MessageBox]::Show($form, 'ネットワークアダプターを選択してください。', 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $preset = Get-SelectedPreset
    if (-not $preset) {
        [System.Windows.Forms.MessageBox]::Show($form, '適用するプリセットを選択してください。', 'IPプリセット',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $errs = Test-PresetValid $preset
    if ($errs.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show($form, ($errs -join "`r`n"), '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    [string]$modeText = if (([string]$preset.mode).ToLowerInvariant() -eq 'static') {
        [string]$gwText = if ($preset.gateway) { [string]$preset.gateway } else { 'なし' }
        "静的IP: $($preset.ipv4) / ゲートウェイ: $gwText"
    }
    else {
        'DHCP（自動取得）'
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $form,
        "アダプター「$($adapter.Name)」にプリセット「$($preset.name)」を適用します。`r`n設定内容: $modeText`r`n`r`n適用中は一時的にネットワーク接続が切断される場合があります。よろしいですか？",
        '適用の確認',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log '適用をキャンセルしました。'
        return
    }

    Set-Busy $true
    Append-Log "「$($preset.name)」を適用しています…"
    $form.Refresh()
    try {
        $null = Invoke-ApplyPreset -IfIndex ([int]$adapter.ifIndex) -Preset $preset
        Append-Log "「$($preset.name)」を適用しました。"
    }
    catch {
        Append-Log $_.Exception.Message -IsError
    }
    finally {
        Set-Busy $false
        Refresh-AdapterList -PreserveSelection
        Update-CurrentConfig
    }
})

$form.Add_Shown({
    [string]$elevNote = if (Test-IsElevated) { '管理者権限で起動しています。' } else { '管理者権限が必要です（起動時にUAC確認があります）。' }
    Append-Log "起動しました。$elevNote"
    Load-PresetsIntoUi
    Refresh-AdapterList
    Update-CurrentConfig
})

[System.Windows.Forms.Application]::Run($form)
