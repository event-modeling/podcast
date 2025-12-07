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

# Function to fetch episode metadata
fetch_episode_metadata() {
    video_id="$1"
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    video_url="https://www.youtube.com/watch?v=$video_id"

    if [ ! -d "$episode_dir" ]; then
        mkdir -p "$episode_dir"
    fi

    # Get video metadata if not already cached
    if [ ! -f "$episode_dir/title" ] || [ ! -s "$episode_dir/title" ]; then 
        echo "Getting title for $video_id"
        yt-dlp --print "%(title)s" "$video_url" > "$episode_dir/title" 2>/dev/null
    fi
    if [ ! -f "$episode_dir/date" ]; then
        echo "Getting upload date for $video_id"
        yt-dlp --print "%(upload_date)s" "$video_url" > "$episode_dir/date" 2>/dev/null
    fi
    if [ ! -f "$episode_dir/description" ]; then
        echo "Getting description for $video_id"
        yt-dlp --print "%(description)s" "$video_url" > "$episode_dir/description" 2>/dev/null
    fi
    
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

# Step 1: Fetch all metadata first
echo "Fetching episode metadata..."
while IFS= read -r video_id; do
    fetch_episode_metadata "$video_id"
done <<< "$video_ids"

# Step 2: Build sorted list with dates and create tab-delimited mapping file
# Format: episode_number<TAB>video_id<TAB>title
echo "Building episode mapping..."
episode_mapping=$(mktemp)
temp_dates=$(mktemp)

# Collect all video IDs with their dates
while IFS= read -r video_id; do
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    if [ -f "$episode_dir/date" ]; then
        upload_date=$(head -n 1 "$episode_dir/date" | tr -d '\r')
        if [[ $upload_date =~ ^[0-9]{8}$ ]]; then
            title=$(head -n 1 "$episode_dir/title" | tr -d '\r' | sed 's/\t/ /g')
            if [ -z "$title" ]; then
                title="Video $video_id"
            fi
            echo "$upload_date|$video_id|$title" >> "$temp_dates"
        fi
    fi
done <<< "$video_ids"

# Sort by date (oldest first) and assign episode numbers
count=1
sort "$temp_dates" | while IFS='|' read -r upload_date video_id title; do
    echo -e "$count\t$video_id\t$title" >> "$episode_mapping"
    count=$((count + 1))
done

# Step 3: Process each episode using the mapping
echo "Processing episodes..."
while IFS=$'\t' read -r episode_num video_id episode_title; do
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    video_url="https://www.youtube.com/watch?v=$video_id"
    
    echo "Processing episode $episode_num: $episode_title"
    
    # Check if MP3 already exists in static/audio
    if [ -f "$AUDIO_DIR/episode-$episode_num.mp3" ]; then
        echo "Found existing MP3 in static/audio: episode-$episode_num.mp3"
        echo "$AUDIO_DIR/episode-$episode_num.mp3" > "$episode_dir/audio_source.txt"
    else
        # Prompt for MP3 or MP4
        echo "Selecting local audio for episode \"$episode_title\""
        selection_tmp=$(mktemp)
        
        # Load cached directory if it exists, otherwise default to HOME
        cached_dir_file="$CACHE_DIR/last_directory.txt"
        if [ -f "$cached_dir_file" ]; then
            current_path=$(cat "$cached_dir_file" | tr -d '\r\n')
            # Verify the cached directory still exists
            if [ ! -d "$current_path" ]; then
                current_path="$HOME/"
            else
                # Ensure it ends with /
                if [[ "$current_path" != */ ]]; then
                    current_path="$current_path/"
                fi
            fi
        else
            current_path="$HOME/"
        fi

        while true; do
            dialog --title "Select MP3 or MP4 for: $episode_title" \
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
                # Cache the navigated directory
                if [ -d "$current_path" ]; then
                    echo "$current_path" > "$cached_dir_file"
                fi
                continue
            elif [ -f "$selected_file" ]; then
                source_audio="$selected_file"
                extension="${selected_file##*.}"
                shopt -s nocasematch
                if [[ "$extension" == "mp4" ]]; then
                    target_audio="${selected_file%.*}.mp3"
                    # Get source duration for verification
                    source_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$selected_file" 2>/dev/null | head -n 1)
                    needs_conversion=true
                    
                    # Check if converted file exists and is complete
                    if [ -f "$target_audio" ]; then
                        existing_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$target_audio" 2>/dev/null | head -n 1)
                        if [ -n "$source_duration" ] && [ -n "$existing_duration" ]; then
                            duration_diff=$(echo "$source_duration - $existing_duration" | bc | awk '{if ($1 < 0) print -$1; else print $1}')
                            # Allow 2 second tolerance for rounding
                            if (( $(echo "$duration_diff <= 2" | bc -l) )); then
                                echo "Using existing converted MP3 (duration matches source)"
                                needs_conversion=false
                            else
                                echo "Existing MP3 is incomplete (${existing_duration}s vs ${source_duration}s), re-converting..."
                                rm -f "$target_audio"
                            fi
                        fi
                    fi
                    if [ "$needs_conversion" = true ]; then
                        echo "Converting $selected_file to MP3..."
                        echo "This may take several minutes. Please wait..."
                        timeout 7200 ffmpeg -y -i "$selected_file" -vn -acodec libmp3lame -ab 128k "$target_audio" < /dev/null > /tmp/ffmpeg_convert.log 2>&1
                        ffmpeg_exit=$?
                        if [ $ffmpeg_exit -eq 124 ]; then
                            echo "Warning: ffmpeg conversion timed out after 2 hours"
                            ffmpeg_exit=1
                        fi
                        if [ $ffmpeg_exit -ne 0 ]; then
                            dialog --title "Conversion failed" --msgbox "ffmpeg could not convert the selected MP4. Exit code: $ffmpeg_exit\n\nCheck /tmp/ffmpeg_convert.log for details." 10 70
                            shopt -u nocasematch
                            continue
                        fi
                        # Verify the output duration matches the source
                        if [ -n "$source_duration" ] && [ -f "$target_audio" ]; then
                            output_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$target_audio" 2>/dev/null | head -n 1)
                            if [ -n "$output_duration" ] && [ -n "$source_duration" ]; then
                                duration_diff=$(echo "$source_duration - $output_duration" | bc | awk '{if ($1 < 0) print -$1; else print $1}')
                                if (( $(echo "$duration_diff > 2" | bc -l) )); then
                                    echo "Warning: Output duration (${output_duration}s) differs significantly from source (${source_duration}s)"
                                    dialog --title "Conversion warning" --msgbox "The converted MP3 duration (${output_duration}s) differs from the source MP4 (${source_duration}s). The conversion may be incomplete." 8 70
                                fi
                            fi
                        fi
                    fi
                    source_audio="$target_audio"
                fi
                shopt -u nocasematch

                # Store the source audio path
                echo "$source_audio" > "$episode_dir/audio_source.txt"
                
                # Cache the directory of the selected file for next time
                selected_dir=$(dirname "$selected_file")
                if [ -d "$selected_dir" ]; then
                    echo "$selected_dir" > "$cached_dir_file"
                fi
                
                break
            else
                dialog --title "Invalid selection" --msgbox "Please select a valid file." 6 50
            fi
        done

        rm -f "$selection_tmp"
    fi
    
    # Get duration and filesize from audio source
    audio_source=""
    if [ -f "$episode_dir/audio_source.txt" ]; then
        audio_source=$(cat "$episode_dir/audio_source.txt" | tr -d '\r\n')
    fi
    
    if [ -n "$audio_source" ] && [ -f "$audio_source" ]; then
        # Get duration if not cached
        if [ ! -f "$episode_dir/duration" ]; then
            echo "Getting duration from audio file for $video_id"
            ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
                "$audio_source" | awk '{printf "%.0f\n", $1}' > "$episode_dir/duration"
        fi

        # Get file size if not cached
        if [ ! -f "$episode_dir/filesize" ]; then
            stat --format="%s" "$audio_source" > "$episode_dir/filesize"
        fi
    fi
done < "$episode_mapping"

# Step 4: Remove existing episodes and create new markdown files
rm -f "$OUTPUT_DIR"/*

# Step 5: Generate markdown files using the mapping
while IFS=$'\t' read -r episode_num video_id episode_title; do
    episode_dir="$CACHED_EPISODES_DIR/$video_id"
    
    # Get audio source path
    audio_source=""
    if [ -f "$episode_dir/audio_source.txt" ]; then
        audio_source=$(cat "$episode_dir/audio_source.txt" | tr -d '\r\n')
    fi
    
    if [ -n "$audio_source" ] && [ -f "$audio_source" ]; then
        upload_date=$(head -n 1 "$episode_dir/date" | tr -d '\r')
        formatted_date=$(echo "$upload_date" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
        description=$(cat "$episode_dir/description")
        duration=$(head -n 1 "$episode_dir/duration" | tr -d '\r')
        filesize=$(head -n 1 "$episode_dir/filesize" | tr -d '\r')
        
        echo "Creating episode $episode_num: [$formatted_date] $episode_title"
        
        # Create markdown file
        cat > "$OUTPUT_DIR/episode-$episode_num.md" << EOF
---
title: "$episode_title"
date: $formatted_date
description: "$description"
audio: "/audio/episode-$episode_num.mp3"
video: "$video_id"
duration: "$duration"
length: "$filesize"
---

### Show Notes

$description

EOF
        
        # Copy audio file to static/audio if it's not already there
        if [ "$audio_source" != "$AUDIO_DIR/episode-$episode_num.mp3" ]; then
            cp "$audio_source" "$AUDIO_DIR/episode-$episode_num.mp3"
        fi
    else
        echo "Warning: Missing audio file for episode $episode_num: $episode_title"
    fi
done < "$episode_mapping"

# Clean up temp files
rm -f "$episode_mapping"
rm -f "$temp_dates"

echo "Script completed!"
