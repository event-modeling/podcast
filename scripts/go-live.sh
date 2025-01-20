#!/bin/bash

# source dir: 
SOURCE_DIR="public"
# destination dir: 
DEST_DIR="adam@eventmodeling.org:~/podcast.eventmodeling.org"

# copy only changed files using file size comparison, excluding mp3 files
rsync -avz --size-only --delete --backup --backup-dir=podcast-backup-$(date +%Y-%m-%d-%H-%M-%S) --exclude="*.mp3" "$SOURCE_DIR/" "$DEST_DIR/"

# copy the mp3 files
rsync -avz --include="*.mp3" --exclude="*" "$SOURCE_DIR/audio/" "$DEST_DIR/audio/"
