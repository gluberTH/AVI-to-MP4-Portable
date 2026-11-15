# Portable Windows Forms AVI-to-MP4 converter for Windows 10/11.
# Requires Windows PowerShell 5.1; does not require Python or an installer.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:bin = Join-Path $script:root 'bin'
$script:tempDir = Join-Path $env:TEMP 'AVI-to-MP4-Portable'
[IO.Directory]::CreateDirectory($script:tempDir) | Out-Null
$script:ffmpeg = $null
$script:ffprobe = $null
$script:converter = $null
$script:installer = $null
$script:installStatus = Join-Path $script:tempDir 'install.status'
$script:installAutoStart = $false
$script:currentInput = $null
$script:currentOutput = $null
$script:currentItem = $null
$script:currentDuration = 0.0
$script:progressFile = $null
$script:currentLog = $null
$script:lastErrorLog = $null
$script:stderrTask = $null
$script:cancelRequested = $false
$script:isBatchRunning = $false
$script:nextIndex = 0
$script:completed = 0
$script:failed = 0
$script:videoFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Q([string]$value) {
    return '"' + $value.Replace('"', '\"') + '"'
}

function Locate-FFmpeg {
    $localFfmpeg = Join-Path $script:bin 'ffmpeg.exe'
    $localFfprobe = Join-Path $script:bin 'ffprobe.exe'
    if (Test-Path -LiteralPath $localFfmpeg -PathType Leaf) {
        $script:ffmpeg = $localFfmpeg
        if (Test-Path -LiteralPath $localFfprobe -PathType Leaf) { $script:ffprobe = $localFfprobe }
        else { $script:ffprobe = $null }
        return $true
    }
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        $script:ffmpeg = $cmd.Source
        $probeCmd = Get-Command ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($probeCmd) { $script:ffprobe = $probeCmd.Source }
        else { $script:ffprobe = $null }
        return $true
    }
    $script:ffmpeg = $null
    $script:ffprobe = $null
    return $false
}

function Show-Error([string]$message) {
    [void][System.Windows.Forms.MessageBox]::Show($form, $message, 'AVI → MP4', 'OK', 'Error')
}

# ---------------- UI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AVI → MP4 | Portable Converter'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(960, 660)
$form.MinimumSize = New-Object System.Drawing.Size(780, 550)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [Drawing.Color]::FromArgb(246, 248, 251)

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object Drawing.Point(0, 0)
$header.Size = New-Object Drawing.Size(960, 96)
$header.Anchor = 'Top,Left,Right'
$header.BackColor = [Drawing.Color]::FromArgb(31, 41, 55)
$form.Controls.Add($header)

$headline = New-Object System.Windows.Forms.Label
$headline.Text = 'AVI  →  MP4'
$headline.Location = New-Object Drawing.Point(24, 16)
$headline.Size = New-Object Drawing.Size(380, 37)
$headline.Font = New-Object Drawing.Font('Segoe UI', 20, [Drawing.FontStyle]::Bold)
$headline.ForeColor = [Drawing.Color]::White
$header.Controls.Add($headline)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Конвертер видео • H.264 + AAC • без Python и установки'
$subtitle.Location = New-Object Drawing.Point(27, 58)
$subtitle.Size = New-Object Drawing.Size(650, 24)
$subtitle.ForeColor = [Drawing.Color]::FromArgb(210, 219, 232)
$header.Controls.Add($subtitle)

$ffmpegState = New-Object System.Windows.Forms.Label
$ffmpegState.Location = New-Object Drawing.Point(675, 38)
$ffmpegState.Size = New-Object Drawing.Size(260, 24)
$ffmpegState.Anchor = 'Top,Right'
$ffmpegState.TextAlign = 'MiddleRight'
$ffmpegState.ForeColor = [Drawing.Color]::FromArgb(224, 231, 239)
$header.Controls.Add($ffmpegState)

$fileTitle = New-Object System.Windows.Forms.Label
$fileTitle.Text = 'ВИДЕОФАЙЛЫ'
$fileTitle.Location = New-Object Drawing.Point(24, 111)
$fileTitle.Size = New-Object Drawing.Size(210, 22)
$fileTitle.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($fileTitle)

