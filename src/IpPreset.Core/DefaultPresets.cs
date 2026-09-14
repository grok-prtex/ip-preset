using IpPreset.Core.Models;

namespace IpPreset.Core;

/// <summary>
/// presets.json が存在しない場合に、初回起動時に書き出す既定のサンプルプリセット。
/// </summary>
public static class DefaultPresets
{
    public static List<NetworkPreset> CreateSamples() => new()
    {
        new NetworkPreset
        {
            Name = "自動取得（DHCP）",
            Mode = PresetMode.Dhcp,
            Note = "通常のオフィス・自宅ネットワークなど、DHCPサーバーがある環境向けです。"
        },
        new NetworkPreset
        {
            Name = "工場ライン例（静的IP）",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.10.50",
            PrefixLength = 24,
            Gateway = "192.168.10.1",
            Dns = new List<string> { "192.168.10.1" },
            Note = "サンプルです。現場のIP体系に合わせて編集してください。"
        }
    };
}
