using System.Diagnostics;
using IpPreset.Core.Models;

namespace IpPreset.Core.Net;

/// <summary>
/// プリセットの内容から PowerShell (Set-NetIPInterface / New-NetIPAddress /
/// Set-DnsClientServerAddress) 呼び出しを組み立てて実行します。
/// 値はすべてコマンドライン引数として渡すため、文字列連結によるインジェクションの心配はありません。
/// </summary>
public sealed class IpApplyExecutor
{
    private readonly string _workingDirectory;

    public IpApplyExecutor(string workingDirectory)
    {
        _workingDirectory = workingDirectory;
    }

    /// <summary>
    /// powershell.exe に渡す引数リストを組み立てます（テスト用に副作用なしで公開）。
    /// スクリプトファイルパスは呼び出し側で解決した実際のパスを渡してください。
    /// </summary>
    public static List<string> BuildArguments(string scriptPath, int interfaceIndex, NetworkPreset preset)
    {
        var args = new List<string>
        {
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", scriptPath,
            "-Mode", preset.Mode == PresetMode.Static ? "Static" : "Dhcp",
            "-IfIndex", interfaceIndex.ToString()
        };

        if (preset.Mode == PresetMode.Static)
        {
            if (!Net.IpUtils.TryResolvePrefixLength(preset.PrefixLength, preset.SubnetMask, out var prefixLength))
            {
                throw new InvalidOperationException("プレフィックス長を解決できませんでした。");
            }

            args.Add("-IpAddress");
            args.Add(preset.Ipv4 ?? string.Empty);
            args.Add("-PrefixLength");
            args.Add(prefixLength.ToString());

            if (!string.IsNullOrWhiteSpace(preset.Gateway))
            {
                args.Add("-Gateway");
                args.Add(preset.Gateway);
            }

            if (preset.Dns.Count > 0)
            {
                args.Add("-Dns");
                args.Add(string.Join(",", preset.Dns));
            }
        }

        return args;
    }

    /// <summary>
    /// スクリプトを一時フォルダに書き出します（未存在または内容不一致のときのみ上書き）。
    /// </summary>
    public string EnsureScriptWritten()
    {
        Directory.CreateDirectory(_workingDirectory);
        var path = Path.Combine(_workingDirectory, IpApplyScript.FileName);

        var needsWrite = true;
        if (File.Exists(path))
        {
            try
            {
                needsWrite = File.ReadAllText(path) != IpApplyScript.Content;
            }
            catch (IOException)
            {
                needsWrite = true;
            }
        }

        if (needsWrite)
        {
            File.WriteAllText(path, IpApplyScript.Content);
        }

        return path;
    }

    /// <summary>
    /// プリセットを指定インターフェイスに適用します。呼び出し元プロセスは管理者権限で
    /// 実行されている必要があります（本アプリはマニフェストで常に管理者権限を要求します）。
    /// </summary>
    public IpApplyResult Apply(int interfaceIndex, NetworkPreset preset)
    {
        var errors = PresetValidator.Validate(preset);
        if (errors.Count > 0)
        {
            return IpApplyResult.Failed(string.Join(Environment.NewLine, errors));
        }

        string scriptPath;
        List<string> args;
        try
        {
            scriptPath = EnsureScriptWritten();
            args = BuildArguments(scriptPath, interfaceIndex, preset);
        }
        catch (Exception ex)
        {
            return IpApplyResult.Failed(ex.Message);
        }

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args)
        {
            psi.ArgumentList.Add(a);
        }

        try
        {
            using var process = Process.Start(psi);
            if (process is null)
            {
                return IpApplyResult.Failed("PowerShellプロセスを起動できませんでした。");
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            var exited = process.WaitForExit(30000);
            if (!exited)
            {
                try { process.Kill(true); } catch { /* 終了処理の失敗は無視 */ }
                return IpApplyResult.Failed("処理がタイムアウトしました（30秒）。");
            }

            var stdout = stdoutTask.GetAwaiter().GetResult();
            var stderr = stderrTask.GetAwaiter().GetResult();

            return new IpApplyResult
            {
                Success = process.ExitCode == 0 && stdout.Contains("RESULT_OK", StringComparison.Ordinal),
                Output = stdout,
                Error = stderr,
                ExitCode = process.ExitCode
            };
        }
        catch (Exception ex)
        {
            return IpApplyResult.Failed($"PowerShellの実行に失敗しました: {ex.Message}");
        }
    }
}