$fileCount = New-Object System.Windows.Forms.Label
$fileCount.Text = '0 файлов • Можно перетащить AVI прямо в окно'
$fileCount.Location = New-Object Drawing.Point(24, 137)
$fileCount.Size = New-Object Drawing.Size(450, 22)
$fileCount.ForeColor = [Drawing.Color]::FromArgb(99, 110, 125)
$form.Controls.Add($fileCount)

function Make-Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'System'
    return $b
}

$btnAdd = Make-Button '+ Добавить AVI' 505 118 126 32
$btnRemove = Make-Button 'Убрать' 642 118 84 32
$btnClear = Make-Button 'Очистить' 736 118 90 32
$btnDownload = Make-Button 'Скачать FFmpeg' 837 118 105 32
foreach ($b in @($btnAdd, $btnRemove, $btnClear, $btnDownload)) {
    $b.Anchor = 'Top,Right'
    $form.Controls.Add($b)
}

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object Drawing.Point(24, 168)
$list.Size = New-Object Drawing.Size(912, 221)
$list.Anchor = 'Top,Bottom,Left,Right'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $true
$list.MultiSelect = $true
$list.HideSelection = $false
$list.AllowDrop = $true
[void]$list.Columns.Add('Файл', 577)
[void]$list.Columns.Add('Размер', 110)
[void]$list.Columns.Add('Состояние', 205)
$form.Controls.Add($list)

$outputGroup = New-Object System.Windows.Forms.GroupBox
$outputGroup.Text = 'Куда сохранять MP4'
$outputGroup.Location = New-Object Drawing.Point(24, 401)
$outputGroup.Size = New-Object Drawing.Size(912, 88)
$outputGroup.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($outputGroup)

$cbSameFolder = New-Object System.Windows.Forms.CheckBox
$cbSameFolder.Text = 'Рядом с исходным AVI'
$cbSameFolder.Location = New-Object Drawing.Point(16, 26)
$cbSameFolder.Size = New-Object Drawing.Size(188, 26)
$cbSameFolder.Checked = $true
$outputGroup.Controls.Add($cbSameFolder)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object Drawing.Point(210, 27)
$txtOutput.Size = New-Object Drawing.Size(565, 24)
$txtOutput.Anchor = 'Top,Left,Right'
$txtOutput.Enabled = $false
$txtOutput.Text = '(в папку каждого исходного файла)'
$outputGroup.Controls.Add($txtOutput)

$btnChooseDir = Make-Button 'Обзор...' 786 25 110 29
$btnChooseDir.Anchor = 'Top,Right'
$btnChooseDir.Enabled = $false
$outputGroup.Controls.Add($btnChooseDir)

$outputTip = New-Object System.Windows.Forms.Label
$outputTip.Text = 'Исходные AVI не удаляются. Если MP4 уже существует, будет создан файл с новым именем.'
$outputTip.Location = New-Object Drawing.Point(16, 58)
$outputTip.Size = New-Object Drawing.Size(865, 20)
$outputTip.ForeColor = [Drawing.Color]::FromArgb(101, 112, 126)
$outputGroup.Controls.Add($outputTip)

$settings = New-Object System.Windows.Forms.GroupBox
$settings.Text = 'Настройки конвертации'
$settings.Location = New-Object Drawing.Point(24, 497)
$settings.Size = New-Object Drawing.Size(912, 76)
$settings.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($settings)

$qualityLabel = New-Object System.Windows.Forms.Label
$qualityLabel.Text = 'Качество:'
$qualityLabel.Location = New-Object Drawing.Point(16, 33)
$qualityLabel.Size = New-Object Drawing.Size(74, 23)
$settings.Controls.Add($qualityLabel)

$cboQuality = New-Object System.Windows.Forms.ComboBox
$cboQuality.DropDownStyle = 'DropDownList'
$cboQuality.Location = New-Object Drawing.Point(92, 29)
$cboQuality.Size = New-Object Drawing.Size(310, 25)
[void]$cboQuality.Items.Add('Сбалансированное (рекомендуется)')
[void]$cboQuality.Items.Add('Высокое качество (больше файл)')
[void]$cboQuality.Items.Add('Меньше размер (ниже качество)')
$cboQuality.SelectedIndex = 0
$settings.Controls.Add($cboQuality)

