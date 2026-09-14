namespace IpPreset.Core.Net;

/// <summary>IP設定適用処理の結果。</summary>
public sealed class IpApplyResult
{
    public bool Success { get; init; }
    public string Output { get; init; } = string.Empty;
    public string Error { get; init; } = string.Empty;
    public int ExitCode { get; init; }

    public static IpApplyResult Failed(string error) => new()
    {
        Success = false,
        Error = error,
        ExitCode = -1
    };
}
