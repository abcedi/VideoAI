# VideoAI GUI v0.5.0
# Local Windows GUI frontend for the VideoAI v0.4.2 backend.
# No persistent PATH/profile changes. Does not download URLs.

[CmdletBinding()]
param(
    [string]$BackendPath = "$HOME\Tools\VideoAI\Convert-VideoForAI.ps1"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Clipboard and WinForms dialogs are most reliable from an STA thread.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
    if (-not $PSCommandPath) {
        throw "VideoAI GUI must be launched from its .ps1 file."
    }

    $Pwsh = (Get-Process -Id $PID).Path
    $Psi = [System.Diagnostics.ProcessStartInfo]::new()
    $Psi.FileName = $Pwsh
    $Psi.UseShellExecute = $false
    [void]$Psi.ArgumentList.Add("-NoLogo")
    [void]$Psi.ArgumentList.Add("-NoProfile")
    [void]$Psi.ArgumentList.Add("-STA")
    [void]$Psi.ArgumentList.Add("-File")
    [void]$Psi.ArgumentList.Add($PSCommandPath)
    [void]$Psi.ArgumentList.Add("-BackendPath")
    [void]$Psi.ArgumentList.Add($BackendPath)

    [void][System.Diagnostics.Process]::Start($Psi)
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$ToolScript = $BackendPath
$YouTubeHelperScript = Join-Path (Split-Path -Parent $ToolScript) "Download-YouTubeForVideoAI.ps1"
$TikTokHelperScript = Join-Path (Split-Path -Parent $ToolScript) "Download-TikTokForVideoAI.ps1"
$DefaultOutput = "$HOME\Videos\AI-Video-Analysis\Jobs"

$script:ActiveJob = $null
$script:RunStarted = $null
$script:LatestZip = $null
$script:Cancelled = $false

function Show-UiError {
    param([string]$Message)

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "VideoAI",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Show-UiInfo {
    param([string]$Message)

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "VideoAI",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

if (-not (Test-Path -LiteralPath $ToolScript -PathType Leaf)) {
    Show-UiError "Production backend not found:`n$ToolScript"
    return
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Show-UiError "uv is not available in PATH. The VideoAI backend requires uv."
    return
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = "VideoAI Converter v0.5.0"
$form.StartPosition = "CenterScreen"
$form.Size = [System.Drawing.Size]::new(940, 760)
$form.MinimumSize = [System.Drawing.Size]::new(820, 680)
$form.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$main = [System.Windows.Forms.TableLayoutPanel]::new()
$main.Dock = "Fill"
$main.Padding = [System.Windows.Forms.Padding]::new(18)
$main.ColumnCount = 1
$main.RowCount = 9
[void]$main.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$main.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$form.Controls.Add($main)

$header = [System.Windows.Forms.Panel]::new()
$header.Dock = "Top"
$header.Height = 58

$title = [System.Windows.Forms.Label]::new()
$title.Text = "Convert local videos, YouTube URLs, or TikTok URLs into AI evidence"
$title.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 15)
$title.AutoSize = $true
$title.Location = [System.Drawing.Point]::new(0, 0)

$subtitle = [System.Windows.Forms.Label]::new()
$subtitle.Text = "Local/YouTube/TikTok video + RTX/Turbo fallback + video-ai-evidence/v4 ZIP"
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = [System.Drawing.Point]::new(2, 31)

[void]$header.Controls.AddRange(@($title, $subtitle))
[void]$main.Controls.Add($header, 0, 0)

function New-InputRow {
    param(
        [string]$LabelText,
        [bool]$WithBrowse = $false,
        [bool]$WithPaste = $false,
        [bool]$IsFolder = $false
    )

    $row = [System.Windows.Forms.TableLayoutPanel]::new()
    $row.Dock = "Top"
    $row.AutoSize = $true
    $row.Margin = [System.Windows.Forms.Padding]::new(0, 4, 0, 4)
    $row.ColumnCount = 4
    [void]$row.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 110))
    [void]$row.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$row.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$row.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))

    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $LabelText
    $label.AutoSize = $true
    $label.Anchor = "Left"
    $label.Margin = [System.Windows.Forms.Padding]::new(0, 9, 8, 0)

    $box = [System.Windows.Forms.TextBox]::new()
    $box.Dock = "Fill"
    $box.Margin = [System.Windows.Forms.Padding]::new(0, 4, 8, 4)

    $browse = [System.Windows.Forms.Button]::new()
    $browse.Text = "Browse"
    $browse.AutoSize = $true
    $browse.Visible = $WithBrowse
    $browse.Margin = [System.Windows.Forms.Padding]::new(0, 2, 6, 2)

    $paste = [System.Windows.Forms.Button]::new()
    $paste.Text = "Paste"
    $paste.AutoSize = $true
    $paste.Visible = $WithPaste
    $paste.Margin = [System.Windows.Forms.Padding]::new(0, 2, 0, 2)

    [void]$row.Controls.Add($label, 0, 0)
    [void]$row.Controls.Add($box, 1, 0)
    [void]$row.Controls.Add($browse, 2, 0)
    [void]$row.Controls.Add($paste, 3, 0)

    return [PSCustomObject]@{
        Panel = $row
        Box = $box
        Browse = $browse
        Paste = $paste
        IsFolder = $IsFolder
    }
}