$speedLabel = New-Object System.Windows.Forms.Label
$speedLabel.Text = 'Скорость:'
$speedLabel.Location = New-Object Drawing.Point(460, 33)
$speedLabel.Size = New-Object Drawing.Size(78, 23)
$settings.Controls.Add($speedLabel)

$cboSpeed = New-Object System.Windows.Forms.ComboBox
$cboSpeed.DropDownStyle = 'DropDownList'
$cboSpeed.Location = New-Object Drawing.Point(544, 29)
$cboSpeed.Size = New-Object Drawing.Size(290, 25)
$cboSpeed.Anchor = 'Top,Left,Right'
[void]$cboSpeed.Items.Add('Обычно (лучше сжатие)')
[void]$cboSpeed.Items.Add('Быстрее (файл может быть крупнее)')
$cboSpeed.SelectedIndex = 0
$settings.Controls.Add($cboSpeed)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Готово к работе'
$statusLabel.Location = New-Object Drawing.Point(24, 584)
$statusLabel.Size = New-Object Drawing.Size(660, 22)
$statusLabel.Anchor = 'Bottom,Left,Right'
$statusLabel.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$form.Controls.Add($statusLabel)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(24, 611)
$progress.Size = New-Object Drawing.Size(685, 18)
$progress.Anchor = 'Bottom,Left,Right'
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Text = 'Добавьте AVI-файлы и нажмите «Конвертировать».'
$detailLabel.Location = New-Object Drawing.Point(24, 635)
$detailLabel.Size = New-Object Drawing.Size(685, 19)
$detailLabel.Anchor = 'Bottom,Left,Right'
$detailLabel.ForeColor = [Drawing.Color]::FromArgb(104, 115, 128)
$form.Controls.Add($detailLabel)

$btnStart = Make-Button 'Конвертировать' 721 600 147 40
$btnStart.Anchor = 'Bottom,Right'
$btnStart.BackColor = [Drawing.Color]::FromArgb(36, 120, 213)
$btnStart.ForeColor = [Drawing.Color]::White
$btnStart.FlatStyle = 'Flat'
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($btnStart)

$btnCancel = Make-Button 'Стоп' 878 600 58 40
$btnCancel.Anchor = 'Bottom,Right'
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

# ---------------- Helpers ----------------
function Update-FileCount {
    $fileCount.Text = ('{0} файлов • Можно перетащить AVI прямо в окно' -f $list.Items.Count)
}

function Set-UiBusy([bool]$busy) {
    foreach ($control in @($btnAdd, $btnRemove, $btnClear, $cboQuality, $cboSpeed, $cbSameFolder, $txtOutput, $btnChooseDir)) {
        $control.Enabled = -not $busy
    }
    if (-not $busy) {
        $txtOutput.Enabled = -not $cbSameFolder.Checked
        $btnChooseDir.Enabled = -not $cbSameFolder.Checked
    }
    $btnStart.Enabled = -not $busy
    $btnCancel.Enabled = $busy
    $btnDownload.Enabled = -not $busy -and -not $script:installer
}

function Add-Videos([string[]]$paths) {
    $added = 0
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ([IO.Path]::GetExtension($path).ToLowerInvariant() -ne '.avi') { continue }
        $full = [IO.Path]::GetFullPath($path)
        if ($script:videoFiles.Contains($full)) { continue }
        $f = Get-Item -LiteralPath $full
        $row = New-Object System.Windows.Forms.ListViewItem($f.Name)
        [void]$row.SubItems.Add(('{0:N1} МБ' -f ($f.Length / 1MB)))
        [void]$row.SubItems.Add('В очереди')
        $row.Tag = $full
        [void]$list.Items.Add($row)
        [void]$script:videoFiles.Add($full)
        $added++
    }
    Update-FileCount
    if ($added -gt 0) { $detailLabel.Text = ('Добавлено файлов: {0}. Можно запускать!' -f $added) }
}

