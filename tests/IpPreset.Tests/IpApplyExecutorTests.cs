using IpPreset.Core.Models;
using IpPreset.Core.Net;

namespace IpPreset.Tests;

public class IpApplyExecutorTests
{
    [Fact]
    public void BuildArguments_StaticPreset_IncludesAllExpectedFlags()
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

        var args = IpApplyExecutor.BuildArguments("C:\\temp\\script.ps1", 12, preset);

        Assert.Contains("-Mode", args);
        Assert.Contains("Static", args);
        Assert.Contains("-IfIndex", args);
        Assert.Contains("12", args);
        Assert.Contains("-IpAddress", args);
        Assert.Contains("192.168.1.50", args);
        Assert.Contains("-PrefixLength", args);
        Assert.Contains("24", args);
        Assert.Contains("-Gateway", args);
        Assert.Contains("192.168.1.1", args);
        Assert.Contains("-Dns", args);
        Assert.Contains("8.8.8.8,1.1.1.1", args);
    }

    [Fact]
    public void BuildArguments_StaticPreset_ResolvesSubnetMaskToPrefixLength()
    {
        var preset = new NetworkPreset
        {
            Name = "工場ライン2",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            SubnetMask = "255.255.255.0"
        };

        var args = IpApplyExecutor.BuildArguments("script.ps1", 5, preset);
        var prefixIndex = args.IndexOf("-PrefixLength");

        Assert.True(prefixIndex >= 0);
        Assert.Equal("24", args[prefixIndex + 1]);
    }

    [Fact]
    public void BuildArguments_DhcpPreset_OmitsStaticOnlyFlags()
    {
        var preset = new NetworkPreset { Name = "自動取得", Mode = PresetMode.Dhcp };

        var args = IpApplyExecutor.BuildArguments("script.ps1", 3, preset);

        Assert.Contains("Dhcp", args);
        Assert.DoesNotContain("-IpAddress", args);
        Assert.DoesNotContain("-Gateway", args);
        Assert.DoesNotContain("-Dns", args);
    }

    [Fact]
    public void BuildArguments_StaticPresetWithoutGatewayOrDns_OmitsOptionalFlags()
    {
        var preset = new NetworkPreset
        {
            Name = "ゲートウェイなし",
            Mode = PresetMode.Static,
            Ipv4 = "192.168.1.50",
            PrefixLength = 24
        };

        var args = IpApplyExecutor.BuildArguments("script.ps1", 3, preset);

        Assert.DoesNotContain("-Gateway", args);
        Assert.DoesNotContain("-Dns", args);
    }

    [Fact]
    public void Apply_InvalidPreset_ReturnsFailureWithoutLaunchingProcess()
    {
        var executor = new IpApplyExecutor(Path.Combine(Path.GetTempPath(), "IpPresetTests_ExecDir_" + Guid.NewGuid().ToString("N")));
        var invalidPreset = new NetworkPreset { Name = "", Mode = PresetMode.Static };

        var result = executor.Apply(1, invalidPreset);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Error);
    }

    [Fact]
    public void EnsureScriptWritten_WritesScriptFileWithExpectedContent()
    {
        var dir = Path.Combine(Path.GetTempPath(), "IpPresetTests_ScriptDir_" + Guid.NewGuid().ToString("N"));
        try
        {
            var executor = new IpApplyExecutor(dir);
            var path = executor.EnsureScriptWritten();

            Assert.True(File.Exists(path));
            Assert.Equal(IpApplyScript.Content, File.ReadAllText(path));
        }
        finally
        {
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }
}
