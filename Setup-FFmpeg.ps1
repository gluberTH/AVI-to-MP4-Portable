param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$StatusFile
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-InstallStatus([string]$phase, [int]$percent, [string]$message) {
    try {
        [IO.File]::WriteAllText($StatusFile, "$phase|$percent|$message", [Text.Encoding]::UTF8)
    } catch {
        # A status-file failure must not interrupt an otherwise successful installation.
    }
}

$archive = Join-Path ([IO.Path]::GetTempPath()) ('avi_mp4_ffmpeg_' + [guid]::NewGuid().ToString('N') + '.zip')
try {
    $url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
    $hashUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256'

    Write-InstallStatus 'download' 0 'Загрузка FFmpeg (потребуется около 110 МБ)...'
    $request = [Net.HttpWebRequest][Net.WebRequest]::Create($url)
    $request.UserAgent = 'AVI-to-MP4-Portable/1.0'
    $request.Timeout = 60000
    $request.ReadWriteTimeout = 120000
    $response = $request.GetResponse()
    $stream = $response.GetResponseStream()
    $target = [IO.File]::Open($archive, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $length = [double]$response.ContentLength
        $written = [double]0
        $last = -1
        $buffer = New-Object byte[] (1024 * 1024)
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $target.Write($buffer, 0, $read)
            $written += $read
            if ($length -gt 0) {
                $pct = [Math]::Min(78, [int][Math]::Floor($written * 78 / $length))
                if ($pct -gt $last) {
                    $last = $pct
                    Write-InstallStatus 'download' $pct ("Загрузка FFmpeg: {0}%" -f [int][Math]::Floor($written * 100 / $length))
                }
            }
        }
    } finally {
        $target.Dispose()
        $stream.Dispose()
        $response.Dispose()
    }

    Write-InstallStatus 'verify' 80 'Проверка целостности архива...'
    $client = New-Object Net.WebClient
    try {
        $checksum = $client.DownloadString($hashUrl)
    } finally {
        $client.Dispose()
    }
    $match = [regex]::Match($checksum, '(?i)\b[a-f0-9]{64}\b')
    if (-not $match.Success) { throw 'Не удалось прочитать контрольную сумму FFmpeg.' }
    $expected = $match.Value.ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw 'Контрольная сумма FFmpeg не совпадает. Архив не установлен.' }

    Write-InstallStatus 'extract' 88 'Распаковка FFmpeg...'
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
            $entry = $zip.Entries | Where-Object { $_.FullName -match ('(?i)(^|/)bin/' + [regex]::Escape($name) + '$') } | Select-Object -First 1
            if (-not $entry) { throw "Файл $name не найден в официальном архиве." }
            $tempExe = Join-Path $Destination ($name + '.downloading')
            $finalExe = Join-Path $Destination $name
            if (Test-Path -LiteralPath $tempExe) { Remove-Item -LiteralPath $tempExe -Force }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tempExe)
            Move-Item -LiteralPath $tempExe -Destination $finalExe -Force
        }
    } finally {
        $zip.Dispose()
    }

    Write-InstallStatus 'done' 100 'FFmpeg установлен. Можно конвертировать видео.'
    exit 0
} catch {
    $message = $_.Exception.Message -replace '[\r\n|]', ' '
    Write-InstallStatus 'error' 0 ("Ошибка установки: " + $message)
    exit 1
} finally {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
}
