using IpPreset.Core;
using IpPreset.Core.Models;

namespace IpPreset.Tests;

public class PresetValidatorTests
{
    [Fact]
    public void Validate_DhcpPreset_OnlyRequiresName()
    {
        var preset = new NetworkPreset { Name = "自動取得", Mode = PresetMode.Dhcp };

        var errors = PresetValidator.Validate(preset);

        Assert.Empty(errors);
    }

    [Fact]
    public void Validate_MissingName_ReturnsError()
    {
        var preset = new NetworkPreset { Name = "", Mode = PresetMode.Dhcp };

        var errors = PresetValidator.Validate(preset);

        Assert.Contains(errors, e => e.Contains("プリセット名"));
    }

    [Fact]
    public void Validate_StaticPreset_ValidValues_ReturnsNoErrors()
    {
        var preset = new NetworkPreset
        {
            Name = "工場ライン1",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            PrefixLength = 24,
            Gateway = "192.168.1.1",
            Dns = new List<string> { "8.8.8.8", "1.1.1.1" }
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Empty(errors);
    }

    [Fact]
    public void Validate_StaticPreset_WithSubnetMaskInsteadOfPrefix_IsValid()
    {
        var preset = new NetworkPreset
        {
            Name = "工場ライン2",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            SubnetMask = "255.255.255.0"
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Empty(errors);
    }

    [Fact]
    public void Validate_StaticPreset_InvalidIp_ReturnsError()
    {
        var preset = new NetworkPreset
        {
            Name = "不正なIP",
            Mode = PresetMode.Static,
            Ipv4 = "999.999.999.999",
            PrefixLength = 24
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Contains(errors, e => e.Contains("IPv4アドレス"));
    }

    [Fact]
    public void Validate_StaticPreset_MissingPrefixAndMask_ReturnsError()
    {
        var preset = new NetworkPreset
        {
            Name = "サブネット未指定",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50"
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Contains(errors, e => e.Contains("プレフィックス長"));
    }

    [Fact]
    public void Validate_StaticPreset_InvalidGateway_ReturnsError()
    {
        var preset = new NetworkPreset
        {
            Name = "不正なゲートウェイ",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            PrefixLength = 24,
            Gateway = "invalid"
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Contains(errors, e => e.Contains("ゲートウェイ"));
    }

    [Fact]
    public void Validate_StaticPreset_InvalidDns_ReturnsError()
    {
        var preset = new NetworkPreset
        {
            Name = "不正なDNS",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            PrefixLength = 24,
            Dns = new List<string> { "not-an-ip" }
        };

        var errors = PresetValidator.Validate(preset);

        Assert.Contains(errors, e => e.Contains("DNS"));
    }
}