function Get-OutputPath([string]$source) {
    if ($cbSameFolder.Checked) {
        $folder = [IO.Path]::GetDirectoryName($source)
    } else {
        $folder = $txtOutput.Text.Trim()
    }
    if (-not [IO.Directory]::Exists($folder)) { [IO.Directory]::CreateDirectory($folder) | Out-Null }
    $base = [IO.Path]::GetFileNameWithoutExtension($source)
    $target = Join-Path $folder ($base + '.mp4')
    $i = 1
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $folder (('{0} ({1}).mp4' -f $base, $i))
        $i++
    }
    return $target
}

function Get-VideoDuration([string]$source) {
    if (-not $script:ffprobe) { return 0.0 }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ffprobe
    $psi.Arguments = '-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ' + (Q $source)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    try {
        $p = [Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(8000)) { $p.Kill(); return 0.0 }
        $result = $p.StandardOutput.ReadToEnd().Trim()
        $d = 0.0
        if ([double]::TryParse($result, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            return [Math]::Max(0.0, $d)
        }
    } catch { }
    return 0.0
}

function Read-ProgressPercent {
    if (-not $script:progressFile -or -not [IO.File]::Exists($script:progressFile)) { return -1 }
    try {
        $fs = [IO.File]::Open($script:progressFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $r = New-Object IO.StreamReader($fs)
            $data = $r.ReadToEnd()
            $r.Dispose()
        } finally {
            $fs.Dispose()
        }
        $matches = [regex]::Matches($data, '(?m)^out_time=(\d{2,}:\d{2}:\d{2}(?:\.\d+)?)')
        if ($matches.Count -eq 0 -or $script:currentDuration -le 0) { return -1 }
        $lastTime = $matches[$matches.Count - 1].Groups[1].Value
        $ts = [TimeSpan]::Zero
        if ([TimeSpan]::TryParse($lastTime, [Globalization.CultureInfo]::InvariantCulture, [ref]$ts)) {
            return [Math]::Min(99, [Math]::Max(0, [int][Math]::Floor($ts.TotalSeconds * 100.0 / $script:currentDuration)))
        }
    } catch { }
    return -1
}

function Refresh-FFmpegState {
    if (Locate-FFmpeg) {
        $ffmpegState.Text = '● FFmpeg готов'
        $btnDownload.Visible = $false
        $detailLabel.Text = 'FFmpeg доступен. Можно конвертировать AVI.'
    } else {
        $ffmpegState.Text = '○ Требуется FFmpeg'
        $btnDownload.Visible = $true
        $detailLabel.Text = 'FFmpeg скачается при первом запуске конвертации (нужен интернет).'
    }
}

function Start-Install {
    if ($script:installer) { return }
    $setup = Join-Path $script:root 'Setup-FFmpeg.ps1'
    if (-not (Test-Path -LiteralPath $setup)) { Show-Error 'Файл Setup-FFmpeg.ps1 не найден.'; return }
    try {
        if (Test-Path -LiteralPath $script:installStatus) { Remove-Item -LiteralPath $script:installStatus -Force }
        [IO.Directory]::CreateDirectory($script:bin) | Out-Null
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Q $setup) + ' -Destination ' + (Q $script:bin) + ' -StatusFile ' + (Q $script:installStatus)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $script:installer = [Diagnostics.Process]::Start($psi)
        $statusLabel.Text = 'Подготавливаем FFmpeg...'
        $detailLabel.Text = 'Один раз скачиваем видеодвижок. В дальнейшем интернет не нужен.'
        $progress.Style = 'Marquee'
        Set-UiBusy $true
        $btnCancel.Enabled = $true
    } catch {
        $script:installer = $null
        Set-UiBusy $false
        Show-Error ('Не удалось начать загрузку FFmpeg: ' + $_.Exception.Message)
    }
}

