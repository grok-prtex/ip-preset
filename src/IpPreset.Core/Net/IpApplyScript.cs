namespace IpPreset.Core.Net;

/// <summary>
/// 実際にIP設定を変更するPowerShellスクリプトの中身。
/// 値はコマンドライン引数（-IfIndex, -IpAddress など）として渡すため、
/// このスクリプト自体にはプリセットの値を文字列展開しません（インジェクション対策）。
/// </summary>
public static class IpApplyScript
{
    public const string FileName = "IpPreset.Apply.ps1";

    public const string Content = """
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][ValidateSet('Dhcp','Static')][string]$Mode,
            [Parameter(Mandatory=$true)][int]$IfIndex,
            [string]$IpAddress = '',
            [int]$PrefixLength = -1,
            [string]$Gateway = '',
            [string]$Dns = ''
        )

        $ErrorActionPreference = 'Stop'

        function Remove-ExistingIPv4Address {
            param([int]$IfIndex)
            Get-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        }

        try {
            if ($Mode -eq 'Static') {
                if ([string]::IsNullOrWhiteSpace($IpAddress)) {
                    throw 'IPv4アドレスが指定されていません。'
                }
                if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
                    throw 'プレフィックス長が不正です。'
                }

                Remove-ExistingIPv4Address -IfIndex $IfIndex

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
                    $dnsList = $Dns -split ',' | Where-Object { $_ -ne '' }
                    Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $dnsList
                }
            }
            else {
                Remove-ExistingIPv4Address -IfIndex $IfIndex
                Set-NetIPInterface -InterfaceIndex $IfIndex -Dhcp Enabled
                Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses
            }

            Write-Output 'RESULT_OK'
        }
        catch {
            Write-Error $_.Exception.Message
            exit 1
        }
        """;
}
