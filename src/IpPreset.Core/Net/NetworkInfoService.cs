using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.Versioning;

namespace IpPreset.Core.Net;

/// <summary>
/// System.Net.NetworkInformation を使って、ネットワークアダプターの一覧と
/// 現在のIPv4設定を取得します（読み取り専用・管理者権限不要）。
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class NetworkInfoService
{
    /// <summary>
    /// 利用可能なネットワークアダプターの一覧を返します。
    /// ループバックやトンネルなど、通常ユーザーが設定対象にしないものは除外します。
    /// </summary>
    public List<AdapterInfo> GetAdapters()
    {
        var result = new List<AdapterInfo>();

        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback
                or NetworkInterfaceType.Tunnel
                or NetworkInterfaceType.Unknown)
            {
                continue;
            }

            var props = nic.GetIPProperties();
            var ipv4Props = TryGetIPv4Properties(nic);

            result.Add(new AdapterInfo
            {
                Name = nic.Name,
                Description = nic.Description,
                InterfaceIndex = ipv4Props?.Index ?? -1,
                Status = nic.OperationalStatus.ToString(),
                MacAddress = FormatMac(nic.GetPhysicalAddress())
            });
        }

        return result
            .OrderByDescending(a => a.Status == "Up")
            .ThenBy(a => a.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>指定したインターフェイスインデックスの現在のIPv4設定を取得します。</summary>
    public CurrentIpConfig? GetCurrentConfig(int interfaceIndex)
    {
        var nic = NetworkInterface.GetAllNetworkInterfaces()
            .FirstOrDefault(n => TryGetIPv4Properties(n)?.Index == interfaceIndex);

        if (nic is null)
        {
            return null;
        }

        var props = nic.GetIPProperties();
        var ipv4Props = TryGetIPv4Properties(nic);

        var config = new CurrentIpConfig
        {
            DhcpEnabled = ipv4Props?.IsDhcpEnabled ?? false,
            Gateway = props.GatewayAddresses
                .Select(g => g.Address)
                .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)?.ToString(),
            DnsServers = props.DnsAddresses
                .Where(a => a.AddressFamily == AddressFamily.InterNetwork)
                .Select(a => a.ToString())
                .ToList()
        };

        foreach (var unicast in props.UnicastAddresses)
        {
            if (unicast.Address.AddressFamily != AddressFamily.InterNetwork)
            {
                continue;
            }

            config.Ipv4Addresses.Add(unicast.Address.ToString());
            if (config.SubnetMask is null && unicast.IPv4Mask is not null)
            {
                config.SubnetMask = unicast.IPv4Mask.ToString();
                if (IpUtils.TryMaskToPrefixLength(config.SubnetMask, out var prefix))
                {
                    config.PrefixLength = prefix;
                }
            }
        }

        return config;
    }

    private static IPv4InterfaceProperties? TryGetIPv4Properties(NetworkInterface nic)
    {
        try
        {
            if (!nic.Supports(NetworkInterfaceComponent.IPv4))
            {
                return null;
            }

            return nic.GetIPProperties().GetIPv4Properties();
        }
        catch (NetworkInformationException)
        {
            return null;
        }
    }

    private static string FormatMac(PhysicalAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes.Length == 0 ? string.Empty : string.Join("-", bytes.Select(b => b.ToString("X2")));
    }
}
