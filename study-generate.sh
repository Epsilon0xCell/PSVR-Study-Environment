#!/bin/bash

# Specify input and output files
INPUT_VIDEO="vr.mp4"         # 360 VR video
OVERLAY_VIDEO="non360.mp4"   # non-360 video shown in the center of the 360 video
OUTPUT_VIDEO="output.mp4"    # 360 VR video with the overlay added in the center

# The script needs ffmpeg and ffprobe
for tool in ffmpeg ffprobe; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "Error: $tool is not installed or not on PATH"
        exit 1
    fi
done

# The input files must exist before anything else runs
for file in "$INPUT_VIDEO" "$OVERLAY_VIDEO"; do
    if [ ! -f "$file" ]; then
        echo "Error: input file $file not found (run this script from the folder containing it)"
        exit 1
    fi
done

# Check the integrity of the input files
if ! ffprobe -v error -i "$INPUT_VIDEO" -show_format -show_streams -count_frames -pretty -hide_banner; then
    echo "Error: input file $INPUT_VIDEO is corrupted"
    exit 1
fi

if ! ffprobe -v error -i "$OVERLAY_VIDEO" -show_format -show_streams -count_frames -pretty -hide_banner; then
    echo "Error: input file $OVERLAY_VIDEO is corrupted"
    exit 1
fi

# Specify output encoding parameters
VIDEO_CODEC="libx264"          # video codec
VIDEO_BITRATE="4M"             # video bitrate
VIDEO_FRAMERATE="60"           # video frame rate
VIDEO_PROFILE="baseline"       # H.264 profile
VIDEO_LEVEL="40"               # H.264 level

# Set high-medium priority for CPU usage (best effort: raising priority
# needs extra privileges on most systems, so failure here is not fatal)
renice -5 $$ > /dev/null 2>&1 || true

# Add the overlay to the center of the 360 VR video.
# The background is looped twice extra (-stream_loop 2) and the overlay
# three times extra (-stream_loop 3), so the output runs about three
# times as long as the background video. The overlay is scaled to
# 640x360 in the center and the finished video is scaled to 1920x1080.
if ! ffmpeg -stream_loop 2 -i "$INPUT_VIDEO" -stream_loop 3 -i "$OVERLAY_VIDEO" -filter_complex "[1:v]scale=w=640:h=360[v1];[0:v][v1]overlay=(W-w)/2:(H-h)/2[v];[v]scale=w=1920:h=1080,format=yuv420p,setsar=1[v_scaled]" -map "[v_scaled]" -map 0:a? -c:v "$VIDEO_CODEC" -b:v "$VIDEO_BITRATE" -r "$VIDEO_FRAMERATE" -c:a copy -profile:v "$VIDEO_PROFILE" -level "$VIDEO_LEVEL" -y "$OUTPUT_VIDEO"; then
    echo "Error: ffmpeg failed to create $OUTPUT_VIDEO"
    exit 1
fi

echo "Done: $OUTPUT_VIDEO created"
