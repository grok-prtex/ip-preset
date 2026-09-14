using IpPreset.Core;
using IpPreset.Core.Models;

namespace IpPreset.Tests;

public class PresetStoreTests : IDisposable
{
    private readonly string _tempDir;

    public PresetStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "IpPresetTests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_tempDir, recursive: true);
        }
        catch
        {
            // テスト後片付けの失敗は無視
        }
    }

    [Fact]
    public void Load_WhenFileMissing_ReturnsEmptyList()
    {
        var store = PresetStore.CreateDefault(_tempDir);

        var presets = store.Load();

        Assert.Empty(presets);
        Assert.False(store.Exists);
    }

    [Fact]
    public void SaveThenLoad_RoundTripsPresetData()
    {
        var store = PresetStore.CreateDefault(_tempDir);
        var original = new List<NetworkPreset>
        {
            new()
            {
                Name = "テスト現場A",
                Mode = PresetMode.Static,
                Ipv4 = "10.0.0.5",
                PrefixLength = 24,
                Gateway = "10.0.0.1",
                Dns = new List<string> { "10.0.0.1", "8.8.8.8" },
                Note = "現場Aのメモ"
            },
            new()
            {
                Name = "自動取得",
                Mode = PresetMode.Dhcp
            }
        };

        store.Save(original);
        var loaded = store.Load();

        Assert.Equal(2, loaded.Count);
        Assert.Equal("テスト現場A", loaded[0].Name);
        Assert.Equal(PresetMode.Static, loaded[0].Mode);
        Assert.Equal("10.0.0.5", loaded[0].Ipv4);
        Assert.Equal(24, loaded[0].PrefixLength);
        Assert.Equal(2, loaded[0].Dns.Count);
        Assert.Equal(PresetMode.Dhcp, loaded[1].Mode);
    }

    [Fact]
    public void EnsureSeeded_WritesDefaultsOnlyWhenMissing()
    {
        var store = PresetStore.CreateDefault(_tempDir);
        var defaults = DefaultPresets.CreateSamples();

        store.EnsureSeeded(defaults);
        Assert.True(store.Exists);

        var loadedOnce = store.Load();
        Assert.Equal(defaults.Count, loadedOnce.Count);

        // 既に存在する場合は上書きしない
        store.Save(new List<NetworkPreset> { new() { Name = "カスタム", Mode = PresetMode.Dhcp } });
        store.EnsureSeeded(defaults);

        var loadedTwice = store.Load();
        Assert.Single(loadedTwice);
        Assert.Equal("カスタム", loadedTwice[0].Name);
    }

    [Fact]
    public void FilePath_IsNextToBaseDirectory()
    {
        var store = PresetStore.CreateDefault(_tempDir);

        Assert.Equal(Path.Combine(_tempDir, "presets.json"), store.FilePath);
    }

    [Fact]
    public void Load_ParsesCamelCaseJson_LikePresetsExampleJson()
    {
        var json = """
        [
          { "name": "自動取得（DHCP）", "mode": "dhcp" },
          {
            "name": "本社オフィス",
            "mode": "static",
            "ipv4": "192.168.1.50",
            "prefixLength": 24,
            "gateway": "192.168.1.1",
            "dns": ["192.168.1.1", "8.8.8.8"]
          }
        ]
        """;
        var path = Path.Combine(_tempDir, "presets.json");
        File.WriteAllText(path, json);
        var store = new PresetStore(path);

        var presets = store.Load();

        Assert.Equal(2, presets.Count);
        Assert.Equal(PresetMode.Dhcp, presets[0].Mode);
        Assert.Equal(PresetMode.Static, presets[1].Mode);
        Assert.Equal("192.168.1.50", presets[1].Ipv4);
        Assert.Equal(24, presets[1].PrefixLength);
        Assert.Equal(2, presets[1].Dns.Count);
    }
}
