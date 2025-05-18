#!/bin/bash

# Your Configuration
HOST="https://cdn.rainnny.club"
API_KEY="X"
SOUND_VOLUME=20 # 0-100

# Function to upload a file
upload_file() {
    local file_path="$1"
    echo "Uploading file: $file_path"
    result=$(curl -s -X POST "$HOST/api/upload" -F "x-clippy-upload-token=$API_KEY" -F "x-clippy-compress-percentage=100" -F "sharex=@$file_path")

    if [ $? -eq 0 ]; then
        path=$(echo "$result" | jq -r '.path')
        url=$(echo "$result" | jq -r '.url')

        if [ -n "$path" ] && [ -n "$url" ]; then
            wl-copy "$url/$path"
            notify-send "File Uploaded" "$url/$path"
            echo "File uploaded successfully: $url/$path"
        else
            echo "Failed to extract path and URL from the JSON response."
            return 1
        fi
    else
        echo "Failed to upload file."
        return 1
    fi
}

# Function to upload a folder as individual files
upload_folder_individual() {
    local folder_path="$1"
    echo "Uploading folder contents individually: $folder_path"

    # Find all files in the directory and its subdirectories
    find "$folder_path" -type f -print0 | while IFS= read -r -d '' file; do
        upload_file "$file"
    done
}

# Function to upload a folder as a compressed zip
upload_folder_compressed() {
    local folder_path="$1"
    echo "Uploading folder contents as compressed zip: $folder_path"

    # Create a temporary directory for the zip file
    temp_dir=$(mktemp -d)
    zip_file="$temp_dir/upload.zip"

    # Create zip file of the folder contents
    (cd "$folder_path" && zip -r "$zip_file" .)

    if [ $? -eq 0 ]; then
        upload_file "$zip_file"
        rm -rf "$temp_dir"
    else
        echo "Failed to create zip file."
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to capture a screenshot and save it with a random name
capture_screenshot() {
    # Generate a unique filename for the screenshot
    random_filename=$(date +%s%N | sha256sum | head -c 10)

    # Use flameshot in GUI mode to save the screenshot as a PNG file with the random name
    QT_QPA_PLATFORM=xcb flameshot gui -p /tmp/"$random_filename".png

    if [ ! -f "/tmp/$random_filename.png" ]; then
        echo "Failed to capture the screenshot."
        return 1
    fi

    # Upload the screenshot
    upload_file "/tmp/$random_filename.png"

    # Clean up
    rm -f "/tmp/$random_filename.png"
}

# Parse command line arguments
compress_folder=false
target_path=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --compress|-c)
            compress_folder=true
            shift
            ;;
        *)
            target_path="$1"
            shift
            ;;
    esac
done

# Simple function to play a sound
play_sound() {
    [[ -f "$1" ]] && pw-cat -p --volume $SOUND_VOLUME "$1" &> /dev/null &
}

# Sound file paths
CAPTURE_SOUND="/tmp/CaptureSound.wav"
COMPLETE_SOUND="/tmp/TaskCompletedSound.wav"

# Simple function to download sounds if needed
get_sound() {
    local file="$1"
    local url="$2"

    # Download if file doesn't exist or is too small
    if [[ ! -f "$file" ]] || [[ $(stat -c%s "$file") -lt 1000 ]]; then
        curl -L -s -o "$file" "$url" || {
            echo "Failed to download sound" >&2
            return 1
        }
    fi
}

# Get sound files
get_sound "$CAPTURE_SOUND" "https://cdn.rainnny.club/Capture.wav"
get_sound "$COMPLETE_SOUND" "https://cdn.rainnny.club/PCapture.wav"

# Main script logic
if [ -z "$target_path" ]; then
    # No arguments provided, take a screenshot
    play_sound "$CAPTURE_SOUND"
    capture_screenshot
    play_sound "$COMPLETE_SOUND"
else
    # Check if the argument is a file or directory
    if [ -f "$target_path" ]; then
        upload_file "$target_path"
        play_sound "$COMPLETE_SOUND"
    elif [ -d "$target_path" ]; then
        if [ "$compress_folder" = true ]; then
            upload_folder_compressed "$target_path"
            play_sound "$COMPLETE_SOUND"
        else
            upload_folder_individual "$target_path"
            play_sound "$COMPLETE_SOUND"
        fi
    else
        echo "Error: '$target_path' is not a valid file or directory"
        exit 1
    fi
fi
