#!/bin/bash
# ffmpeg-wrapper.sh written by Jordan Dalley <jordan@dalleyfamily.net>
# https://github.com/jordandalley/threadfin-get-best-stream

# Enable caching for faster stream starts
cache=true
# specify directory to store cache items
cache_dir="/home/threadfin/conf/ffmpeg-wrapper/cache"
# specify a maximum expiry for the cache item (in days)
cache_max=30
# logging enabled
logging=true
# log retention (in days)
log_retention=2
# specify directory to store logs
log_dir="/home/threadfin/conf/ffmpeg-wrapper/log"
# ffmpeg log level, eg quiet, info, verbose, debug (Default: info)
ffmpeg_loglevel="info"
# ffmpeg and yt-dlp path
# manually configure if issues
yt_dlp_path=$(command -v yt-dlp)
ffmpeg_path=$(command -v ffmpeg)

start_stream() {
  # initialise variables
  cache_revalidate="false"
  ffmpeg_logging=""
  cmd_logging=""
  # create log directory if it doesn't exist (ensure this runs silently)
  mkdir -p "$log_dir" >> /dev/null 2>&1
  # create an md5 encoded string with the master input url
  # this is used for cache and log file generation (ensure this runs silently)
  input_md5=$(echo -n "$input" | md5sum | cut -d ' ' -f1) >> /dev/null 2>&1
  if [[ "$logging" == "true" ]]; then
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    log_file="${log_dir}/${input_md5}_${timestamp}.log"
    log_stderr="2>> \"$log_file\""
    log_all=">> \"$log_file\" 2>&1"
  else
    log_stderr="2>> /dev/null"
    log_all=">> /dev/null 2>&1"
  fi
  # start logging
  # start or restart stream log files by piping a new line
  log_message "Master URL: $input"
  log_message "User Agent: $user_agent"
  if [[ -n "$http_proxy" ]]; then
    log_message "Proxy Server: $http_proxy"
  fi
  log_message "Caching Enabled: $cache"
  log_message "Cache Max: $cache_max days"
  log_message "Log Retention: $log_retention days"
  log_message "FFmpeg Log Level: $ffmpeg_loglevel"
  # expire cache elements older than specified cache_max time in days
  log_message "Cleaning logs older than $log_retention days"
  find "$log_dir" -name "*.log" -mtime +"$log_retention" -exec rm -f {} +
  # if caching enabled, check cache
  if [[ "$cache" == "true" ]]; then
    # caching enabled, get command through check_cache function
    ffmpeg_command=$(check_cache)
  else
    # caching disabled, get command directly from contruct_command function
    ffmpeg_command=$(construct_command)
  fi
  run_command
}

check_cache() {
  # check if cache dir exists, and if not, create it
  mkdir -p "${cache_dir}" "$log_all"

  # create full path for file in cache
  cache_file="$cache_dir/$input_md5.cfl"

  # check if revalidation is required
  if [[ "$cache_revalidate" == "true" ]]; then
    log_message "Cache file revalidation requested, purging $cache_file"
    rm -f "$cache_file"
  else
    # expire cache elements older than specified cache_max time in days
    log_message "Expiring any cache elements older than $cache_max days"
    find "$cache_dir" -name "*.cfl" -mtime +"$cache_max" -exec rm -f {} +
  fi

  # check if cache file still exists after expiring old cache objects
  if [ -f "$cache_file" ]; then
    log_message "Cache file $cache_file exists, checking..."
    # pull command from the cache
    output=$(< "$cache_file")
    # check the ffmpeg command for only the first instance of 'exp=[0-9]{10}' which is an expiry timestamp. These are common in akamai streams.
    if [[ $output =~ exp=([0-9]{10}) ]]; then
      log_message "Cache URL contains an expiry timestamp"
      if [[ ${BASH_REMATCH[1]} -lt $(date +%s) ]]; then
        log_message "Timestamp is expired, generate a new command"
        output=$(construct_command)
        log_message "Storing new command in cache file"
        echo "$output" > "$cache_file"
      else
        log_message "Timestamp still current, continuing on without changes"
      fi
    fi
    log_message "Cache check complete"
  else
    log_message "Cache file $cache_file doesn't exist, constructing command..."
    output=$(construct_command)
    log_message "Saving new command to cache file: $cache_file"
    echo "$output" > "$cache_file"
  fi
  echo "$output"
}

