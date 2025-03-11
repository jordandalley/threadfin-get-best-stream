#!/bin/bash

# Enable caching for faster stream starts
cache=true
# specify directory to store cache items (allow overriding)
cache_dir="/home/threadfin/conf/cache"
# specify a maximum expiry for the cache item (in days)
cache_max=30
# ffmpeg and yt-dlp path
# manually configure if issues
yt_dlp_path=$(command -v yt-dlp)
ffmpeg_path=$(command -v ffmpeg)

construct_command() {
  yt_dlp_proxy=""
  ffmpeg_proxy=""

  if [[ -n "$http_proxy" ]]; then
    yt_dlp_proxy="--proxy \"$http_proxy\""
    ffmpeg_proxy="-http_proxy \"$http_proxy\""
  fi

  # get highest quality stream using yt-dlp
  getUrls=$(eval "$yt_dlp_path $yt_dlp_proxy --user-agent \"$user_agent\" -S br -f \"bv+ba/b\" -gS proto:m3u8 \"$input\"")

  # split each line into inputs for ffmpeg which include proxy (if applicable) and user agent strings
  constructInputs=$(echo "$getUrls" | awk -v ua="$user_agent" -v proxy="$ffmpeg_proxy" '{printf "%s -user_agent \"%s\" -i \"%s\" ", proxy, ua, $0}')

  # construct the ffmpeg command for output to stdout
  echo "$ffmpeg_path -y -hide_banner -loglevel quiet -threads auto -re -analyzeduration 10000000 -probesize 10M -fflags +discardcorrupt+genpts $constructInputs -c copy -f mpegts -reconnect 1 -reconnect_streamed 1 -reconnect_on_network_error 1 -reconnect_delay_max 2 -reconnect_at_eof 1 pipe:1"
}

run_command() {
  # run the ffmpeg commamd
  eval "$ffmpeg_command"
  # set the error code to exit_code variable
  exit_code=$?
  # check exit code for errors and if exit code is more than 0, delete cache file and try again
  if [[ $exit_code -gt 0 ]]; then
    for i in {1..5}; do
      # if caching enabled, skip cache any maintenance
      if [[ $cache == "true" ]]; then
        rm -f "$cache_file"
        check_cache
      fi
      eval "$ffmpeg_command"
      exit_code=$?
      # if ffmpeg exits with code 0, its successful, exit with code 0
      if [[ $exit_code -eq 0 ]]; then
        return 0
      fi
    done
    # exhausted all options, exit with code 1
    return 1
  fi
}

check_cache() {

  if [ "$cache" == "true" ]; then
    # check if cache dir exists, and if not, create it
    mkdir -p "${cache_dir}"

    # expire cache elements older than specified cache_max time in days
    find "$cache_dir" -name "ffcmd-*" -mtime +"$cache_max" -exec rm -f {} +

    # create an md5 encoded string with the master input url
    input_md5=$(echo -n "$input" | md5sum | cut -d ' ' -f1)
    # create full path for file in cache
    cache_file="$cache_dir/ffcmd-$input_md5"

    # check if cache file still exists after expiring old cache objects
    if [ -f "$cache_file" ]; then
      # pull command from the cache
      ffmpeg_command=$(< "$cache_file")
      # check the ffmpeg command for only the first instance of 'exp=[0-9]{10}' which is an expiry timestamp. These are common in akamai streams.
      if [[ $ffmpeg_command =~ exp=([0-9]{10}) ]]; then
        # if there is a expiry string in the command, then extract it and check if it is expired
        if [[ ${BASH_REMATCH[1]} -lt $(date +%s) ]]; then
          # timestamp is expired, generate a new command and update cache file (this updated modified time for further cache checking)
          ffmpeg_command=$(construct_command)
          echo "$ffmpeg_command" > "$cache_file"
        fi
      fi
    else
      # create the ffmpeg_command variable
      ffmpeg_command=$(construct_command)
      # create a cache file
      echo "$ffmpeg_command" > "$cache_file"
    fi
  else
    # caching is not enabled, just construct the command
    ffmpeg_command=$(construct_command)
  fi
  run_command
}

usage() {
  echo "Usage: $0 -i <input> -user_agent <user-agent-string>"
  echo
  echo "Mandatory Arguments:"
  echo "  -i            Specify the input (e.g., URL or file)"
  echo "  -user_agent   Specify the User-Agent string"
  echo
  echo "Optional Arguments:"
  echo "  -http_proxy   Specify an http proxy to use (e.g., \"http://proxy.server.address:3128\")"
  echo
  echo "Example:"
  echo "  $0 -i \"https://url.to.stream/tvchannel.m3u8\" -user_agent \"Mozilla/5.0\""
  exit 1
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
    -http_proxy)
      if [[ -n "$2" && "$2" != -* ]]; then
        http_proxy="$2"
        shift 2
      else
        http_proxy=""
        shift
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

if [[ -z "$input" || -z "$user_agent" ]]; then
  echo "Error: Missing required arguments."
  usage
fi

check_cache
