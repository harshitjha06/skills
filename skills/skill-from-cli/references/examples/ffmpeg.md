---
name: ffmpeg
description: >-
  Audio and video processing with ffmpeg. Use when converting media formats,
  extracting audio, trimming/cutting video, adjusting quality, creating
  thumbnails, merging files, adding subtitles, streaming, recording, applying
  filters, or any audio/video manipulation. Also covers ffprobe for media
  inspection.
---

# ffmpeg

## Quick start

```bash
# Convert format
ffmpeg -i input.mov output.mp4
# Extract audio
ffmpeg -i video.mp4 -vn -acodec copy audio.aac
# Trim video (start at 1:30, duration 30s)
ffmpeg -ss 00:01:30 -i input.mp4 -t 30 -c copy trimmed.mp4
# Inspect a file
ffprobe -v quiet -print_format json -show_format -show_streams input.mp4
```

## Core patterns

### Format conversion

```bash
# Video format conversion
ffmpeg -i input.avi output.mp4
ffmpeg -i input.mkv -c:v libx264 -c:a aac output.mp4
# Audio conversion
ffmpeg -i input.wav output.mp3
ffmpeg -i input.flac -b:a 320k output.mp3
# Lossless copy (change container only)
ffmpeg -i input.mkv -c copy output.mp4
```

### Trim and cut

```bash
# Cut from timestamp (fast seek with -ss before -i)
ffmpeg -ss 00:01:30 -i input.mp4 -t 00:00:30 -c copy clip.mp4
# Cut to timestamp
ffmpeg -ss 00:01:30 -i input.mp4 -to 00:02:00 -c copy clip.mp4
# Frame-accurate cut (slower, -ss after -i)
ffmpeg -i input.mp4 -ss 00:01:30 -t 30 -c:v libx264 -c:a aac clip.mp4
```

### Audio extraction and manipulation

```bash
# Extract audio (keep original codec)
ffmpeg -i video.mp4 -vn -acodec copy audio.aac
# Extract and convert to mp3
ffmpeg -i video.mp4 -vn -b:a 192k audio.mp3
# Strip audio from video
ffmpeg -i input.mp4 -an -c:v copy silent.mp4
# Replace audio track
ffmpeg -i video.mp4 -i new_audio.mp3 -c:v copy -map 0:v -map 1:a output.mp4
# Adjust volume
ffmpeg -i input.mp4 -filter:a "volume=1.5" louder.mp4
```

### Quality control

```bash
# CRF encoding (lower = better quality, 18 ≈ visually lossless)
ffmpeg -i input.mp4 -c:v libx264 -crf 18 -preset slow output.mp4
# Presets: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
ffmpeg -i input.mp4 -c:v libx264 -crf 23 -preset fast output.mp4
# H.265 (smaller files, slower encoding)
ffmpeg -i input.mp4 -c:v libx265 -crf 28 output.mp4
# Constant bitrate
ffmpeg -i input.mp4 -c:v libx264 -b:v 5M output.mp4
```

### Resize and scale

```bash
# Scale to specific resolution
ffmpeg -i input.mp4 -vf "scale=1280:720" output.mp4
# Scale maintaining aspect ratio (-1 = auto)
ffmpeg -i input.mp4 -vf "scale=1280:-1" output.mp4
# Scale to fit within bounds
ffmpeg -i input.mp4 -vf "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease" output.mp4
```

### Images

```bash
# Extract single frame
ffmpeg -ss 00:00:05 -i input.mp4 -frames:v 1 thumbnail.jpg
# Extract frames at interval (1 frame per second)
ffmpeg -i input.mp4 -vf "fps=1" frames/frame_%04d.png
# Create video from images
ffmpeg -framerate 24 -i frames/frame_%04d.png -c:v libx264 -pix_fmt yuv420p output.mp4
# Create GIF
ffmpeg -ss 5 -t 3 -i input.mp4 -vf "fps=10,scale=480:-1" output.gif
```

### Merge and concatenate

```bash
# Concatenate files (same codec) — create filelist.txt:
#   file 'part1.mp4'
#   file 'part2.mp4'
ffmpeg -f concat -safe 0 -i filelist.txt -c copy merged.mp4
# Overlay audio on video
ffmpeg -i video.mp4 -i audio.mp3 -c:v copy -c:a aac -shortest output.mp4
# Side by side
ffmpeg -i left.mp4 -i right.mp4 -filter_complex "[0:v][1:v]hstack=inputs=2" sidebyside.mp4
```

### Filters

```bash
# Remove watermark (interpolate from surroundings)
ffmpeg -i input.mp4 -vf "delogo=x=100:y=50:w=200:h=30" clean.mp4
# Crop
ffmpeg -i input.mp4 -vf "crop=640:480:100:50" cropped.mp4
# Rotate
ffmpeg -i input.mp4 -vf "transpose=1" rotated.mp4  # 90° clockwise
# Speed up / slow down
ffmpeg -i input.mp4 -vf "setpts=0.5*PTS" -af "atempo=2.0" fast.mp4
# Add subtitles
ffmpeg -i input.mp4 -vf "subtitles=subs.srt" output.mp4
```

## Inspection with ffprobe

```bash
# Full JSON info
ffprobe -v quiet -print_format json -show_format -show_streams input.mp4
# Duration only
ffprobe -v quiet -show_entries format=duration -of csv=p=0 input.mp4
# Resolution
ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 input.mp4
# Codec info
ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 input.mp4
```

## Example: Prepare video for web

```bash
# H.264 + AAC, web-optimized (faststart moves metadata to front)
ffmpeg -i raw_footage.mov \
  -c:v libx264 -crf 23 -preset slow \
  -c:a aac -b:a 128k \
  -movflags +faststart \
  -vf "scale='min(1920,iw)':-2" \
  web_video.mp4
```

## Example: Extract and normalize audio

```bash
# Analyze loudness
ffmpeg -i input.mp4 -af "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | tail -20
# Apply normalization
ffmpeg -i input.mp4 -af "loudnorm=I=-16:TP=-1.5:LRA=11" -c:v copy normalized.mp4
```

## Gotchas

- **`-ss` position matters.** Before `-i` = fast seek (keyframe-based, may be imprecise).
  After `-i` = frame-accurate but slower. For cutting with `-c copy`, put `-ss` before `-i`.
- **`-c copy` limitations.** Stream copy can't apply filters, change resolution, or
  cut at non-keyframes precisely. Use re-encoding when precision matters.
- **Pixel format.** Some players reject `yuv444p`. Add `-pix_fmt yuv420p` for compatibility.
- **Overwrite.** ffmpeg prompts before overwriting. Use `-y` to auto-overwrite, `-n` to never overwrite.
- **Stream mapping.** Multi-stream files need explicit `-map` to select which streams to include.
- **Filter chain syntax.** Simple: `-vf "filter1,filter2"`. Complex (multi-input): `-filter_complex "[0:v][1:v]..."`.
- **`-2` in scale.** Use `-2` instead of `-1` to ensure dimensions are divisible by 2 (required by many codecs).