function Start-NextVideo {
    if ($script:cancelRequested) {
        End-Batch
        return
    }
    if ($script:nextIndex -ge $list.Items.Count) {
        End-Batch
        return
    }
    $script:currentItem = $list.Items[$script:nextIndex]
    $script:nextIndex++
    $script:currentInput = [string]$script:currentItem.Tag
    try {
        $script:currentOutput = Get-OutputPath $script:currentInput
        $script:currentDuration = Get-VideoDuration $script:currentInput
        $script:progressFile = Join-Path $script:tempDir ('ffmpeg_' + [guid]::NewGuid().ToString('N') + '.progress')
        $script:currentLog = $null
        $crf = switch ($cboQuality.SelectedIndex) { 1 { 18 } 2 { 28 } default { 23 } }
        $preset = if ($cboSpeed.SelectedIndex -eq 1) { 'veryfast' } else { 'medium' }
        $args = @(
            '-hide_banner', '-nostdin', '-loglevel error', '-nostats', '-stats_period 0.5',
            '-progress', (Q $script:progressFile),
            '-i', (Q $script:currentInput),
            '-map 0:v:0', '-map 0:a:0?', '-sn', '-dn',
            '-vf scale=trunc(iw/2)*2:trunc(ih/2)*2',
            '-c:v libx264', ('-preset ' + $preset), ('-crf ' + $crf), '-pix_fmt yuv420p',
            '-c:a aac', '-b:a 192k', '-movflags +faststart', '-max_muxing_queue_size 1024', '-n',
            (Q $script:currentOutput)
        ) -join ' '
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $script:ffmpeg
        $psi.Arguments = $args
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $script:root
        # Drain stderr asynchronously to prevent FFmpeg from blocking on a full pipe.
        $psi.RedirectStandardError = $true
        $script:converter = [Diagnostics.Process]::Start($psi)
        $script:stderrTask = $script:converter.StandardError.ReadToEndAsync()
        $script:currentItem.SubItems[2].Text = 'Конвертация...'
        $statusLabel.Text = ('Файл {0}/{1}: {2}' -f $script:nextIndex, $list.Items.Count, $script:currentItem.Text)
        $detailLabel.Text = ('MP4: ' + $script:currentOutput)
        $progress.Style = if ($script:currentDuration -gt 0) { 'Continuous' } else { 'Marquee' }
        if ($script:currentDuration -gt 0) { $progress.Value = 0 }
        $script:currentItem.EnsureVisible()
    } catch {
        $script:failed++
        if ($script:currentItem) { $script:currentItem.SubItems[2].Text = 'Ошибка запуска' }
        $detailLabel.Text = $_.Exception.Message
        $script:converter = $null
        Start-NextVideo
    }
}

function Start-Batch {
    if ($list.Items.Count -eq 0) {
        [void][Windows.Forms.MessageBox]::Show($form, 'Сначала добавьте хотя бы один AVI-файл.', 'AVI → MP4', 'OK', 'Information')
        return
    }
    if (-not $cbSameFolder.Checked) {
        if ([string]::IsNullOrWhiteSpace($txtOutput.Text)) {
            Show-Error 'Выберите папку для сохранения MP4.'
            return
        }
        try { [IO.Directory]::CreateDirectory($txtOutput.Text.Trim()) | Out-Null }
        catch { Show-Error ('Папка недоступна: ' + $_.Exception.Message); return }
    }
    if (-not (Locate-FFmpeg)) {
        $script:installAutoStart = $true
        Start-Install
        return
    }
    $script:cancelRequested = $false
    $script:isBatchRunning = $true
    $script:nextIndex = 0
    $script:completed = 0
    $script:failed = 0
    $script:lastErrorLog = $null
    foreach ($row in $list.Items) { $row.SubItems[2].Text = 'В очереди' }
    Set-UiBusy $true
    Start-NextVideo
}

function End-Batch {
    $script:isBatchRunning = $false
    $script:converter = $null
    Set-UiBusy $false
    $progress.Style = 'Continuous'
    $progress.Value = 0
    if ($script:cancelRequested) {
        $statusLabel.Text = 'Конвертация остановлена'
    } else {
        $statusLabel.Text = ('Готово! Успешно: {0} • Ошибок: {1}' -f $script:completed, $script:failed)
    }
    if ($script:failed -gt 0 -and $script:lastErrorLog) {
        $detailLabel.Text = ('Подробности последней ошибки: ' + $script:lastErrorLog)
    } else {
        $detailLabel.Text = 'Готовые MP4 находятся рядом с AVI или в выбранной папке.'
    }
}

