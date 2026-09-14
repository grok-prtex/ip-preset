using System.Text.Json.Serialization;

namespace IpPreset.Core.Models;

/// <summary>
/// IP設定を適用するモード。
/// </summary>
public enum PresetMode
{
    Dhcp,
    Static
}

/// <summary>
/// 名前付きのネットワーク設定プリセット。
/// presets.json にこの型のリストとして保存されます。
/// </summary>
public sealed class NetworkPreset
{
    /// <summary>プリセットの表示名（例: 「本社オフィス」「A工場ライン1」）。</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>"dhcp" または "static"。</summary>
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public PresetMode Mode { get; set; } = PresetMode.Dhcp;

    /// <summary>静的IPv4アドレス（Mode=Static のとき必須）。</summary>
    public string? Ipv4 { get; set; }

    /// <summary>CIDRのプレフィックス長（例: 24）。SubnetMask とどちらか一方を指定します。</summary>
    public int? PrefixLength { get; set; }

    /// <summary>サブネットマスク（例: 255.255.255.0）。PrefixLength とどちらか一方を指定します。</summary>
    public string? SubnetMask { get; set; }

    /// <summary>デフォルトゲートウェイ（任意）。</summary>
    public string? Gateway { get; set; }

    /// <summary>DNSサーバーのリスト（任意、最大2件程度を想定）。</summary>
    public List<string> Dns { get; set; } = new();

    /// <summary>メモ（任意）。</summary>
    public string? Note { get; set; }

    public NetworkPreset Clone()
    {
        return new NetworkPreset
        {
            Name = Name,
            Mode = Mode,
            Ipv4 = Ipv4,
            PrefixLength = PrefixLength,
            SubnetMask = SubnetMask,
            Gateway = Gateway,
            Dns = new List<string>(Dns),
            Note = Note
        };
    }

    public override string ToString() => Name;
}