$videoRow = New-InputRow -LabelText "Video file" -WithBrowse $true -WithPaste $true
$videoRow.Box.AllowDrop = $true
$videoRow.Box.PlaceholderText = "Optional local video: paste, browse, or drag an .mp4/.mov/.mkv/.webm file here"
[void]$main.Controls.Add($videoRow.Panel, 0, 1)

$urlRow = New-InputRow -LabelText "Source URL" -WithPaste $true
$urlRow.Box.PlaceholderText = "YouTube or TikTok URL for automatic download, or optional provenance URL for a local file"
[void]$main.Controls.Add($urlRow.Panel, 0, 2)

$contextRow = New-InputRow -LabelText "Context label" -WithPaste $true
$contextRow.Box.PlaceholderText = "Optional: e.g. Pi-hole DNS privacy tips"
[void]$main.Controls.Add($contextRow.Panel, 0, 3)

$options = [System.Windows.Forms.TableLayoutPanel]::new()
$options.Dock = "Top"
$options.AutoSize = $true
$options.Margin = [System.Windows.Forms.Padding]::new(0, 4, 0, 4)
$options.ColumnCount = 4
[void]$options.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 110))
[void]$options.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 190))
[void]$options.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 110))
[void]$options.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))

$langLabel = [System.Windows.Forms.Label]::new()
$langLabel.Text = "Language"
$langLabel.AutoSize = $true
$langLabel.Anchor = "Left"
$langLabel.Margin = [System.Windows.Forms.Padding]::new(0, 9, 8, 0)

$langBox = [System.Windows.Forms.ComboBox]::new()
$langBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$langBox.Dock = "Fill"
[void]$langBox.Items.AddRange(@("English (en)", "Auto detect"))
$langBox.SelectedIndex = 0
$langBox.Margin = [System.Windows.Forms.Padding]::new(0, 4, 20, 4)

$formatLabel = [System.Windows.Forms.Label]::new()
$formatLabel.Text = "Evidence"
$formatLabel.AutoSize = $true
$formatLabel.Anchor = "Left"
$formatLabel.Margin = [System.Windows.Forms.Padding]::new(0, 9, 8, 0)

$formatValue = [System.Windows.Forms.Label]::new()
$formatValue.Text = "video-ai-evidence/v4"
$formatValue.AutoSize = $true
$formatValue.Anchor = "Left"
$formatValue.ForeColor = [System.Drawing.Color]::DimGray
$formatValue.Margin = [System.Windows.Forms.Padding]::new(0, 9, 0, 0)

[void]$options.Controls.Add($langLabel, 0, 0)
[void]$options.Controls.Add($langBox, 1, 0)
[void]$options.Controls.Add($formatLabel, 2, 0)
[void]$options.Controls.Add($formatValue, 3, 0)
[void]$main.Controls.Add($options, 0, 4)

$outputRow = New-InputRow -LabelText "Output folder" -WithBrowse $true -IsFolder $true
$outputRow.Box.Text = $DefaultOutput
[void]$main.Controls.Add($outputRow.Panel, 0, 5)

$controls = [System.Windows.Forms.TableLayoutPanel]::new()
$controls.Dock = "Top"
$controls.AutoSize = $true
$controls.Margin = [System.Windows.Forms.Padding]::new(0, 8, 0, 8)
$controls.ColumnCount = 6
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$controls.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))

$convertButton = [System.Windows.Forms.Button]::new()
$convertButton.Text = "Convert to AI ZIP"
$convertButton.AutoSize = $true
$convertButton.Padding = [System.Windows.Forms.Padding]::new(12, 5, 12, 5)

$cancelButton = [System.Windows.Forms.Button]::new()
$cancelButton.Text = "Cancel"
$cancelButton.AutoSize = $true
$cancelButton.Enabled = $false
$cancelButton.Padding = [System.Windows.Forms.Padding]::new(8, 5, 8, 5)

$clearButton = [System.Windows.Forms.Button]::new()
$clearButton.Text = "Clear"
$clearButton.AutoSize = $true
$clearButton.Padding = [System.Windows.Forms.Padding]::new(8, 5, 8, 5)

