using IpPreset.Core.Net;

namespace IpPreset.Tests;

public class IpUtilsTests
{
    [Theory]
    [InlineData("255.255.255.0", 24)]
    [InlineData("255.255.0.0", 16)]
    [InlineData("255.0.0.0", 8)]
    [InlineData("255.255.255.255", 32)]
    [InlineData("0.0.0.0", 0)]
    [InlineData("255.255.255.252", 30)]
    public void TryMaskToPrefixLength_ConvertsValidMasks(string mask, int expected)
    {
        var ok = IpUtils.TryMaskToPrefixLength(mask, out var result);

        Assert.True(ok);
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("255.255.255.1")] // 不連続なビット
    [InlineData("not-an-ip")]
    [InlineData("")]
    [InlineData(null)]
    public void TryMaskToPrefixLength_RejectsInvalidMasks(string? mask)
    {
        var ok = IpUtils.TryMaskToPrefixLength(mask, out _);

        Assert.False(ok);
    }

    [Theory]
    [InlineData(24, "255.255.255.0")]
    [InlineData(16, "255.255.0.0")]
    [InlineData(0, "0.0.0.0")]
    [InlineData(32, "255.255.255.255")]
    public void PrefixLengthToMask_ConvertsCorrectly(int prefix, string expectedMask)
    {
        var mask = IpUtils.PrefixLengthToMask(prefix);

        Assert.Equal(expectedMask, mask);
    }

    [Fact]
    public void PrefixLengthToMask_ThrowsForOutOfRange()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => IpUtils.PrefixLengthToMask(33));
        Assert.Throws<ArgumentOutOfRangeException>(() => IpUtils.PrefixLengthToMask(-1));
    }

    [Theory]
    [InlineData("192.168.1.1", true)]
    [InlineData("255.255.255.255", true)]
    [InlineData("999.1.1.1", false)]
    [InlineData("not-an-ip", false)]
    [InlineData("", false)]
    public void IsValidIPv4_Works(string value, bool expected)
    {
        Assert.Equal(expected, IpUtils.IsValidIPv4(value));
    }

    [Fact]
    public void TryResolvePrefixLength_PrefersExplicitPrefixLength()
    {
        var ok = IpUtils.TryResolvePrefixLength(24, "255.255.0.0", out var result);

        Assert.True(ok);
        Assert.Equal(24, result);
    }

    [Fact]
    public void TryResolvePrefixLength_FallsBackToSubnetMask()
    {
        var ok = IpUtils.TryResolvePrefixLength(null, "255.255.255.0", out var result);

        Assert.True(ok);
        Assert.Equal(24, result);
    }

    [Fact]
    public void TryResolvePrefixLength_FailsWhenBothMissing()
    {
        var ok = IpUtils.TryResolvePrefixLength(null, null, out _);

        Assert.False(ok);
    }
}
