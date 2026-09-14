using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Text;
using IpPreset.Core.Models;

namespace IpPreset.Core.Net;

/// <summary>
/// プリセットの内容から PowerShell (Set-NetIPInterface / New-NetIPAddress /
/// Set-DnsClientServerAddress) 呼び出しを組み立てて実行します。
/// 値はすべてコマンドライン引数として渡すため、文字列連結によるインジェクションの心配はありません。
/// 非管理者プロセスから呼ぶ場合は PowerShell のみ Verb=runas で昇格します。
/// </summary>
public sealed class IpApplyExecutor
{
    private readonly string _workingDirectory;

    public IpApplyExecutor(string workingDirectory)
    {
        _workingDirectory = workingDirectory;
    }

    /// <summary>
    /// 現在のプロセスが管理者として実行されているか。
    /// </summary>
    public static bool IsElevated()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
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
    /// プリセットを指定インターフェイスに適用します。
    /// 非昇格プロセスの場合は PowerShell を Verb=runas で起動し、UAC 確認後に適用します。
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

        return IsElevated()
            ? RunPowerShellRedirected(args)
            : RunPowerShellElevated(scriptPath, args);
    }

    /// <summary>
    /// 既に管理者のとき: 標準出力・標準エラーをリダイレクトして実行。
    /// </summary>
    private static IpApplyResult RunPowerShellRedirected(List<string> args)
    {
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

    /// <summary>
    /// 非管理者のとき: UseShellExecute + Verb=runas で PowerShell のみ昇格。
    /// リダイレクト不可のため、ラッパースクリプト経由で結果を一時ファイルへ書き出します。
    /// </summary>
    private IpApplyResult RunPowerShellElevated(string scriptPath, List<string> applyArgs)
    {
        Directory.CreateDirectory(_workingDirectory);
        var id = Guid.NewGuid().ToString("N");
        var resultPath = Path.Combine(_workingDirectory, $"apply-result-{id}.txt");
        var wrapperPath = Path.Combine(_workingDirectory, $"apply-wrap-{id}.ps1");

        // applyArgs は -NoProfile ... -File script ... の形。ラッパーでは -File 以降を再実行する。
        var fileIndex = applyArgs.IndexOf("-File");
        if (fileIndex < 0 || fileIndex + 1 >= applyArgs.Count)
        {
            return IpApplyResult.Failed("適用引数の組み立てに失敗しました。");
        }

        var scriptArgs = applyArgs.Skip(fileIndex + 2).ToList();
        var wrapper = BuildElevatedWrapper(scriptPath, scriptArgs, resultPath);
        try
        {
            File.WriteAllText(wrapperPath, wrapper, Encoding.UTF8);
        }
        catch (Exception ex)
        {
            return IpApplyResult.Failed($"昇格用スクリプトの作成に失敗しました: {ex.Message}");
        }

        // UseShellExecute=true では ArgumentList が使えないため Arguments 文字列を使用。
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{wrapperPath}\""
        };

        try
        {
            using var process = Process.Start(psi);
            if (process is null)
            {
                return IpApplyResult.Failed("昇格付きPowerShellを起動できませんでした。");
            }

            // UAC 操作を含むため、リダイレクト時より長めに待つ。
            var exited = process.WaitForExit(120000);
            if (!exited)
            {
                try { process.Kill(true); } catch { /* ignore */ }
                return IpApplyResult.Failed("処理がタイムアウトしました（120秒）。");
            }

            var output = File.Exists(resultPath) ? File.ReadAllText(resultPath) : string.Empty;
            var cancelledOrDenied = process.ExitCode == int.MinValue; // not used; UAC cancel is Win32Exception

            return new IpApplyResult
            {
                Success = process.ExitCode == 0 && output.Contains("RESULT_OK", StringComparison.Ordinal),
                Output = output,
                Error = process.ExitCode == 0 ? string.Empty : output,
                ExitCode = process.ExitCode
            };
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            // ERROR_CANCELLED: ユーザーが UAC を拒否
            return IpApplyResult.Failed("管理者権限の承認がキャンセルされました。");
        }
        catch (Exception ex)
        {
            return IpApplyResult.Failed($"昇格付きPowerShellの実行に失敗しました: {ex.Message}");
        }
        finally
        {
            TryDelete(wrapperPath);
            TryDelete(resultPath);
        }
    }

    private static string BuildElevatedWrapper(string scriptPath, List<string> scriptArgs, string resultPath)
    {
        static string Q(string s) => "'" + s.Replace("'", "''") + "'";

        var argLiteral = string.Join(", ", scriptArgs.Select(Q));
        return $$"""
            $ErrorActionPreference = 'Continue'
            $resultPath = {{Q(resultPath)}}
            $scriptPath = {{Q(scriptPath)}}
            $scriptArgs = @({{argLiteral}})
            try {
                $output = & $scriptPath @scriptArgs 2>&1 | ForEach-Object { $_.ToString() }
                $text = ($output -join [Environment]::NewLine)
                Set-Content -LiteralPath $resultPath -Value $text -Encoding UTF8
                if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                    exit $LASTEXITCODE
                }
                if ($text -notmatch 'RESULT_OK') {
                    exit 1
                }
                exit 0
            }
            catch {
                Set-Content -LiteralPath $resultPath -Value $_.Exception.Message -Encoding UTF8
                exit 1
            }
            """;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            /* 一時ファイル削除失敗は無視 */
        }
    }
}
