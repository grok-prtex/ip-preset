using IpPreset.Core;
using IpPreset.Core.Models;
using IpPreset.Core.Net;

namespace IpPreset;

/// <summary>
/// メイン画面。アダプター選択・現在の状態表示・プリセット管理・適用を行います。
/// </summary>
public sealed class MainForm : Form
{
    private readonly NetworkInfoService _networkInfoService = new();
    private readonly PresetStore _presetStore;
    private readonly IpApplyExecutor _applyExecutor;

    private readonly List<AdapterInfo> _adapters = new();
    private List<NetworkPreset> _presets = new();

    private readonly ComboBox _adapterCombo = new();
    private readonly Button _refreshAdapterButton = new();
    private readonly TextBox _currentConfigText = new();
    private readonly Button _refreshConfigButton = new();
    private readonly ListBox _presetListBox = new();
    private readonly Button _addButton = new();
    private readonly Button _editButton = new();
    private readonly Button _deleteButton = new();
    private readonly Button _applyButton = new();
    private readonly TextBox _logText = new();

    public MainForm()
    {
        Text = "IPプリセット";
        Width = 780;
        Height = 720;
        MinimumSize = new Size(700, 620);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Yu Gothic UI", 9.5f, FontStyle.Regular);

        var baseDirectory = AppContext.BaseDirectory;
        _presetStore = PresetStore.CreateDefault(baseDirectory);
        _applyExecutor = new IpApplyExecutor(Path.Combine(Path.GetTempPath(), "IpPreset"));

        BuildLayout();

        Load += MainForm_Load;
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 170));
        Controls.Add(root);

        root.Controls.Add(BuildAdapterRow(), 0, 0);
        root.Controls.Add(BuildCurrentStatusGroup(), 0, 1);
        root.Controls.Add(BuildPresetsGroup(), 0, 2);
        root.Controls.Add(BuildLogGroup(), 0, 3);
    }

    private Control BuildAdapterRow()
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 3,
            Margin = new Padding(0, 0, 0, 10)
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var label = new Label
        {
            Text = "ネットワークアダプター:",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 8, 8, 0)
        };

        _adapterCombo.DropDownStyle = ComboBoxStyle.DropDownList;
        _adapterCombo.Dock = DockStyle.Fill;
        _adapterCombo.Margin = new Padding(0, 3, 8, 0);
        _adapterCombo.SelectedIndexChanged += (_, _) => RefreshCurrentConfig();

        _refreshAdapterButton.Text = "更新";
        _refreshAdapterButton.AutoSize = true;
        _refreshAdapterButton.Margin = new Padding(0, 3, 0, 0);
        _refreshAdapterButton.Click += (_, _) => LoadAdapters(preserveSelection: true);

        panel.Controls.Add(label, 0, 0);
        panel.Controls.Add(_adapterCombo, 1, 0);
        panel.Controls.Add(_refreshAdapterButton, 2, 0);
        return panel;
    }

    private Control BuildCurrentStatusGroup()
    {
        var group = new GroupBox
        {
            Text = "現在の状態",
            Dock = DockStyle.Top,
            Height = 150,
            Margin = new Padding(0, 0, 0, 10)
        };

        _currentConfigText.Multiline = true;
        _currentConfigText.ReadOnly = true;
        _currentConfigText.BorderStyle = BorderStyle.None;
        _currentConfigText.BackColor = SystemColors.Control;
        _currentConfigText.Dock = DockStyle.Fill;
        _currentConfigText.Font = new Font("Consolas", 9.5f);
        _currentConfigText.Margin = new Padding(8);
        _currentConfigText.Text = "（アダプターを選択してください）";

        _refreshConfigButton.Text = "再取得";
        _refreshConfigButton.AutoSize = true;
        _refreshConfigButton.Dock = DockStyle.Bottom;
        _refreshConfigButton.Anchor = AnchorStyles.Right;
        _refreshConfigButton.Click += (_, _) => RefreshCurrentConfig();

        var inner = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Padding = new Padding(8) };
        inner.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        inner.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var buttonRow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, AutoSize = true };
        buttonRow.Controls.Add(_refreshConfigButton);

        inner.Controls.Add(_currentConfigText, 0, 0);
        inner.Controls.Add(buttonRow, 0, 1);

        group.Controls.Add(inner);
        return group;
    }

    private Control BuildPresetsGroup()
    {
        var group = new GroupBox
        {
            Text = "プリセット",
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 10)
        };

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            Padding = new Padding(8)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));

        _presetListBox.Dock = DockStyle.Fill;
        _presetListBox.Font = new Font("Yu Gothic UI", 10f);
        _presetListBox.ItemHeight = 22;
        _presetListBox.DoubleClick += (_, _) => EditSelectedPreset();

        var buttonPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Margin = new Padding(10, 0, 0, 0)
        };
        for (var i = 0; i < 5; i++)
        {
            buttonPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }
        buttonPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        _addButton.Text = "追加(&A)";
        _editButton.Text = "編集(&E)";
        _deleteButton.Text = "削除(&D)";
        foreach (var btn in new[] { _addButton, _editButton, _deleteButton })
        {
            btn.Dock = DockStyle.Top;
            btn.Height = 34;
            btn.Margin = new Padding(0, 0, 0, 8);
        }

        _addButton.Click += (_, _) => AddPreset();
        _editButton.Click += (_, _) => EditSelectedPreset();
        _deleteButton.Click += (_, _) => DeleteSelectedPreset();

        _applyButton.Text = "適用";
        _applyButton.Dock = DockStyle.Bottom;
        _applyButton.Height = 56;
        _applyButton.BackColor = AppTheme.Accent;
        _applyButton.ForeColor = AppTheme.AccentText;
        _applyButton.FlatStyle = FlatStyle.Flat;
        _applyButton.FlatAppearance.BorderSize = 0;
        _applyButton.Font = new Font("Yu Gothic UI", 12f, FontStyle.Bold);
        _applyButton.Click += (_, _) => ApplySelectedPreset();

        buttonPanel.Controls.Add(_addButton, 0, 0);
        buttonPanel.Controls.Add(_editButton, 0, 1);
        buttonPanel.Controls.Add(_deleteButton, 0, 2);
        buttonPanel.Controls.Add(_applyButton, 0, 5);

        layout.Controls.Add(_presetListBox, 0, 0);
        layout.Controls.Add(buttonPanel, 1, 0);

        group.Controls.Add(layout);
        return group;
    }

    private Control BuildLogGroup()
    {
        var group = new GroupBox
        {
            Text = "ログ",
            Dock = DockStyle.Fill
        };

        _logText.Multiline = true;
        _logText.ReadOnly = true;
        _logText.ScrollBars = ScrollBars.Vertical;
        _logText.Dock = DockStyle.Fill;
        _logText.Font = new Font("Consolas", 9f);
        _logText.BackColor = Color.White;

        group.Controls.Add(_logText);
        return group;
    }

    private void MainForm_Load(object? sender, EventArgs e)
    {
        AppendLog("起動しました。管理者権限で実行されています。");
        LoadPresets();
        LoadAdapters(preserveSelection: false);
    }

    private void LoadAdapters(bool preserveSelection)
    {
        var previousName = preserveSelection && _adapterCombo.SelectedItem is AdapterInfo prev ? prev.Name : null;

        _adapters.Clear();
        _adapters.AddRange(_networkInfoService.GetAdapters());

        _adapterCombo.BeginUpdate();
        _adapterCombo.Items.Clear();
        foreach (var adapter in _adapters)
        {
            _adapterCombo.Items.Add(adapter);
        }
        _adapterCombo.EndUpdate();

        if (_adapters.Count == 0)
        {
            AppendLog("ネットワークアダプターが見つかりませんでした。", isError: true);
            return;
        }

        var indexToSelect = 0;
        if (previousName is not null)
        {
            var idx = _adapters.FindIndex(a => a.Name == previousName);
            if (idx >= 0)
            {
                indexToSelect = idx;
            }
        }

        _adapterCombo.SelectedIndex = indexToSelect;
    }

    private void LoadPresets()
    {
        try
        {
            _presetStore.EnsureSeeded(DefaultPresets.CreateSamples());
            _presets = _presetStore.Load();
        }
        catch (Exception ex)
        {
            _presets = new List<NetworkPreset>();
            AppendLog($"presets.json の読み込みに失敗しました: {ex.Message}", isError: true);
        }

        RefreshPresetList();
    }

    private void RefreshPresetList()
    {
        var selectedName = _presetListBox.SelectedItem is NetworkPreset p ? p.Name : null;

        _presetListBox.BeginUpdate();
        _presetListBox.Items.Clear();
        foreach (var preset in _presets)
        {
            _presetListBox.Items.Add(preset);
        }
        _presetListBox.EndUpdate();

        if (selectedName is not null)
        {
            var idx = _presets.FindIndex(p => p.Name == selectedName);
            if (idx >= 0)
            {
                _presetListBox.SelectedIndex = idx;
            }
        }
    }

    private void SavePresets()
    {
        try
        {
            _presetStore.Save(_presets);
        }
        catch (Exception ex)
        {
            AppendLog($"presets.json の保存に失敗しました: {ex.Message}", isError: true);
        }
    }

    private AdapterInfo? SelectedAdapter => _adapterCombo.SelectedItem as AdapterInfo;

    private void RefreshCurrentConfig()
    {
        var adapter = SelectedAdapter;
        if (adapter is null)
        {
            _currentConfigText.Text = "（アダプターを選択してください）";
            return;
        }

        try
        {
            var config = _networkInfoService.GetCurrentConfig(adapter.InterfaceIndex);
            _currentConfigText.Text = config is null
                ? "現在の状態を取得できませんでした。"
                : $"アダプター: {adapter.Name}\r\nMAC: {adapter.MacAddress}\r\n{config.ToDisplayText()}";
        }
        catch (Exception ex)
        {
            _currentConfigText.Text = "現在の状態の取得中にエラーが発生しました。";
            AppendLog($"状態取得エラー: {ex.Message}", isError: true);
        }
    }

    private void AddPreset()
    {
        using var dialog = new PresetEditForm(new NetworkPreset { Name = "新しいプリセット" });
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        _presets.Add(dialog.Result);
        SavePresets();
        RefreshPresetList();
        AppendLog($"プリセット「{dialog.Result.Name}」を追加しました。");
    }

    private void EditSelectedPreset()
    {
        if (_presetListBox.SelectedItem is not NetworkPreset selected)
        {
            MessageBox.Show(this, "編集するプリセットを選択してください。", "IPプリセット", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var index = _presets.IndexOf(selected);
        using var dialog = new PresetEditForm(selected.Clone());
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        _presets[index] = dialog.Result;
        SavePresets();
        RefreshPresetList();
        AppendLog($"プリセット「{dialog.Result.Name}」を更新しました。");
    }

    private void DeleteSelectedPreset()
    {
        if (_presetListBox.SelectedItem is not NetworkPreset selected)
        {
            MessageBox.Show(this, "削除するプリセットを選択してください。", "IPプリセット", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var confirm = MessageBox.Show(
            this,
            $"プリセット「{selected.Name}」を削除しますか？\nこの操作は元に戻せません。",
            "削除の確認",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
        {
            return;
        }

        _presets.Remove(selected);
        SavePresets();
        RefreshPresetList();
        AppendLog($"プリセット「{selected.Name}」を削除しました。");
    }

    private void ApplySelectedPreset()
    {
        var adapter = SelectedAdapter;
        if (adapter is null)
        {
            MessageBox.Show(this, "ネットワークアダプターを選択してください。", "IPプリセット", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (_presetListBox.SelectedItem is not NetworkPreset preset)
        {
            MessageBox.Show(this, "適用するプリセットを選択してください。", "IPプリセット", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var errors = PresetValidator.Validate(preset);
        if (errors.Count > 0)
        {
            MessageBox.Show(this, string.Join(Environment.NewLine, errors), "入力エラー", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var modeText = preset.Mode == PresetMode.Static
            ? $"静的IP: {preset.Ipv4} / ゲートウェイ: {(string.IsNullOrEmpty(preset.Gateway) ? "なし" : preset.Gateway)}"
            : "DHCP（自動取得）";

        var confirm = MessageBox.Show(
            this,
            $"アダプター「{adapter.Name}」にプリセット「{preset.Name}」を適用します。\n" +
            $"設定内容: {modeText}\n\n" +
            "適用中は一時的にネットワーク接続が切断される場合があります。よろしいですか？",
            "適用の確認",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
        {
            AppendLog("適用をキャンセルしました。");
            return;
        }

        SetBusy(true);
        AppendLog($"「{preset.Name}」を適用しています…");

        var interfaceIndex = adapter.InterfaceIndex;
        Task.Run(() => _applyExecutor.Apply(interfaceIndex, preset))
            .ContinueWith(t =>
            {
                if (IsDisposed)
                {
                    return;
                }

                BeginInvoke(() =>
                {
                    SetBusy(false);

                    if (t.IsFaulted)
                    {
                        AppendLog($"適用中に予期しないエラーが発生しました: {t.Exception?.GetBaseException().Message}", isError: true);
                        return;
                    }

                    var result = t.Result;
                    if (result.Success)
                    {
                        AppendLog($"「{preset.Name}」を適用しました。");
                    }
                    else
                    {
                        var detail = string.IsNullOrWhiteSpace(result.Error) ? result.Output : result.Error;
                        AppendLog($"適用に失敗しました（終了コード {result.ExitCode}）: {detail}", isError: true);
                    }

                    LoadAdapters(preserveSelection: true);
                });
            });
    }

    private void SetBusy(bool busy)
    {
        Cursor = busy ? Cursors.WaitCursor : Cursors.Default;
        _applyButton.Enabled = !busy;
        _addButton.Enabled = !busy;
        _editButton.Enabled = !busy;
        _deleteButton.Enabled = !busy;
        _adapterCombo.Enabled = !busy;
        _refreshAdapterButton.Enabled = !busy;
    }

    private void AppendLog(string message, bool isError = false)
    {
        var timestamp = DateTime.Now.ToString("HH:mm:ss");
        var prefix = isError ? "[エラー]" : "[情報]";
        _logText.AppendText($"{timestamp} {prefix} {message}{Environment.NewLine}");
    }
}
