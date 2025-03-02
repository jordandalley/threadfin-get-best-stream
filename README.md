# "Get Best Stream" yt-dlp and ffmpeg wrapper for xteve and threadfin

When using proxy mode in xteve and threadfin, ffmpeg effectively pulls all streams available in the manifest. This is not optimal, as typically only one stream is viewed by the client. This also creates delays in starting the stream by various clients, particularly in streams with multiple different quality video and audio streams.

This script utilises 'yt-dlp' to download, and cache the the highest quality HLS streams before passing it off to ffmpeg.

When using docker, you'll need to download a yt-dlp binary and include it into your xteve/threadfin container. I generally map the binary to /usr/sbin/yt-dlp.

To add the script to xteve/threadfin, the following config can be used. This script also supports http proxies if using those settings in threadfin.

![image](https://github.com/user-attachments/assets/a664adad-1c65-4bd8-a711-b916a84b581a)
