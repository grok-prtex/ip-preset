namespace IpPreset;

/// <summary>
/// 最小限の配色定義。アクセントカラーとしてジェイド (#0E9E6B) のみを使用します。
/// </summary>
internal static class AppTheme
{
    public static readonly Color Accent = ColorTranslator.FromHtml("#0E9E6B");
    public static readonly Color AccentDark = ColorTranslator.FromHtml("#0B7F55");
    public static readonly Color AccentText = Color.White;
    public static readonly Color ErrorText = ColorTranslator.FromHtml("#B3261E");
}
