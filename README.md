# "ffmpeg-wrapper.sh"

This script is an ffmpeg wrapper for threadfin that optimises the retrieval of highest quality live streams with caching for faster channel switching.

## Introduction

When using ffmpeg in proxy mode in threadfin, ffmpeg ignores individual stream quality information in the m3u8 manifest and probes all streams to determine which is the highest resolution and quality. This is time consuming and not optimal when the m3u8 manifest contains all the relevant information necessary to determine the best stream.

This script passes tne requested stream url to 'yt-dlp' first, which parses the m3u8 manifest for the highest quality stream (or streams if audio and video separate), builds a special ffmpeg command which feeds the highest quality stream directly to it, and caches the command (when appropriate) for subsequent streams.

## Installation

This installation guide assumes that you are using threadfin in a docker container.

1. Download the latest '[yt-dlp_linux](https://github.com/yt-dlp/yt-dlp/releases)' binary
2. Place the 'yt-dlp_linux' binary with the rest of your persistent data for threadfin
3. Ensure that the 'yt-dlp_linux' binary is executable: ```chmod +x yt-dlp_linux```
4. Update your docker compose file to map the binary into the container

```
services:
  threadfin:
    image: fyb3roptik/threadfin:latest
    container_name: threadfin
    #orts:
      - 34400:34400
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Pacific/Auckland
    volumes:
      - /path/to/threadfin/config:/home/threadfin/conf
      - /path/to/threadfin/tmp:/tmp/threadfin
      - /path/to/threadfin/yt-dlp/yt-dlp:/usr/bin/yt-dlp
    restart: unless-stopped
```

5. Run ```docker compose up -d``` to refresh the configuration and restart the threadfin docker container
6. Copy the [get_best_stream.sh](get_best_stream.sh) file to your persistent config directory for threadfin
7. Set the script to executable: ```chmod +x get_best_stream.sh```
8. Open the threadfin interface and navigate to 'Settings'
9. Configure a user agent. I use ```Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36``` to emulate Chrome on Windows.
10. Change the ffmpeg binary path to ```/home/threadfin/conf/get_best_stream.sh``` (or wherever you decided to place the binary)
11. You can leave the 'FFmpeg Options' field as is. The only options that the wrapper script uses are the input url, the proxy (if enabled) and user agent. All that is required to pass to the script is the following: ```-i [URL]```
12. Save your configuration, then enable 'ffmpeg' proxy mode for any of your m3u8 playlists.

![image](https://github.com/user-attachments/assets/a664adad-1c65-4bd8-a711-b916a84b581a)

## Script options

If you edit the 'get_best_stream.sh' wrapper, you will see a number of options that can be configured. The defaults will work fine in most instances.

| Variable | Type | Description | Default |
| --- | --- | --- | --- | 
| cache | boolean | Enables or disables caching of predetermined optimised ffmpeg commands. Disable this if facing issues with loading some streams | true |
| cache_dir | string | Specifies the path in which to store the 'ffcmd-*' cache files | /home/threadfin/conf/ffmpeg-wrapper/cache |
| cache_max | integer | Specifies the maximum amount of time, in days, that a cache file should remain valid | 30 |
| logging | boolean | Enables or disables logging of wrapper script processes and ffmpeg output | true |
| log_retention | integer | Specifies the maximum amount of days that log files should be retained for | 2 |
| cache_dir | string | Specifies the path in which to store the '*.cfl' cache files | /home/threadfin/conf/ffmpeg-wrapper/log |
| ffmpeg_loglevel="info" | string | Specifies the verbosity of ffmpeg logging, if logging is enabled: Valid options include: quiet, info, verbose, and debug | info |
| yt_dlp_path | string | Specifies the path to the yt-dlp binary. The default checks $PATH for the command | $(command -v yt-dlp) |
| ffmpeg_path | string | Specifies the path to the ffmpeg binary. The default checks $PATH for the command | $(command -v ffmpeg) |

## Clearing the cache

If you have modified the ffmpeg command in the script in any way, you will need to purge the cache before your changes become effective.

Find the cache directory by the 'cache_dir' variable in the top of the script, then run the following (assuming the default): ```docker exec -it threadfin rm /home/threadfin/conf/ffmpeg-wrapper/cache/*.cfl -f```
