#!/bin/bash

# Enable caching for faster stream starts
cache=true
# specify directory to store cache items
cache_dir="/home/threadfin/conf/cache"
# specify an expiry for the cache item (in days)
cache_expire=14
# ffmpeg and yt-dlp path
# manually configure if issues
yt_dlp_path=$(which yt-dlp)
ffmpeg_path=$(which ffmpeg)

# Function to display usage instructions
usage() {
  echo "Usage: $0 -i <input> -user_agent <user-agent-string>"
  echo
  echo "Options:"
  echo "  -i            Specify the input (e.g., URL or file)"
  echo "  -user_agent   Specify the User-Agent string"
  echo
  echo "Example:"
  echo "  $0 -i \"video.m3u8\" -user_agent \"Mozilla/5.0\""
  exit 1
}

construct_command() {
  # get highest quality stream using yt-dlp
  getUrls=$(bash -c "$yt_dlp_path --user-agent \"$user_agent\" -S br -f \"bv+ba/b\" -gS proto:m3u8 \"$input\"")
  # split each line into inputs for ffmpeg
  constructInputs=$(echo "$getUrls" | awk -v ua="$user_agent" '{printf "-user_agent \"%s\" -i \"%s\" ", ua, $0}')
  # construct the ffmpeg command for output to stdout
  echo "$ffmpeg_path -y -hide_banner -loglevel quiet -fflags +genpts+discardcorrupt $constructInputs -c copy -f mpegts -copyts -reconnect 1 -reconnect_streamed 1 -reconnect_on_network_error 1 -reconnect_delay_max 10 -fflags +nobuffer pipe:1"
}

# Capture arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      if [[ -n "$2" && "$2" != -* ]]; then
        input="$2"
        shift 2
      else
        echo "Error: Missing value for -i argument."
        usage
      fi
      ;;
    -user_agent)
      if [[ -n "$2" && "$2" != -* ]]; then
        user_agent="$2"
        shift 2
      else
        echo "Error: Missing value for -user_agent argument."
        usage
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      shift
      ;;
  esac
done

# Check if required arguments are provided
if [[ -z "$input" || -z "$user_agent" ]]; then
  echo "Error: Missing required arguments."
  usage
fi

if [ "$cache" == "true" ]; then
  # check if cache dir exists, and if not, create it
  if [ ! -d "${cache_dir}" ]; then
    mkdir -p "${cache_dir}"
  fi
  # create an md5 encoded string with the master input url
  input_md5=$(echo -n "$input" | md5sum | awk '{print $1}')
  # create full path for file in cache
  cache_file="$cache_dir/ffcmd-$input_md5"
  # expire cache element if older than specified expiry time
  if [ -f "$cache_file" ]; then
    find "$cache_file" -mtime +"$cache_expire" -exec rm {} \;
  fi
  # check if cache file still exists after being checked for expiry
  if [ -f "$cache_file" ]; then
    # cache file still exists, run the command out of the cache file
    ffmpeg_command=$(< $cache_file)
  else
    # cache file doesn't exist, construct a new command and send it to the cache
    ffmpeg_command=$(construct_command)
    echo "$ffmpeg_command" > "$cache_file"
  fi
else
  # construct a new command
  ffmpeg_command=$(construct_command)
fi

# finally, run the command
bash -c "$ffmpeg_command"