construct_command() {
  yt_dlp_proxy=""
  ffmpeg_proxy=""

  if [[ -n "$http_proxy" ]]; then
    yt_dlp_proxy="--proxy \"$http_proxy\""
    ffmpeg_proxy="-http_proxy \"$http_proxy\""
  fi

  # get highest quality stream using yt-dlp
  log_message "Finding highest quality stream..."
  getUrls=$(eval "$yt_dlp_path $yt_dlp_proxy --user-agent \"$user_agent\" -S br -f \"bv+ba/b\" -g \"$input\"" "$log_stderr")
  exit_code=$?
  if [[ "$exit_code" == 1 ]]; then
    log_message "Fatal error retrieving streams using yt-dlp. Exiting!"
    exit 1
  fi

  # check for patterns in the url that can give hints as to which ffmpeg profile to use (default is profile 1)
  ffmpeg_profile=1
  if [[ "$getUrls" == *"dai.google.com"* ]]; then
    log_message "dai.google.com detected in url, this stream may not work well..."
    ffmpeg_profile=1
  fi

  # for each line of getUrls, generate input side of ffmpeg command
  log_message "Constructing input side of ffmpeg command..."
  ff_inputs=""
  while IFS= read -r url; do
    ff_inputs+=" $ffmpeg_proxy -user_agent \"$user_agent\" -analyzeduration 3000000 -probesize 10M -thread_queue_size 1000 -fflags +discardcorrupt+genpts -i \"$url\""
  done <<< "$getUrls"

  # below are the various command profiles that are different depending on the livestream
  # for now we're just running with one command profile, but this may expand later into handling for DAI/SSAI streams etc
  log_message "Generating command for profile $ffmpeg_profile"
  if [[ "$ffmpeg_profile" == "1" ]]; then
    # ffmpeg profile 1 (default): good for most streams
    output="$ffmpeg_path -y -hide_banner -loglevel $ffmpeg_loglevel $ff_inputs -c copy -f mpegts pipe:1"
  fi
  log_message "FFmpeg command generated as: $output"
  echo "$output"
}

run_command() {
  # Run the ffmpeg command
  log_message "Running FFmpeg..."
  eval "$ffmpeg_command" "$log_stderr"

  # Capture the exit code of the ffmpeg command
  exit_code=$?

  # If the exit code is 1 (indicating failure)
  if [[ $exit_code == 1 ]]; then
    # Check if caching is enabled
    log_message "FFmpeg exited with error code: $exit_code"
    if [[ $cache == "true" ]]; then
      # If caching is enabled, set revalidation flag
      cache_revalidate="true"
      # Regenerate a new ffmpeg command
      ffmpeg_command=$(check_cache)
      # Run the command again
      log_message "Retrying ffmpeg process after revalidation..."
      eval "$ffmpeg_command" "$log_stderr"
      # Capture the new exit code
      exit_code=$?
      if [[ $exit_code == 1 ]]; then
        # If the second attempt fails, return 1 (indicating failure)
        log_message "FFmpeg exited with an error for the second time, giving up!"
        exit 1
      fi
    fi
    # If caching is not enabled or the second attempt fails, return 1
    exit 1
  fi
  # Return 0 if the command was successful
  log_message "FFmpeg exited successfully"
  exit 0
}

log_message() {
  if [[ "$logging" == "true" ]]; then
    echo "[ffmpeg-wrapper]: $*" >> "$log_file"
  fi
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
        echo
        usage
      fi
      ;;
    -user_agent)
      if [[ -n "$2" && "$2" != -* ]]; then
        user_agent="$2"
        shift 2
      else
        echo "Error: Missing value for -user_agent argument."
        echo
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
  # Show usage when no arguments supplied
  usage
fi

start_stream