$statusLabel = [System.Windows.Forms.Label]::new()
$statusLabel.Text = "Ready"
$statusLabel.AutoSize = $true
$statusLabel.Anchor = "Right"
$statusLabel.Margin = [System.Windows.Forms.Padding]::new(10, 10, 10, 0)

$progress = [System.Windows.Forms.ProgressBar]::new()
$progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$progress.Width = 160
$progress.Anchor = "Right"

[void]$controls.Controls.Add($convertButton, 0, 0)
[void]$controls.Controls.Add($cancelButton, 1, 0)
[void]$controls.Controls.Add($clearButton, 2, 0)
[void]$controls.Controls.Add([System.Windows.Forms.Label]::new(), 3, 0)
[void]$controls.Controls.Add($statusLabel, 4, 0)
[void]$controls.Controls.Add($progress, 5, 0)
[void]$main.Controls.Add($controls, 0, 6)

$logBox = [System.Windows.Forms.RichTextBox]::new()
$logBox.Dock = "Fill"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
$logBox.ForeColor = [System.Drawing.Color]::Gainsboro
$logBox.Font = [System.Drawing.Font]::new("Cascadia Mono", 9)
$logBox.WordWrap = $false
$logBox.DetectUrls = $false
[void]$main.Controls.Add($logBox, 0, 7)

$resultPanel = [System.Windows.Forms.TableLayoutPanel]::new()
$resultPanel.Dock = "Bottom"
$resultPanel.AutoSize = $true
$resultPanel.Margin = [System.Windows.Forms.Padding]::new(0, 8, 0, 0)
$resultPanel.ColumnCount = 4
[void]$resultPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 110))
[void]$resultPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$resultPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$resultPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))

$resultLabel = [System.Windows.Forms.Label]::new()
$resultLabel.Text = "Latest AI ZIP"
$resultLabel.AutoSize = $true
$resultLabel.Anchor = "Left"
$resultLabel.Margin = [System.Windows.Forms.Padding]::new(0, 9, 8, 0)

$resultBox = [System.Windows.Forms.TextBox]::new()
$resultBox.ReadOnly = $true
$resultBox.Dock = "Fill"
$resultBox.Margin = [System.Windows.Forms.Padding]::new(0, 4, 8, 4)

$copyResult = [System.Windows.Forms.Button]::new()
$copyResult.Text = "Copy path"
$copyResult.AutoSize = $true
$copyResult.Enabled = $false

$openResult = [System.Windows.Forms.Button]::new()
$openResult.Text = "Open folder"
$openResult.AutoSize = $true
$openResult.Enabled = $false

[void]$resultPanel.Controls.Add($resultLabel, 0, 0)
[void]$resultPanel.Controls.Add($resultBox, 1, 0)
[void]$resultPanel.Controls.Add($copyResult, 2, 0)
[void]$resultPanel.Controls.Add($openResult, 3, 0)
[void]$main.Controls.Add($resultPanel, 0, 8)

function Append-Log {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $logBox.AppendText($Text.TrimEnd() + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()

    switch -Regex ($Text) {
        "===== CUDA DOCTOR =====" { $statusLabel.Text = "Checking CUDA"; break }
        "===== SPLIT ====="       { $statusLabel.Text = "Inspecting media"; break }
        "===== TRANSCRIBE ====="  { $statusLabel.Text = "Transcribing on RTX"; break }
        "===== FRAMES ====="      { $statusLabel.Text = "Extracting visuals"; break }
        "===== BUILD V4 PACK =====" { $statusLabel.Text = "Building AI evidence"; break }
        "===== COMPLETE ====="    { $statusLabel.Text = "Finalizing"; break }
    }
}

function Set-UiRunning {
    param([bool]$Running)

    $videoRow.Box.Enabled = -not $Running
    $videoRow.Browse.Enabled = -not $Running
    $videoRow.Paste.Enabled = -not $Running
    $urlRow.Box.Enabled = -not $Running
    $urlRow.Paste.Enabled = -not $Running
    $contextRow.Box.Enabled = -not $Running
    $contextRow.Paste.Enabled = -not $Running
    $langBox.Enabled = -not $Running
    $outputRow.Box.Enabled = -not $Running
    $outputRow.Browse.Enabled = -not $Running
    $convertButton.Enabled = -not $Running
    $clearButton.Enabled = -not $Running
    $cancelButton.Enabled = $Running
    $progress.Visible = $Running
}

function Find-NewestZip {
    param(
        [string]$Root,
        [datetime]$Since
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $null
    }

    return Get-ChildItem `
        -LiteralPath $Root `
        -File `
        -Recurse `
        -Filter "*-ai.zip" `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

$videoRow.Browse.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = "Choose informational video"
    $dialog.Filter = "Video files|*.mp4;*.mov;*.mkv;*.webm|All files|*.*"
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $videoRow.Box.Text = $dialog.FileName
    }

    $dialog.Dispose()
})

$outputRow.Browse.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Choose VideoAI job output folder"
    $dialog.UseDescriptionForTitle = $true

    if (Test-Path -LiteralPath $outputRow.Box.Text -PathType Container) {
        $dialog.SelectedPath = $outputRow.Box.Text
    }

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputRow.Box.Text = $dialog.SelectedPath
    }

    $dialog.Dispose()
})

$videoRow.Paste.Add_Click({
    try {
        $value = (Get-Clipboard -Raw -ErrorAction Stop).Trim()
        if ($value) {
            $videoRow.Box.Text = $value.Trim('"')
        }
    }
    catch {
        Show-UiError "Could not read the clipboard.`n$($_.Exception.Message)"
    }
})

