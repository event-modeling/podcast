#!/bin/bash

# Configuration
CHANNEL_URL="https://www.youtube.com/channel/UCPXhKM1nRIFwTIxhpntSh4A/videos"
OUTPUT_DIR="content/episodes"
AUDIO_DIR="static/audio"
CACHE_DIR="$HOME/.cache/event-modeling-podcast"
CACHED_EPISODES_DIR="$CACHE_DIR/episodes"

# check if "refresh" is passed as an argument
if [ "$1" == "refresh" ]; then
    echo "Refreshing episodes..."
    rm -rf "$CACHE_DIR"
fi

echo "Starting script with:"
echo "Channel URL: $CHANNEL_URL"
echo "Output Dir: $OUTPUT_DIR"
echo "Audio Dir: $AUDIO_DIR"
echo "Cache Dir: $CACHE_DIR"

# Check for yt-dlp
if ! command -v yt-dlp &> /dev/null; then
    echo "yt-dlp is required but not installed. Installing dependencies..."
    sudo apt update
    sudo apt install -y python3-pip ffmpeg
    sudo pip3 install --upgrade yt-dlp
else
    echo "yt-dlp is already installed"
fi

# Check for dialog
if ! command -v dialog &> /dev/null; then
    echo "dialog is required but not installed. Installing dependencies..."
    sudo apt update
    sudo apt install -y dialog
fi

# Create directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$AUDIO_DIR"
mkdir -p "$CACHED_EPISODES_DIR"

# Function to fetch and cache episode data
fetch_and_cache_episode() {
    video_id="$1"
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    
    if [ ! -d "$episode_dir" ]; then
        echo "Caching metadata for video $video_id..."
        video_url="https://www.youtube.com/watch?v=$video_id"
        
        # Create episode directory
        mkdir -p "$episode_dir"
        
        # Get video metadata and save to separate files
        yt-dlp --print "%(title)s" "$video_url" > "$episode_dir/title"
        yt-dlp --print "%(upload_date)s" "$video_url" > "$episode_dir/date"
        yt-dlp --print "%(description)s" "$video_url" > "$episode_dir/description"
        
        # Download audio if it doesn't exist
        if [ ! -f "$episode_dir/audio.mp3" ]; then
            echo "Downloading audio for episode $count..."
            yt-dlp -x --audio-format mp3 \
                  --audio-quality 0 \
                  -o "$episode_dir/audio.mp3" \
                  "$video_url"
        fi
        
        # Add small delay to be nice to YouTube
        sleep 1
    else
        echo "Using cached data for video $video_id"
    fi
}

# Use yt-dlp to get video list
if [ ! -f "$CACHE_DIR/video_ids.txt" ]; then
    echo "Fetching video list from channel..."
    video_ids=$(yt-dlp --get-id "$CHANNEL_URL")
    echo "$video_ids" > "$CACHE_DIR/video_ids.txt"
else
    echo "Using cached video list..."
    video_ids=$(cat "$CACHE_DIR/video_ids.txt")
fi

# Count videos
video_count=$(echo "$video_ids" | wc -l)
echo "Found $video_count videos"

# ask if the user wants to continue
echo -n "Do you want to continue? (y/n) "
read answer
if [[ $answer != "y" && $answer != "Y" ]]; then
    echo "User chose not to continue. Exiting..."
    exit 0
fi

# Process all videos
echo "Processing all episodes..."
# Create a temporary file to store episode data
temp_file=$(mktemp)

# First pass: Collect all episode data
while IFS= read -r video_id; do
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    fetch_and_cache_episode "$video_id"
    
    if [ -d "$episode_dir" ] && [ -f "$episode_dir/audio.mp3" ]; then
        title=$(head -n 1 "$episode_dir/title" | tr -d '\r')
        upload_date=$(head -n 1 "$episode_dir/date" | tr -d '\r')
        description=$(head -n 1 "$episode_dir/description" | tr -d '\r')
        
        # Only store if we have a valid date (YYYYMMDD format)
        if [[ $upload_date =~ ^[0-9]{8}$ ]]; then
            echo "$upload_date|$video_id|$title|$description" >> "$temp_file"
        fi
    fi
done <<< "$video_ids"

# remove existing episodes
rm "$OUTPUT_DIR/*"

# Sort episodes by date (oldest first) and process them
count=1
sort "$temp_file" | while IFS='|' read -r upload_date video_id title description; do
    # Skip empty lines
    if [ -z "$upload_date" ]; then
        continue
    fi
    
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    formatted_date=$(echo "$upload_date" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
    
    echo "Processing episode $count: [$formatted_date] $title"
    
    # Only process if audio file exists
    if [ -f "$episode_dir/audio.mp3" ]; then
        # Create markdown file with escaped content
        cat > "$OUTPUT_DIR/episode-$count.md" << EOF
---
title: "$title"
date: $formatted_date
description: "$description"
audio: "/audio/episode-$count.mp3"
video: "$video_id"
---

### Show Notes

$description

### Links Mentioned

EOF
        
        # Copy audio file
        cp "$episode_dir/audio.mp3" "$AUDIO_DIR/episode-$count.mp3"
        count=$((count + 1))
    else
        echo "Warning: Missing audio file for $title"
    fi
done

# Clean up temp file
rm "$temp_file"

echo "Script completed!" 