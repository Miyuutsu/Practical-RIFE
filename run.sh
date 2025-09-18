#!/bin/bash

# Usage: ./run.sh /path/to/video.mkv multiplier
# Example: ./run.sh /home/miyuu/videos/video1.mkv 3

file="$1"
multiplier="$2"
[ ! "$multiplier" ] && multiplier="2"
filename=$(basename "$file")

# Create output directory
mkdir -p output

# Remove any existing train_log
[ -f train_log ] && rm train_log

# Activate virtual environment
source venv/bin/activate

# Get original FPS using ffprobe
filefps=$(ffprobe -v 0 -select_streams v:0 -show_entries stream=r_frame_rate \
          -of default=noprint_wrappers=1:nokey=1 "$file")
# Convert fraction to decimal
filefps=$(echo "scale=6; $filefps" | bc -l)
# Round to nearest integer
filefps=$(printf "%.0f" "$filefps")

echo "Detected FPS: $filefps"
interp_fps=$((filefps * multiplier))
# --- Step 1: RIFE interpolation ---
ln -s "v4.25/train_log" "train_log"

python inference_video.py \
    --exp=1 \
    --video="$file" \
    --output="output/${filename%.*}_interp.mkv" \
    --fp16 \
    --ext mkv \
    --fps="$interp_fps" \
    --multi=$multiplier

rm train_log

ln -s "safa/train_log" "train_log"

python inference_video_enhance.py \
    --video="output/${filename%.*}_interp.mkv" \
    --output="output/${filename%.*}_interpsa.mkv" \
    --fp16 --ext mkv --fps $interp_fps

# --- Step 2: Downsample 72 -> 60 fps ---
# Calculate interpolated fps for ffmpeg
final_fps=60
[ "$interp_fps" -lt 60 ] && final_fps=30

ffmpeg -i "output/${filename%.*}_interpsa.mkv" \
  -vf "fps=$final_fps,format=yuv444p" -c:v libx264 -crf 15 \
  -tune animation -preset veryslow \
  "output/${filename%.*}_interpff.mkv"

# --- Step 3: SAFA enhancement ---
python inference_video_enhance.py \
    --video="output/${filename%.*}_interpff.mkv" \
    --output="output/${filename%.*}_enh.mkv" \
    --fp16 --ext mkv --fps $final_fps

rm train_log

# Deactivate virtual environment
deactivate

echo "Done! Final enhanced video: output/${filename%.*}_enh.mkv"