function Stop-ActiveWork {
    if ($script:installer) {
        try { if (-not $script:installer.HasExited) { $script:installer.Kill() } } catch { }
        try { $script:installer.Dispose() } catch { }
        $script:installer = $null
        $script:installAutoStart = $false
        $statusLabel.Text = 'Загрузка FFmpeg отменена'
        $detailLabel.Text = 'Нажмите «Скачать FFmpeg», чтобы попробовать ещё раз.'
        $progress.Style = 'Continuous'
        $progress.Value = 0
        Set-UiBusy $false
        return
    }
    if ($script:isBatchRunning) {
        $script:cancelRequested = $true
        if ($script:converter) {
            try { if (-not $script:converter.HasExited) { $script:converter.Kill() } } catch { }
        } else {
            End-Batch
        }
    }
}

# ---------------- Events ----------------
$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Выберите AVI-видео'
    $dlg.Filter = 'AVI видео (*.avi)|*.avi'
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog($form) -eq 'OK') { Add-Videos $dlg.FileNames }
    $dlg.Dispose()
})
$btnRemove.Add_Click({
    $selected = @()
    foreach ($item in $list.SelectedItems) { $selected += $item }
    foreach ($item in $selected) {
        [void]$script:videoFiles.Remove([string]$item.Tag)
        $list.Items.Remove($item)
    }
    Update-FileCount
})
$btnClear.Add_Click({
    $list.Items.Clear()
    $script:videoFiles.Clear()
    Update-FileCount
})
$btnDownload.Add_Click({ $script:installAutoStart = $false; Start-Install })
$btnStart.Add_Click({ Start-Batch })
$btnCancel.Add_Click({ Stop-ActiveWork })
$cbSameFolder.Add_CheckedChanged({
    if (-not $script:isBatchRunning -and -not $script:installer) {
        $txtOutput.Enabled = -not $cbSameFolder.Checked
        $btnChooseDir.Enabled = -not $cbSameFolder.Checked
    }
    if ($cbSameFolder.Checked) { $txtOutput.Text = '(в папку каждого исходного файла)' }
    elseif ($txtOutput.Text.StartsWith('(')) { $txtOutput.Text = [Environment]::GetFolderPath('Desktop') }
})
$btnChooseDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Папка для готовых MP4'
    if ($dlg.ShowDialog($form) -eq 'OK') { $txtOutput.Text = $dlg.SelectedPath }
    $dlg.Dispose()
})
$list.Add_DragEnter({
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [Windows.Forms.DragDropEffects]::Copy
    } else { $_.Effect = [Windows.Forms.DragDropEffects]::None }
})
$list.Add_DragDrop({
    if (-not $script:isBatchRunning -and -not $script:installer) {
        $paths = [string[]]$_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
        Add-Videos $paths
    }
})
$list.Add_Resize({
    $list.Columns[0].Width = [Math]::Max(350, $list.ClientSize.Width - 335)
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    try {
        if ($script:installer) {
            if (Test-Path -LiteralPath $script:installStatus) {
                try {
                    $state = [IO.File]::ReadAllText($script:installStatus, [Text.Encoding]::UTF8).Trim([char]0xFEFF).Split('|', 3)
                    if ($state.Length -eq 3) {
                        $statusLabel.Text = $state[2]
                        if ($state[0] -eq 'error') { $detailLabel.Text = $state[2] }
                        if ($state[1] -match '^\d+$') {
                            $progress.Style = 'Continuous'
                            $progress.Value = [Math]::Min(100, [int]$state[1])
                        }
                    }
                } catch { }
            }
            if ($script:installer.HasExited) {
                $installCode = $script:installer.ExitCode
                $script:installer.Dispose()
                $script:installer = $null
                if ($installCode -eq 0 -and (Locate-FFmpeg)) {
                    Refresh-FFmpegState
                    Set-UiBusy $false
                    $statusLabel.Text = 'FFmpeg установлен!'
                    $progress.Value = 0
                    if ($script:installAutoStart) {
                        $script:installAutoStart = $false
                        Start-Batch
                    }
                } else {
                    Set-UiBusy $false
                    $script:installAutoStart = $false
                    if ($statusLabel.Text -notlike 'Ошибка*') { $statusLabel.Text = 'Не удалось скачать FFmpeg' }
                    $progress.Style = 'Continuous'
                    $progress.Value = 0
                }
            }
        }
        if ($script:converter) {
            if (-not $script:converter.HasExited) {
                $pct = Read-ProgressPercent
                if ($pct -ge 0) {
                    $progress.Style = 'Continuous'
                    $progress.Value = $pct
                    $script:currentItem.SubItems[2].Text = ('{0}%' -f $pct)
                }
            } else {
                $code = $script:converter.ExitCode
                $stderrText = ''
                if ($script:stderrTask) {
                    try { $stderrText = [string]$script:stderrTask.Result } catch { }
                    $script:stderrTask = $null
                }
                $script:converter.Dispose()
                $script:converter = $null
                if ($script:progressFile -and (Test-Path -LiteralPath $script:progressFile)) {
                    Remove-Item -LiteralPath $script:progressFile -Force -ErrorAction SilentlyContinue
                }
                if ($script:cancelRequested) {
                    $script:currentItem.SubItems[2].Text = 'Отменено'
                } elseif ($code -eq 0 -and (Test-Path -LiteralPath $script:currentOutput)) {
                    $script:completed++
                    $script:currentItem.SubItems[2].Text = 'Готово ✓'
                    $progress.Style = 'Continuous'
                    $progress.Value = 100
                } else {
                    $script:failed++
                    $script:currentItem.SubItems[2].Text = 'Ошибка'
                    $script:currentLog = Join-Path (Join-Path $script:root 'logs') ('error-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.txt')
                    try {
                        [IO.Directory]::CreateDirectory((Split-Path -Parent $script:currentLog)) | Out-Null
                        [IO.File]::WriteAllText($script:currentLog, ("Source: " + $script:currentInput + "`r`nDestination: " + $script:currentOutput + "`r`nExit code: " + $code + "`r`n`r`n" + $stderrText), [Text.Encoding]::UTF8)
                        $script:lastErrorLog = $script:currentLog
                        $detailLabel.Text = ('Ошибка FFmpeg. Подробности: ' + $script:currentLog)
                    } catch {
                        $detailLabel.Text = ('Ошибка FFmpeg для файла: ' + $script:currentItem.Text)
                    }
                }
                if (($code -ne 0 -or $script:cancelRequested) -and $script:currentOutput -and (Test-Path -LiteralPath $script:currentOutput)) {
                    Remove-Item -LiteralPath $script:currentOutput -Force -ErrorAction SilentlyContinue
                }
                Start-NextVideo
            }
        }
    } catch {
        $statusLabel.Text = ('Ошибка интерфейса: ' + $_.Exception.Message)
    }
})
$form.Add_FormClosing({
    if ($script:installer -or $script:isBatchRunning) {
        $choice = [Windows.Forms.MessageBox]::Show($form, 'Прервать текущую работу и закрыть программу?', 'AVI → MP4', 'YesNo', 'Question')
        if ($choice -ne 'Yes') { $_.Cancel = $true; return }
        Stop-ActiveWork
        if ($script:converter) {
            try { $script:converter.WaitForExit(1500) | Out-Null } catch { }
        }
        # The UI timer will not tick after the window closes. Clean up explicitly.
        if ($script:currentOutput -and $script:cancelRequested -and (Test-Path -LiteralPath $script:currentOutput)) {
            Remove-Item -LiteralPath $script:currentOutput -Force -ErrorAction SilentlyContinue
        }
        if ($script:progressFile -and (Test-Path -LiteralPath $script:progressFile)) {
            Remove-Item -LiteralPath $script:progressFile -Force -ErrorAction SilentlyContinue
        }
    }
})

Refresh-FFmpegState
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop()
$timer.Dispose()
$form.Dispose()
