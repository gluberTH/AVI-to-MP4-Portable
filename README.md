# AVI to MP4 — Portable Converter for Windows

A simple, portable **AVI → MP4 video converter** with a graphical interface. No Python, installer, or command-line experience required: extract the files, double-click `Convert.bat`, and convert your videos.

Built with **Windows PowerShell + Windows Forms** and powered by **FFmpeg**. The interface is currently in **Russian**.

Watch full video how it works: https://youtu.be/9JjOafuylc4

## Features

- **Batch conversion:** add multiple AVI files and process them one after another.
- **Drag and drop:** drop AVI files directly into the application window.
- **MP4 output:** H.264 video (`libx264`) and AAC audio for broad compatibility.
- **Quality presets:** Balanced, High Quality, or Smaller File.
- **Speed presets:** Normal (better compression) or Faster.
- **Progress indicator:** see the progress of the current video when its duration can be detected.
- **Flexible output:** save MP4 files next to their AVI originals or choose another folder.
- **No overwriting:** existing MP4 files are kept; new files get names such as `video (1).mp4`.
- **Safe originals:** your source AVI files are never deleted.
- **Stop button:** cancel the current conversion; incomplete MP4 output is removed.
- **Error logs:** conversion errors are recorded in `logs/`.
- **Offline after setup:** FFmpeg is only downloaded once, if it is not already available.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (included with those Windows versions)
- Internet access **on first use only**, if FFmpeg is not already installed
- Enough free disk space for the resulting MP4 files

No Python installation is necessary.

## Quick start

1. Download the project files (or a ZIP archive from the repository) and **extract the entire folder**.
2. Double-click **`Convert.bat`**.
3. Click **“+ Добавить AVI”** (*Add AVI*) or drag AVI files into the window.
4. Choose the output folder, quality, and speed, if needed.
5. Click **“Конвертировать”** (*Convert*).
6. Find your MP4 files next to the original AVI files (default), or in your chosen output folder.

If FFmpeg is missing, the application offers to download it automatically before conversion. The download is approximately **110 MB** and is stored locally in `bin/` for future use.

### Main controls (Russian → English)

| Interface text | Meaning |
| --- | --- |
| `+ Добавить AVI` | Add AVI files |
| `Убрать` / `Очистить` | Remove selected / Clear list |
| `Скачать FFmpeg` | Download FFmpeg |
| `Рядом с исходным AVI` | Save next to the source AVI |
| `Обзор...` | Choose an output folder |
| `Качество` / `Скорость` | Quality / Speed |
| `Конвертировать` / `Стоп` | Convert / Stop |

## How FFmpeg is installed

This repository **does not need to contain FFmpeg binaries**. If `bin/ffmpeg.exe` is absent and FFmpeg is not on your system `PATH`, the application can download the Windows *release essentials* build from:

<https://www.gyan.dev/ffmpeg/builds/>

The setup script downloads the archive and its published SHA-256 checksum, verifies the archive, and extracts `ffmpeg.exe` and `ffprobe.exe` into `bin/`.

**Manual alternative:** download a compatible Windows FFmpeg build and place `ffmpeg.exe` and `ffprobe.exe` inside the `bin/` folder. Then launch `Convert.bat` again.

Once FFmpeg is available locally, conversion runs without an internet connection. **Your videos are processed on your own computer**; the application does not upload them to a server.

## Quality and encoding

| Quality setting | Video CRF | General trade-off |
| --- | ---: | --- |
| Balanced (default) | 23 | Recommended starting point |
| High Quality | 18 | Higher quality, usually larger files |
| Smaller File | 28 | Smaller files, reduced quality |

The Normal speed preset uses x264 `medium`; Faster uses `veryfast`. Audio is encoded as AAC at 192 kb/s when the AVI contains an audio track. The converter uses the first video stream and, if present, the first audio stream; subtitle and data streams are not included in the output. Odd frame dimensions are adjusted to even numbers for compatibility.

*Conversion time and output size depend on the source material and your computer. Re-encoding does not improve the original video quality.*

## Project files

```text
AVI-to-MP4-Portable/
├── Convert.bat           # Starts the application
├── AVI-to-MP4.ps1        # GUI and conversion logic
├── Setup-FFmpeg.ps1      # FFmpeg download and checksum verification
├── THIRD_PARTY.txt       # FFmpeg licensing and credits
├── README.md             # This file
├── bin/
│   └── PLACE_FFMPEG_HERE.txt
└── logs/                 # Created/used for conversion error logs
```

`bin/ffmpeg.exe`, `bin/ffprobe.exe`, and runtime logs are **not** required in the GitHub source repository. Avoid committing downloaded binaries or personal video files.

## Troubleshooting

**Nothing happens when I double-click `Convert.bat`.**  
Make sure you extracted *all* project files and kept `Convert.bat` and `AVI-to-MP4.ps1` in the same folder. Windows security software may warn about unsigned BAT/PowerShell scripts; inspect the scripts before running them and use only a source you trust.

**FFmpeg cannot be downloaded.**  
Check your internet connection, or install `ffmpeg.exe` and `ffprobe.exe` manually in `bin/` as described above.

**Conversion fails for a particular file.**  
Check the `logs/` folder for an `error-*.txt` file. Damaged AVI files and rare or unsupported source codecs may fail. You can open an issue with the error message (remove any private file paths first).

**Where did my MP4 go?**  
By default, it is saved in the same folder as the source AVI. If you selected another location, check that folder. Existing MP4 files are never overwritten.

## Notes and third-party licensing

The converter scripts call FFmpeg as a separate program. **FFmpeg is a separate third-party project**, with its own licensing terms; the downloadable gyan.dev builds may be distributed under GPLv3. If you redistribute FFmpeg binaries (for example, by uploading a preconfigured `bin/` folder or packaged release), review the applicable license obligations first.

See [`THIRD_PARTY.txt`](THIRD_PARTY.txt) and <https://ffmpeg.org/legal.html>.

---

## 🇷🇺 Краткая инструкция на русском

**AVI to MP4 Portable Converter** — портативный конвертер AVI в MP4 с графическим интерфейсом для Windows 10/11. Python и установка программы не нужны.

1. Скачайте файлы проекта и распакуйте всю папку.
2. Запустите **`Convert.bat`** двойным щелчком.
3. Добавьте один или несколько файлов AVI кнопкой **«+ Добавить AVI»** или перетащите их в окно.
4. Выберите качество, скорость и при необходимости папку сохранения.
5. Нажмите **«Конвертировать»**. Готовые MP4 по умолчанию будут рядом с AVI.

Если FFmpeg отсутствует, приложение предложит скачать его (примерно 110 МБ). После этого конвертация работает **без интернета**. AVI не удаляются, существующие MP4 не перезаписываются; при ошибке информация сохраняется в папке `logs/`.

**Важно для публикации на GitHub:** загружайте исходные `.ps1`, `.bat`, `README.md`, `THIRD_PARTY.txt` и файл-заглушку из `bin/`, но не сами `ffmpeg.exe`, `ffprobe.exe`, личные видео или логи ошибок.
