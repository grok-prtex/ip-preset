using System.Net;

namespace IpPreset.Core.Net;

/// <summary>
/// IPv4アドレス・サブネットマスク・プレフィックス長を相互変換するための小さなユーティリティ。
/// </summary>
public static class IpUtils
{
    /// <summary>サブネットマスク文字列（例: 255.255.255.0）をプレフィックス長（例: 24）に変換します。</summary>
    public static bool TryMaskToPrefixLength(string? mask, out int prefixLength)
    {
        prefixLength = 0;
        if (string.IsNullOrWhiteSpace(mask))
        {
            return false;
        }

        if (!IPAddress.TryParse(mask, out var addr) || addr.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
        {
            return false;
        }

        var bytes = addr.GetAddressBytes();
        uint value = ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];

        // 有効なサブネットマスクは、上位ビットから連続した1、その後連続した0である必要がある
        // （例: 11111111.11111111.11111111.00000000）。MSB (bit31) から順に確認する。
        var zeros = 0;
        var seenZero = false;
        for (var i = 31; i >= 0; i--)
        {
            var bit = (value >> i) & 1;
            if (bit == 0)
            {
                seenZero = true;
                zeros++;
            }
            else if (seenZero)
            {
                return false; // 0の後に1が来るのは不正なマスク
            }
        }

        prefixLength = 32 - zeros;
        return true;
    }

    /// <summary>プレフィックス長（例: 24）をサブネットマスク文字列（例: 255.255.255.0）に変換します。</summary>
    public static string PrefixLengthToMask(int prefixLength)
    {
        if (prefixLength < 0 || prefixLength > 32)
        {
            throw new ArgumentOutOfRangeException(nameof(prefixLength), "プレフィックス長は0〜32の範囲で指定してください。");
        }

        uint mask = prefixLength == 0 ? 0 : 0xFFFFFFFF << (32 - prefixLength);
        var bytes = new byte[]
        {
            (byte)((mask >> 24) & 0xFF),
            (byte)((mask >> 16) & 0xFF),
            (byte)((mask >> 8) & 0xFF),
            (byte)(mask & 0xFF)
        };
        return new IPAddress(bytes).ToString();
    }

    /// <summary>文字列が有効なIPv4アドレスかどうかを判定します。</summary>
    public static bool IsValidIPv4(string? value)
    {
        return !string.IsNullOrWhiteSpace(value)
            && IPAddress.TryParse(value, out var addr)
            && addr.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork;
    }

    /// <summary>
    /// プリセットが持つ PrefixLength / SubnetMask のいずれかから、有効なプレフィックス長を解決します。
    /// </summary>
    public static bool TryResolvePrefixLength(int? prefixLength, string? subnetMask, out int resolved)
    {
        if (prefixLength is >= 0 and <= 32)
        {
            resolved = prefixLength.Value;
            return true;
        }

        if (TryMaskToPrefixLength(subnetMask, out resolved))
        {
            return true;
        }

        resolved = 0;
        return false;
    }
}
