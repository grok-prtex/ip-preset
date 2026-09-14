using IpPreset.Core;
using IpPreset.Core.Models;
using IpPreset.Core.Net;

namespace IpPreset;

/// <summary>
/// プリセットの追加・編集用ダイアログ。
/// </summary>
public sealed class PresetEditForm : Form
{
    private readonly TextBox _nameBox = new();
    private readonly RadioButton _dhcpRadio = new() { Text = "DHCP（自動取得）" };
    private readonly RadioButton _staticRadio = new() { Text = "静的（手動設定）" };
    private readonly TextBox _ipv4Box = new();
    private readonly TextBox _subnetBox = new();
    private readonly TextBox _gatewayBox = new();
    private readonly TextBox _dnsBox = new();
    private readonly TextBox _noteBox = new();
    private readonly Label _errorLabel = new();

    public NetworkPreset Result { get; private set; }

    public PresetEditForm(NetworkPreset initial)
    {
        Result = initial;

        Text = "プリセットの編集";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        Width = 460;
        Height = 520;
        Font = new Font("Yu Gothic UI", 9.5f);

        BuildLayout();
        LoadFrom(initial);
    }

    private void BuildLayout()
    {
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            AutoSize = true,
            Padding = new Padding(16)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        void AddRow(string labelText, Control control, string? hint = null)
        {
            var label = new Label { Text = labelText, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 8, 10, 0) };
            control.Dock = DockStyle.Fill;
            control.Margin = new Padding(0, 4, 0, 4);
            layout.Controls.Add(label);
            layout.Controls.Add(control);

            if (hint is not null)
            {
                var hintLabel = new Label
                {
                    Text = hint,
                    AutoSize = true,
                    ForeColor = SystemColors.GrayText,
                    Font = new Font(Font.FontFamily, 8f),
                    Margin = new Padding(0, 0, 0, 6)
                };
                layout.Controls.Add(new Label());
                layout.Controls.Add(hintLabel);
            }
        }

        AddRow("プリセット名:", _nameBox);

        var modePanel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        _dhcpRadio.AutoSize = true;
        _staticRadio.AutoSize = true;
        _dhcpRadio.Margin = new Padding(0, 4, 20, 4);
        _staticRadio.Margin = new Padding(0, 4, 0, 4);
        _dhcpRadio.CheckedChanged += (_, _) => UpdateStaticFieldsEnabled();
        modePanel.Controls.Add(_dhcpRadio);
        modePanel.Controls.Add(_staticRadio);
        layout.Controls.Add(new Label { Text = "モード:", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 8, 10, 0) });
        layout.Controls.Add(modePanel);

        AddRow("IPv4アドレス:", _ipv4Box, "例: 192.168.1.50");
        AddRow("サブネット:", _subnetBox, "プレフィックス長（例: 24）またはマスク（例: 255.255.255.0）");
        AddRow("ゲートウェイ:", _gatewayBox, "任意。例: 192.168.1.1");
        AddRow("DNSサーバー:", _dnsBox, "任意。カンマ区切りで複数指定可（例: 8.8.8.8, 1.1.1.1）");
        AddRow("メモ:", _noteBox, "任意");

        _errorLabel.AutoSize = true;
        _errorLabel.ForeColor = AppTheme.ErrorText;
        _errorLabel.MaximumSize = new Size(400, 0);
        _errorLabel.Margin = new Padding(0, 8, 0, 0);
        layout.Controls.Add(new Label());
        layout.Controls.Add(_errorLabel);

        var buttonPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Padding = new Padding(16)
        };
        var okButton = new Button { Text = "OK", Width = 90, Height = 32, DialogResult = DialogResult.None };
        okButton.Click += OkButton_Click;
        var cancelButton = new Button { Text = "キャンセル", Width = 90, Height = 32, DialogResult = DialogResult.Cancel };
        buttonPanel.Controls.Add(cancelButton);
        buttonPanel.Controls.Add(okButton);

        AcceptButton = okButton;
        CancelButton = cancelButton;

        Controls.Add(layout);
        Controls.Add(buttonPanel);
    }

    private void LoadFrom(NetworkPreset preset)
    {
        _nameBox.Text = preset.Name;
        _dhcpRadio.Checked = preset.Mode == PresetMode.Dhcp;
        _staticRadio.Checked = preset.Mode == PresetMode.Static;
        _ipv4Box.Text = preset.Ipv4 ?? string.Empty;
        _subnetBox.Text = preset.PrefixLength?.ToString() ?? preset.SubnetMask ?? string.Empty;
        _gatewayBox.Text = preset.Gateway ?? string.Empty;
        _dnsBox.Text = string.Join(", ", preset.Dns);
        _noteBox.Text = preset.Note ?? string.Empty;

        if (!_dhcpRadio.Checked && !_staticRadio.Checked)
        {
            _dhcpRadio.Checked = true;
        }

        UpdateStaticFieldsEnabled();
    }

    private void UpdateStaticFieldsEnabled()
    {
        var isStatic = _staticRadio.Checked;
        _ipv4Box.Enabled = isStatic;
        _subnetBox.Enabled = isStatic;
        _gatewayBox.Enabled = isStatic;
        _dnsBox.Enabled = isStatic;
    }

    private void OkButton_Click(object? sender, EventArgs e)
    {
        var preset = new NetworkPreset
        {
            Name = _nameBox.Text.Trim(),
            Mode = _staticRadio.Checked ? PresetMode.Static : PresetMode.Dhcp,
            Note = string.IsNullOrWhiteSpace(_noteBox.Text) ? null : _noteBox.Text.Trim()
        };

        if (preset.Mode == PresetMode.Static)
        {
            preset.Ipv4 = _ipv4Box.Text.Trim();
            preset.Gateway = string.IsNullOrWhiteSpace(_gatewayBox.Text) ? null : _gatewayBox.Text.Trim();
            preset.Dns = _dnsBox.Text
                .Split(new[] { ',', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .ToList();

            var subnetInput = _subnetBox.Text.Trim();
            if (int.TryParse(subnetInput, out var prefixLength) && subnetInput.Length <= 2)
            {
                preset.PrefixLength = prefixLength;
                preset.SubnetMask = null;
            }
            else if (IpUtils.TryMaskToPrefixLength(subnetInput, out _))
            {
                preset.SubnetMask = subnetInput;
                preset.PrefixLength = null;
            }
            else if (subnetInput.Length > 0)
            {
                // 解析できない値でもそのままバリデーションに委ね、エラーメッセージを表示させる。
                preset.SubnetMask = subnetInput;
            }
        }

        var errors = PresetValidator.Validate(preset);
        if (errors.Count > 0)
        {
            _errorLabel.Text = string.Join(Environment.NewLine, errors);
            return;
        }

        Result = preset;
        DialogResult = DialogResult.OK;
        Close();
    }
}
