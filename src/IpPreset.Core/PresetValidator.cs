using IpPreset.Core.Models;
using IpPreset.Core.Net;

namespace IpPreset.Core;

/// <summary>
/// プリセットの入力内容を検証します。UI（保存前）とApply実行前の両方から利用されます。
/// </summary>
public static class PresetValidator
{
    /// <summary>検証エラーのメッセージ一覧を返します。空リストなら問題なしです。</summary>
    public static List<string> Validate(NetworkPreset preset)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(preset.Name))
        {
            errors.Add("プリセット名を入力してください。");
        }

        if (preset.Mode == PresetMode.Static)
        {
            if (!IpUtils.IsValidIPv4(preset.Ipv4))
            {
                errors.Add("IPv4アドレスの形式が正しくありません（例: 192.168.1.50）。");
            }

            if (!IpUtils.TryResolvePrefixLength(preset.PrefixLength, preset.SubnetMask, out _))
            {
                errors.Add("プレフィックス長（0〜32）またはサブネットマスクを正しく指定してください。");
            }

            if (!string.IsNullOrWhiteSpace(preset.Gateway) && !IpUtils.IsValidIPv4(preset.Gateway))
            {
                errors.Add("デフォルトゲートウェイの形式が正しくありません。");
            }

            foreach (var dns in preset.Dns)
            {
                if (!IpUtils.IsValidIPv4(dns))
                {
                    errors.Add($"DNSサーバーの形式が正しくありません: {dns}");
                }
            }
        }

        return errors;
    }

    public static bool IsValid(NetworkPreset preset) => Validate(preset).Count == 0;
}
