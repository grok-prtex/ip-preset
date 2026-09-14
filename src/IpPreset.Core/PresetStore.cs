using System.Text.Json;
using System.Text.Json.Serialization;
using IpPreset.Core.Models;

namespace IpPreset.Core;

/// <summary>
/// presets.json の読み込み・保存を担当します。
/// ポータブル運用（USBメモリ等）を優先し、既定では実行ファイルと同じフォルダの
/// presets.json を使用します。
/// </summary>
public sealed class PresetStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public string FilePath { get; }

    public PresetStore(string filePath)
    {
        FilePath = filePath;
    }

    /// <summary>
    /// 実行ファイルと同じフォルダに presets.json を置く既定のストアを作成します。
    /// </summary>
    public static PresetStore CreateDefault(string baseDirectory)
    {
        return new PresetStore(Path.Combine(baseDirectory, "presets.json"));
    }

    public bool Exists => File.Exists(FilePath);

    /// <summary>
    /// presets.json を読み込みます。存在しない場合は空のリストを返します（例外にしません）。
    /// </summary>
    public List<NetworkPreset> Load()
    {
        if (!File.Exists(FilePath))
        {
            return new List<NetworkPreset>();
        }

        var json = File.ReadAllText(FilePath);
        if (string.IsNullOrWhiteSpace(json))
        {
            return new List<NetworkPreset>();
        }

        var presets = JsonSerializer.Deserialize<List<NetworkPreset>>(json, SerializerOptions);
        return presets ?? new List<NetworkPreset>();
    }

    /// <summary>
    /// プリセット一覧を presets.json に保存します。
    /// </summary>
    public void Save(IEnumerable<NetworkPreset> presets)
    {
        var dir = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        var json = JsonSerializer.Serialize(presets.ToList(), SerializerOptions);

        // 書き込み中のクラッシュ・強制終了による破損を避けるため、一時ファイル経由で置き換えます。
        var tempPath = FilePath + ".tmp";
        File.WriteAllText(tempPath, json);
        File.Copy(tempPath, FilePath, overwrite: true);
        File.Delete(tempPath);
    }

    /// <summary>
    /// 初回起動時、presets.json が存在しない場合にサンプル（既定プリセット）を書き出します。
    /// </summary>
    public void EnsureSeeded(IEnumerable<NetworkPreset> defaults)
    {
        if (!Exists)
        {
            Save(defaults);
        }
    }
}
