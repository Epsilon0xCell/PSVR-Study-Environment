#!/bin/bash

# Specify input and output files
# These names are defaults, not fixed paths. The script used to work
# only when run from the folder holding vr.mp4 and non360.mp4, which
# made a missing file and a wrong folder look like the same error.
# Positional arguments override each name in order:
#   ./study-generate.sh [background.mp4] [overlay.mp4] [output.mp4]
# and --help prints that without needing ffmpeg installed.
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: ./study-generate.sh [background.mp4] [overlay.mp4] [output.mp4]"
    echo "Defaults: vr.mp4, non360.mp4, output.mp4, read from the current folder."
    echo "The overlay is placed in the center of the 360 background video."
    exit 0
fi
if [ $# -gt 3 ]; then
    echo "Error: expected at most three arguments (background, overlay, output)" >&2
    exit 1
fi
INPUT_VIDEO="${1:-vr.mp4}"         # 360 VR video
OVERLAY_VIDEO="${2:-non360.mp4}"   # non-360 video shown in the center of the 360 video
OUTPUT_VIDEO="${3:-output.mp4}"    # 360 VR video with the overlay added in the center

# The script needs ffmpeg and ffprobe
# This check runs before the file check, so on a machine without
# ffmpeg the tool error is what I see even if the inputs are also
# missing. One problem at a time, in this order.
for tool in ffmpeg ffprobe; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "Error: $tool is not installed or not on PATH"
        exit 1
    fi
done

# The output must not be one of the inputs. ffmpeg opens the output
# for writing while it is still reading the inputs, so naming an
# input as the output would destroy that input mid run.
if [ "$OUTPUT_VIDEO" = "$INPUT_VIDEO" ] || [ "$OUTPUT_VIDEO" = "$OVERLAY_VIDEO" ]; then
    echo "Error: output file $OUTPUT_VIDEO is also an input file"
    exit 1
fi

# The input files must exist before anything else runs
for file in "$INPUT_VIDEO" "$OVERLAY_VIDEO"; do
    if [ ! -f "$file" ]; then
        echo "Error: input file $file not found (run this script from the folder containing it)"
        exit 1
    fi
done

# Check the integrity of the input files
# Two costs I accept here. -count_frames makes ffprobe walk the whole
# file, so this check takes real time on a long background video, and
# nothing redirects its output, so a full stream dump lands in the
# terminal on every run. What it proves is narrow too: ffprobe could
# read the file. A file can pass this and still fail in the encode.
if ! ffprobe -v error -i "$INPUT_VIDEO" -show_format -show_streams -count_frames -pretty -hide_banner; then
    echo "Error: input file $INPUT_VIDEO is corrupted"
    exit 1
fi

if ! ffprobe -v error -i "$OVERLAY_VIDEO" -show_format -show_streams -count_frames -pretty -hide_banner; then
    echo "Error: input file $OVERLAY_VIDEO is corrupted"
    exit 1
fi

# Specify output encoding parameters
# These are fixed, not probed from the input. Whatever the source
# files are, the output comes out at this bitrate, this frame rate,
# and baseline profile level 40, because that is the shape I wanted
# for playback on the headset.
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
# Notes on this one command, because it is the whole script:
# - Each -stream_loop sits in front of the -i it belongs to. Moving
#   one past its -i would loop the wrong input or nothing at all.
# - The audio map is 0:a?, background only, and the ? means a silent
#   background does not fail the run. The overlay clip's own audio is
#   never mapped, so nothing from non360.mp4 is heard in the output.
# - The scale to 1920x1080 happens after the overlay, not before, so
#   the 640x360 in the filter is measured against the source size of
#   vr.mp4, whatever that is, not against the final frame.
# - -y overwrites an existing output.mp4 without asking, so a rerun
#   destroys the previous result whether it was better or not.
if ! ffmpeg -stream_loop 2 -i "$INPUT_VIDEO" -stream_loop 3 -i "$OVERLAY_VIDEO" -filter_complex "[1:v]scale=w=640:h=360[v1];[0:v][v1]overlay=(W-w)/2:(H-h)/2[v];[v]scale=w=1920:h=1080,format=yuv420p,setsar=1[v_scaled]" -map "[v_scaled]" -map 0:a? -c:v "$VIDEO_CODEC" -b:v "$VIDEO_BITRATE" -r "$VIDEO_FRAMERATE" -c:a copy -profile:v "$VIDEO_PROFILE" -level "$VIDEO_LEVEL" -y "$OUTPUT_VIDEO"; then
    echo "Error: ffmpeg failed to create $OUTPUT_VIDEO"
    exit 1
fi

# There is no set -e in this script. Every step above guards itself
# with an if or an exit, so this line means the ffmpeg check passed,
# not just that the script reached the end of the file.
echo "Done: $OUTPUT_VIDEO created"
