namespace IpPreset.Core.Net;

/// <summary>ネットワークアダプター（NIC）の一覧表示用情報。</summary>
public sealed class AdapterInfo
{
    /// <summary>Windowsのインターフェイス名（例: "イーサネット"）。New-NetIPAddress 等の -InterfaceAlias に使用。</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>アダプターの説明（例: "Realtek PCIe GbE Family Controller"）。</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>OSが割り当てるインターフェイスインデックス。PowerShellコマンドの -InterfaceIndex に使用。</summary>
    public int InterfaceIndex { get; set; }

    /// <summary>接続状態（Up/Down等）。</summary>
    public string Status { get; set; } = string.Empty;

    /// <summary>MACアドレス（表示用）。</summary>
    public string MacAddress { get; set; } = string.Empty;

    /// <summary>コンボボックス等での表示文字列。</summary>
    public override string ToString() => $"{Name}（{Description}） - {Status}";
}

/// <summary>選択中アダプターの現在のIPv4設定。</summary>
public sealed class CurrentIpConfig
{
    public bool DhcpEnabled { get; set; }
    public List<string> Ipv4Addresses { get; set; } = new();
    public string? SubnetMask { get; set; }
    public int? PrefixLength { get; set; }
    public string? Gateway { get; set; }
    public List<string> DnsServers { get; set; } = new();

    public string ToDisplayText()
    {
        var lines = new List<string>
        {
            $"モード: {(DhcpEnabled ? "DHCP（自動取得）" : "静的（手動設定）")}",
            $"IPv4アドレス: {(Ipv4Addresses.Count > 0 ? string.Join(", ", Ipv4Addresses) : "（未設定）")}"
        };

        if (!string.IsNullOrEmpty(SubnetMask))
        {
            lines.Add($"サブネットマスク: {SubnetMask}" + (PrefixLength.HasValue ? $" (/{PrefixLength})" : string.Empty));
        }

        lines.Add($"デフォルトゲートウェイ: {(string.IsNullOrEmpty(Gateway) ? "（未設定）" : Gateway)}");
        lines.Add($"DNSサーバー: {(DnsServers.Count > 0 ? string.Join(", ", DnsServers) : "（未設定）")}");

        return string.Join(Environment.NewLine, lines);
    }
}