$urlRow.Paste.Add_Click({
    try {
        $value = (Get-Clipboard -Raw -ErrorAction Stop).Trim()
        if ($value) {
            $urlRow.Box.Text = $value
        }
    }
    catch {
        Show-UiError "Could not read the clipboard.`n$($_.Exception.Message)"
    }
})

$contextRow.Paste.Add_Click({
    try {
        $value = (Get-Clipboard -Raw -ErrorAction Stop).Trim()
        if ($value) {
            $contextRow.Box.Text = $value
        }
    }
    catch {
        Show-UiError "Could not read the clipboard.`n$($_.Exception.Message)"
    }
})

$videoRow.Box.Add_DragEnter({
    param($sender, $e)

    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
    else {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
})

$videoRow.Box.Add_DragDrop({
    param($sender, $e)

    $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)

    if ($files -and $files.Count -gt 0) {
        $videoRow.Box.Text = [string]$files[0]
    }
})

$copyResult.Add_Click({
    if ($script:LatestZip -and (Test-Path -LiteralPath $script:LatestZip -PathType Leaf)) {
        try {
            Set-Clipboard -Value $script:LatestZip
            $statusLabel.Text = "ZIP path copied"
        }
        catch {
            Show-UiError "Could not copy the ZIP path.`n$($_.Exception.Message)"
        }
    }
})

