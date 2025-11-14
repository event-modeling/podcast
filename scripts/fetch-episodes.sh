#!/bin/bash

# Configuration
CHANNEL_URL="https://www.youtube.com/channel/UCPXhKM1nRIFwTIxhpntSh4A/videos"
OUTPUT_DIR="content/episodes"
AUDIO_DIR="static/audio"
CACHE_DIR="$HOME/.cache/event-modeling-podcast"
CACHED_EPISODES_DIR="$CACHE_DIR/episodes"
SKIP_FETCH_IDS=false

# check if "refresh" or "skip-ids" are passed as arguments
for arg in "$@"; do
    if [ "$arg" == "refresh" ]; then
        echo "Refreshing episodes..."
        rm -rf "$CACHE_DIR"
    elif [ "$arg" == "skip-ids" ]; then
        echo "Skipping ID fetching..."
        SKIP_FETCH_IDS=true
    fi
done


echo "Starting script with:"
echo "Channel URL: $CHANNEL_URL"
echo "Output Dir: $OUTPUT_DIR"
echo "Audio Dir: $AUDIO_DIR"
echo "Cache Dir: $CACHE_DIR"
echo "Skip Fetch IDs: $SKIP_FETCH_IDS"

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
    video_url="https://www.youtube.com/watch?v=$video_id"
    
    echo "Fetching episode $video_id..."
    echo "Episode dir: $episode_dir"

    if [ ! -d "$episode_dir" ]; then
        # Create episode directory
        mkdir -p "$episode_dir"
    fi

    metadata_complete=true
    for required in title date description audio.mp3 duration filesize; do
        if [ ! -f "$episode_dir/$required" ]; then
            metadata_complete=false
            break
        fi
    done

    if [ "$metadata_complete" = true ]; then
        echo "Cache already complete for $video_id, skipping fetch."
        return
    fi
        
    # Get video metadata and save to separate files
    if [ ! -f "$episode_dir/title" ]; then 
        echo "Getting title for episode $video_url"
        yt-dlp --print "%(title)s" "$video_url" > "$episode_dir/title"
    fi
    if [ ! -f "$episode_dir/date" ]; then
        echo "Getting upload date for episode $video_url"
        yt-dlp --print "%(upload_date)s" "$video_url" > "$episode_dir/date"
    fi
    if [ ! -f "$episode_dir/description" ]; then
        echo "Getting description for episode $video_url"
        yt-dlp --print "%(description)s" "$video_url" > "$episode_dir/description"
        echo "got description for episode $video_url"
        cat "$episode_dir/description"
    fi

    # Grab cached title for better prompts
    episode_title=$(head -n 1 "$episode_dir/title" | tr -d '\r')

    # Prompt user for an MP3 file if it doesn't exist
    if [ ! -f "$episode_dir/audio.mp3" ]; then
        echo "Selecting local audio for episode \"$episode_title\""
        selection_tmp=$(mktemp)
        current_path="$HOME/"

        while true; do
            dialog --title "Select MP3 for: $episode_title" \
                --fselect "$current_path" 16 60 2> "$selection_tmp"
            dialog_status=$?

            if [ $dialog_status -ne 0 ]; then
                echo "Selection cancelled for $video_id. Skipping audio."
                break
            fi

            selected_file=$(tr -d '\r\n' < "$selection_tmp")
            if [ -d "$selected_file" ]; then
                resolved_dir=$(readlink -f "$selected_file")
                if [ -n "$resolved_dir" ]; then
                    current_path="$resolved_dir/"
                else
                    current_path="$selected_file"
                fi
                continue
            elif [ -f "$selected_file" ]; then
                source_audio="$selected_file"
                extension="${selected_file##*.}"
                shopt -s nocasematch
                if [[ "$extension" == "mp4" ]]; then
                    target_audio="${selected_file%.*}.mp3"
                    if [ ! -f "$target_audio" ]; then
                        echo "Converting $selected_file to MP3..."
                        if ! ffmpeg -y -i "$selected_file" -vn -acodec libmp3lame -ab 128k "$target_audio"; then
                            dialog --title "Conversion failed" --msgbox "ffmpeg could not convert the selected MP4." 6 60
                            shopt -u nocasematch
                            continue
                        fi
                    fi
                    source_audio="$target_audio"
                fi
                shopt -u nocasematch

                echo "Copying $source_audio to $episode_dir/audio.mp3"
                cp "$source_audio" "$episode_dir/audio.mp3"
                break
            else
                dialog --title "Invalid selection" --msgbox "Please select a valid file." 6 50
            fi
        done

        rm -f "$selection_tmp"
    fi
    
    if [ -f "$episode_dir/audio.mp3" ]; then
        # get the duration of the audio file for the itunes:duration tag
        if [ ! -f "$episode_dir/duration" ]; then
            echo "Getting duration from local audio file for $video_url"
            ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
                "$episode_dir/audio.mp3" | awk '{printf "%.0f\n", $1}' > "$episode_dir/duration"
        fi

        # get the file size in bytes for the enclosure length attribute
        if [ ! -f "$episode_dir/filesize" ]; then
            stat --format="%s" "$episode_dir/audio.mp3" > "$episode_dir/filesize"
        fi
    fi

    # Add small delay to be nice to YouTube
    sleep 1
}

if [ "$SKIP_FETCH_IDS" = true ]; then 
    echo "Skipping video list fetch..."
    video_ids=$(cat "$CACHE_DIR/video_ids.txt")
else
    # Use yt-dlp to get video list
    echo "Fetching video list from channel..."
    video_ids=$(yt-dlp --get-id "$CHANNEL_URL")
    echo "$video_ids" > "$CACHE_DIR/video_ids.txt"
fi

# Count videos
video_count=$(echo "$video_ids" | wc -l)
echo "Found $video_count videos"

# ask if the user wants to continue, default to Yes if Enter is pressed
read -r -p "Do you want to continue? (Y/n) " answer
answer=${answer:-Y}
if [[ $answer != [Yy] ]]; then
    echo "User chose not to continue. Exiting..."
    exit 0
fi

# Process all videos
echo "Processing all episodes..."
# Create a temporary file to store video IDs and dates
temp_file=$(mktemp)

# First pass: Collect dates and video IDs
while IFS= read -r video_id; do
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    fetch_and_cache_episode "$video_id"
    
    if [ -d "$episode_dir" ] && [ -f "$episode_dir/audio.mp3" ]; then
        upload_date=$(head -n 1 "$episode_dir/date" | tr -d '\r')
        
        # Only store if we have a valid date (YYYYMMDD format)
        if [[ $upload_date =~ ^[0-9]{8}$ ]]; then
            echo "$upload_date|$video_id" >> "$temp_file"
        fi
    fi
done <<< "$video_ids"

# remove existing episodes
rm -f "$OUTPUT_DIR"/*

# Sort episodes by date (oldest first) and process them
count=1
sort "$temp_file" | while IFS='|' read -r upload_date video_id; do
    # Skip empty lines
    if [ -z "$upload_date" ]; then
        continue
    fi
    
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    formatted_date=$(echo "$upload_date" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
    
    # Look up metadata from cache
    title=$(head -n 1 "$episode_dir/title" | tr -d '\r')
    description=$(cat "$episode_dir/description")
    duration=$(head -n 1 "$episode_dir/duration" | tr -d '\r')
    filesize=$(head -n 1 "$episode_dir/filesize" | tr -d '\r')
    
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
duration: "$duration"
length: "$filesize"
---

### Show Notes

$description

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