$openResult.Add_Click({
    if ($script:LatestZip -and (Test-Path -LiteralPath $script:LatestZip -PathType Leaf)) {
        Start-Process -FilePath "explorer.exe" -ArgumentList @(
            "/select,`"$script:LatestZip`""
        )
    }
})

$clearButton.Add_Click({
    if ($script:ActiveJob) {
        return
    }

    $videoRow.Box.Clear()
    $urlRow.Box.Clear()
    $contextRow.Box.Clear()
    $resultBox.Clear()
    $logBox.Clear()
    $script:LatestZip = $null
    $copyResult.Enabled = $false
    $openResult.Enabled = $false
    $statusLabel.Text = "Ready"
})

$convertButton.Add_Click({
    try {
        $video = $videoRow.Box.Text.Trim().Trim('"')
        $url = $urlRow.Box.Text.Trim()
        $contextLabel = $contextRow.Box.Text.Trim()
        $output = $outputRow.Box.Text.Trim().Trim('"')

        if (-not $output) {
            throw "Output folder cannot be empty."
        }

        $allowedYouTubeHosts = @(
            "youtube.com",
            "www.youtube.com",
            "m.youtube.com",
            "youtu.be",
            "music.youtube.com"
        )

        $parsedUri = $null
        $isYouTubeUrl = $false
        $isTikTokUrl = $false

        if ($url) {
            if (
                -not [Uri]::TryCreate(
                    $url,
                    [UriKind]::Absolute,
                    [ref]$parsedUri
                ) -or
                $parsedUri.Scheme -notin @("http", "https")
            ) {
                throw "Source URL must be a valid http:// or https:// URL."
            }

            $isTikTokUrl = (
                $parsedUri.Host.ToLowerInvariant() -in @(
                    "tiktok.com",
                    "www.tiktok.com",
                    "m.tiktok.com"
                )
            )

            $isYouTubeUrl = (
                $parsedUri.Host.ToLowerInvariant() -in
                $allowedYouTubeHosts
            )
        }

        if ($video) {
            # A supplied local file always wins. The URL, if present,
            # remains provenance only and is never downloaded.
            if (-not (Test-Path -LiteralPath $video -PathType Leaf)) {
                throw "Video file does not exist:`n$video"
            }

            $extension = [System.IO.Path]::GetExtension(
                $video
            ).ToLowerInvariant()

            if ($extension -notin @(".mp4", ".mov", ".mkv", ".webm")) {
                throw "Unsupported video type: $extension"
            }

            $mode = "local"
        }
        elseif ($isTikTokUrl) {
            $mode = "tiktok"
        }
        elseif ($isYouTubeUrl) {
            $mode = "youtube"
        }
        elseif ($url) {
            throw (
                "URL-only mode currently supports YouTube and TikTok only. " +
                "For another platform, provide the downloaded local video file."
            )
        }
        else {
            throw "Choose a local video file or paste a YouTube or TikTok URL."
        }

        $language = if ($langBox.SelectedIndex -eq 1) {
            "auto"
        }
        else {
            "en"
        }

        $logBox.Clear()
        $resultBox.Clear()
        $script:LatestZip = $null
        $copyResult.Enabled = $false
        $openResult.Enabled = $false
        $script:Cancelled = $false
        $script:RunStarted = Get-Date

        if ($mode -eq "youtube") {
            Append-Log "Mode: YouTube URL acquisition"
            Append-Log "YouTube URL: $url"

            if ($contextLabel) {
                Append-Log "Context label override: $contextLabel"
            }
            else {
                Append-Log "Context label: automatic YouTube title"
            }
        }
        elseif ($mode -eq "tiktok") {
            Append-Log "Mode: TikTok URL acquisition"
            Append-Log "TikTok URL: $url"

            if ($contextLabel) {
                Append-Log "Context label override: $contextLabel"
            }
            else {
                Append-Log "Context label: automatic TikTok title"
            }
        }
        else {
            Append-Log "Mode: local video"
            Append-Log "Video: $video"

            if ($url) {
                Append-Log "Source URL: $url"
            }

            if ($contextLabel) {
                Append-Log "Context label: $contextLabel"
            }
        }

        Append-Log "Output: $output"
        Append-Log "Language: $language"
        Append-Log ""

        Set-UiRunning $true
        $statusLabel.Text = "Starting"

        $script:ActiveJob = Start-Job `
            -ArgumentList @(
                $ToolScript,
                $YouTubeHelperScript,
                $TikTokHelperScript,
                $mode,
                $video,
                $output,
                $language,
                $url,
                $contextLabel
            ) `
            -ScriptBlock {
                param(
                    $ToolScript,
                    $YouTubeHelper,
                    $TikTokHelper,
                    $Mode,
                    $Video,
                    $OutputRoot,
                    $Language,
                    $SourceUrl,
                    $JobLabel
                )

                $ErrorActionPreference = "Stop"
                Set-StrictMode -Version Latest

                # Job-local encoding only.
                $env:PYTHONUTF8 = "1"
                $env:PYTHONIOENCODING = "utf-8"
                $env:PYTHONUNBUFFERED = "1"

                $Utf8 = [System.Text.UTF8Encoding]::new($false)
                [Console]::OutputEncoding = $Utf8
                $OutputEncoding = $Utf8

                $effectiveVideo = $Video
                $effectiveTranscript = $null
                $effectiveSourceUrl = $SourceUrl
                $effectiveJobLabel = $JobLabel

                if ($Mode -eq "youtube") {
                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $YouTubeHelper `
                                -PathType Leaf
                        )
                    ) {
                        throw "YouTube acquisition helper missing: $YouTubeHelper"
                    }

                    Write-Output "===== GUI YOUTUBE ACQUISITION ====="

                    # The helper can emit native-tool status output plus its final
                    # PSCustomObject. Capture the success stream, identify the
                    # final structured result, and pass other items through.
                    $helperOutput = @(
                        & $YouTubeHelper -Url $SourceUrl
                    )

                    $acquisition = $null

                    foreach ($item in $helperOutput) {
                        if ($null -eq $item) {
                            continue
                        }

                        $manifestProperty = (
                            $item.PSObject.Properties["manifest_path"]
                        )

                        if (
                            $null -ne $manifestProperty -and
                            $manifestProperty.Value
                        ) {
                            $acquisition = $item
                            continue
                        }

                        Write-Output $item
                    }

                    if ($null -eq $acquisition) {
                        throw (
                            "YouTube acquisition finished without a " +
                            "structured acquisition result."
                        )
                    }

                    $manifestPath = [string]$acquisition.manifest_path

                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $manifestPath `
                                -PathType Leaf
                        )
                    ) {
                        throw "Acquisition manifest missing: $manifestPath"
                    }

                    $manifest = Get-Content `
                        -LiteralPath $manifestPath `
                        -Raw |
                        ConvertFrom-Json

                    if (-not $manifest.ok) {
                        throw "Acquisition manifest reports ok=false."
                    }

                    if ([string]$manifest.platform -ne "youtube") {
                        throw (
                            "Unexpected acquisition platform: " +
                            [string]$manifest.platform
                        )
                    }

                    $effectiveVideo = [string]$manifest.media.path

                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $effectiveVideo `
                                -PathType Leaf
                        )
                    ) {
                        throw "Acquired video missing: $effectiveVideo"
                    }

                    $captionPath = $null

                    if (
                        $null -ne $manifest.captions -and
                        $manifest.captions.path
                    ) {
                        $captionPath = [string]$manifest.captions.path

                        if (
                            -not (
                                Test-Path `
                                    -LiteralPath $captionPath `
                                    -PathType Leaf
                            )
                        ) {
                            throw (
                                "Manifest references a subtitle file " +
                                "that does not exist: $captionPath"
                            )
                        }

                        $effectiveTranscript = $captionPath
                    }

                    if (-not $effectiveJobLabel) {
                        $effectiveJobLabel = [string]$manifest.source.title
                    }

                    if ($manifest.source.url) {
                        $effectiveSourceUrl = [string]$manifest.source.url
                    }

                    Write-Output "Acquired video: $effectiveVideo"
                    Write-Output "Acquisition manifest: $manifestPath"

                    if ($effectiveTranscript) {
                        Write-Output (
                            "Explicit transcript: $effectiveTranscript"
                        )
                    }
                    else {
                        Write-Output (
                            "No acquired subtitle sidecar; " +
                            "converter transcript fallback remains enabled."
                        )
                    }

                    if ($effectiveJobLabel) {
                        Write-Output "Job label: $effectiveJobLabel"
                    }

                    Write-Output ""
                    Write-Output "===== GUI VIDEO CONVERSION ====="
                }
                elseif ($Mode -eq "tiktok") {
                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $TikTokHelper `
                                -PathType Leaf
                        )
                    ) {
                        throw "TikTok acquisition helper missing: $TikTokHelper"
                    }

                    $expectedTikTokHelperHash =
                        "02B8806FAED5A3054BB2F80F61B581A262A282EECA4A5F268983F47C6C4E220A"

                    $actualTikTokHelperHash = (
                        Get-FileHash `
                            -LiteralPath $TikTokHelper `
                            -Algorithm SHA256
                    ).Hash

                    if (
                        $actualTikTokHelperHash -ne
                        $expectedTikTokHelperHash
                    ) {
                        throw (
                            "TikTok acquisition helper hash mismatch. " +
                            "Expected $expectedTikTokHelperHash; " +
                            "found $actualTikTokHelperHash."
                        )
                    }

                    Write-Output "===== GUI TIKTOK ACQUISITION ====="

                    $pwshPath = (
                        Get-Command `
                            pwsh `
                            -CommandType Application `
                            -ErrorAction Stop
                    ).Source

                    # Native pwsh invocation is required here. The previous
                    # ProcessStartInfo -> pwsh path hangs when executed from
                    # this Start-Job worker, while native invocation is proven.
                    $PSNativeCommandUseErrorActionPreference = $false

                    $wrapperErrFile = Join-Path (
                        [IO.Path]::GetTempPath()
                    ) (
                        "VideoAI-GUI-TikTok-" +
                        [Guid]::NewGuid().ToString("N") +
                        ".stderr.txt"
                    )

                    try {
                        $stdoutLines = @(
                            & $pwshPath `
                                -NoLogo `
                                -NoProfile `
                                -ExecutionPolicy Bypass `
                                -File $TikTokHelper `
                                -Url $SourceUrl `
                                2> $wrapperErrFile
                        )

                        $exitCode = $LASTEXITCODE

                        $stdout = (
                            $stdoutLines |
                            ForEach-Object { [string]$_ }
                        ) -join [Environment]::NewLine

                        if ($stdoutLines.Count -gt 0) {
                            $stdout += [Environment]::NewLine
                        }

                        if (
                            Test-Path `
                                -LiteralPath $wrapperErrFile `
                                -PathType Leaf
                        ) {
                            $stderr = [IO.File]::ReadAllText(
                                $wrapperErrFile,
                                [Text.Encoding]::UTF8
                            )
                        }
                        else {
                            $stderr = ""
                        }
                    }
                    finally {
                        Remove-Item `
                            -LiteralPath $wrapperErrFile `
                            -Force `
                            -ErrorAction SilentlyContinue
                    }

                    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                        foreach (
                            $line in
                            ($stderr.TrimEnd() -split "\r?\n")
                        ) {
                            if ($line) {
                                Write-Output $line
                            }
                        }
                    }

                    if ($exitCode -ne 0) {
                        throw (
                            "TikTok acquisition failed with exit code " +
                            "$exitCode."
                        )
                    }

                    $jsonText = $stdout.Trim()

                    if ([string]::IsNullOrWhiteSpace($jsonText)) {
                        throw (
                            "TikTok acquisition completed without " +
                            "structured JSON output."
                        )
                    }

                    try {
                        $acquisition = $jsonText |
                            ConvertFrom-Json
                    }
                    catch {
                        throw (
                            "TikTok acquisition returned invalid JSON: " +
                            $_.Exception.Message
                        )
                    }

                    if (-not $acquisition.ok) {
                        throw "TikTok acquisition reports ok=false."
                    }

                    if (
                        [string]$acquisition.platform -ne
                        "tiktok"
                    ) {
                        throw (
                            "Unexpected TikTok acquisition platform: " +
                            [string]$acquisition.platform
                        )
                    }

                    if (
                        [string]$acquisition.source_url -ne
                        [string]$SourceUrl
                    ) {
                        throw (
                            "TikTok acquisition source URL mismatch."
                        )
                    }

                    $manifestPath =
                        [string]$acquisition.manifest_path

                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $manifestPath `
                                -PathType Leaf
                        )
                    ) {
                        throw (
                            "TikTok acquisition manifest missing: " +
                            $manifestPath
                        )
                    }

                    $manifest = Get-Content `
                        -LiteralPath $manifestPath `
                        -Raw `
                        -Encoding UTF8 |
                        ConvertFrom-Json

                    if (
                        [string]$manifest.schema -ne
                        "videoai-acquisition/v1"
                    ) {
                        throw (
                            "Unexpected TikTok acquisition schema: " +
                            [string]$manifest.schema
                        )
                    }

                    if (
                        [string]$manifest.platform -ne
                        "tiktok"
                    ) {
                        throw (
                            "Unexpected TikTok manifest platform: " +
                            [string]$manifest.platform
                        )
                    }

                    if (
                        [string]$manifest.source_url -ne
                        [string]$SourceUrl
                    ) {
                        throw "TikTok manifest source URL mismatch."
                    }

                    if (
                        [string]$manifest.video_id -ne
                        [string]$acquisition.video_id
                    ) {
                        throw "TikTok video ID mismatch."
                    }

                    $effectiveVideo =
                        [string]$manifest.media.path

                    if (
                        -not (
                            Test-Path `
                                -LiteralPath $effectiveVideo `
                                -PathType Leaf
                        )
                    ) {
                        throw (
                            "Acquired TikTok video missing: " +
                            $effectiveVideo
                        )
                    }

                    if (
                        [string]$acquisition.video_path -ne
                        [string]$effectiveVideo
                    ) {
                        throw (
                            "TikTok result/manifest video path mismatch."
                        )
                    }

                    $actualMediaHash = (
                        Get-FileHash `
                            -LiteralPath $effectiveVideo `
                            -Algorithm SHA256
                    ).Hash

                    $actualMediaBytes = (
                        Get-Item `
                            -LiteralPath $effectiveVideo
                    ).Length

                    if (
                        [string]$manifest.media.sha256 -ne
                        [string]$actualMediaHash
                    ) {
                        throw (
                            "TikTok manifest/media SHA256 mismatch."
                        )
                    }

                    if (
                        [int64]$manifest.media.bytes -ne
                        [int64]$actualMediaBytes
                    ) {
                        throw (
                            "TikTok manifest/media byte-count mismatch."
                        )
                    }

                    if (
                        [string]$acquisition.sha256 -ne
                        [string]$actualMediaHash
                    ) {
                        throw (
                            "TikTok result/media SHA256 mismatch."
                        )
                    }

                    if (
                        [int64]$acquisition.bytes -ne
                        [int64]$actualMediaBytes
                    ) {
                        throw (
                            "TikTok result/media byte-count mismatch."
                        )
                    }

                    $effectiveTranscript = $null

                    if (
                        $null -ne $manifest.captions -and
                        $manifest.captions.path
                    ) {
                        $captionPath =
                            [string]$manifest.captions.path

                        if (
                            -not (
                                Test-Path `
                                    -LiteralPath $captionPath `
                                    -PathType Leaf
                            )
                        ) {
                            throw (
                                "TikTok manifest references a " +
                                "subtitle file that does not exist: " +
                                $captionPath
                            )
                        }

                        $effectiveTranscript = $captionPath
                    }

                    if (-not $effectiveJobLabel) {
                        $effectiveJobLabel =
                            [string]$manifest.title
                    }

                    if ($manifest.source_url) {
                        $effectiveSourceUrl =
                            [string]$manifest.source_url
                    }

                    Write-Output "Acquired video: $effectiveVideo"
                    Write-Output "Acquisition manifest: $manifestPath"

                    if ($effectiveTranscript) {
                        Write-Output (
                            "Explicit transcript: " +
                            $effectiveTranscript
                        )
                    }
                    else {
                        Write-Output (
                            "No acquired subtitle sidecar; " +
                            "Whisper transcript fallback remains enabled."
                        )
                    }

                    if ($effectiveJobLabel) {
                        Write-Output (
                            "Job label: " +
                            $effectiveJobLabel
                        )
                    }

                    Write-Output ""
                    Write-Output "===== GUI VIDEO CONVERSION ====="
                }

                $parameters = @{
                    Video      = $effectiveVideo
                    OutputRoot = $OutputRoot
                    Language   = $Language
                }

                if ($effectiveSourceUrl) {
                    $parameters["SourceUrl"] = $effectiveSourceUrl
                }

                if ($effectiveJobLabel) {
                    $parameters["JobLabel"] = $effectiveJobLabel
                }

                if ($effectiveTranscript) {
                    $parameters["Transcript"] = $effectiveTranscript
                }

                & $ToolScript @parameters *>&1 |
                    ForEach-Object {
                        if (
                            $_ -is
                            [System.Management.Automation.ErrorRecord]
                        ) {
                            $_.ToString()
                        }
                        else {
                            ($_ | Out-String).TrimEnd()
                        }
                    }
            }
    }
    catch {
        Set-UiRunning $false
        $statusLabel.Text = "Ready"
        Show-UiError $_.Exception.Message
    }
})

$cancelButton.Add_Click({
    if ($script:ActiveJob) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Cancel this conversion?`n`nA partial job directory may remain for inspection.",
            "VideoAI",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:Cancelled = $true
            Stop-Job -Job $script:ActiveJob -ErrorAction SilentlyContinue
            $statusLabel.Text = "Cancelling"
        }
    }
})

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 350

$timer.Add_Tick({
    if (-not $script:ActiveJob) {
        return
    }

    try {
        $items = @(
            Receive-Job `
                -Job $script:ActiveJob `
                -ErrorAction SilentlyContinue
        )

        foreach ($item in $items) {
            $text = ($item | Out-String).TrimEnd()
            if ($text) {
                Append-Log $text
            }
        }
    }
    catch {
        Append-Log "GUI log read warning: $($_.Exception.Message)"
    }

    if ($script:ActiveJob.State -in @("Completed", "Failed", "Stopped")) {
        $finalState = $script:ActiveJob.State

        try {
            $remaining = @(
                Receive-Job `
                    -Job $script:ActiveJob `
                    -ErrorAction SilentlyContinue
            )

            foreach ($item in $remaining) {
                $text = ($item | Out-String).TrimEnd()
                if ($text) {
                    Append-Log $text
                }
            }
        }
        catch {
        }

        if ($finalState -eq "Failed") {
            foreach ($err in @($script:ActiveJob.ChildJobs[0].JobStateInfo.Reason)) {
                if ($err) {
                    Append-Log "FAILED: $err"
                }
            }
        }

        Remove-Job -Job $script:ActiveJob -Force -ErrorAction SilentlyContinue
        $script:ActiveJob = $null
        Set-UiRunning $false

        if ($script:Cancelled -or $finalState -eq "Stopped") {
            $statusLabel.Text = "Cancelled"
            Append-Log ""
            Append-Log "Conversion cancelled. A partial job may remain."
            return
        }

        if ($finalState -eq "Failed") {
            $statusLabel.Text = "Failed"
            Append-Log ""
            Append-Log "Conversion failed. Review the log above."
            return
        }

        $zip = Find-NewestZip `
            -Root $outputRow.Box.Text.Trim().Trim('"') `
            -Since $script:RunStarted

        if ($zip) {
            $script:LatestZip = $zip.FullName
            $resultBox.Text = $script:LatestZip
            $copyResult.Enabled = $true
            $openResult.Enabled = $true
            $statusLabel.Text = "Complete"

            Append-Log ""
            Append-Log "===== GUI COMPLETE ====="
            Append-Log "AI ZIP: $script:LatestZip"
        }
        else {
            $statusLabel.Text = "Completed; ZIP not located"
            Append-Log ""
            Append-Log "Backend completed, but the GUI could not locate a newly-created *-ai.zip."
        }
    }
})

$form.Add_FormClosing({
    param($sender, $e)

    if ($script:ActiveJob) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "A conversion is still running. Stop it and close the GUI?",
            "VideoAI",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }

        $script:Cancelled = $true
        Stop-Job -Job $script:ActiveJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:ActiveJob -Force -ErrorAction SilentlyContinue
        $script:ActiveJob = $null
    }

    $timer.Stop()
})

$timer.Start()

[void]$form.ShowDialog()

$timer.Stop()
$timer.Dispose()
$form.Dispose()
