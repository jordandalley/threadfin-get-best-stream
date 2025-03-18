# Get Best Stream for Threadfin
## yt-dlp and ffmpeg wrapper for threadfin and xteve

When using proxy mode (using ffmpeg) in threadfin, ffmpeg effectively pulls all streams available in the manifest. This is not optimal, as typically only one stream is viewed by the client. This also creates delays in starting the stream by various clients, particularly in streams with multiple different quality video and audio streams.

This script utilises a 'yt-dlp' binary to figure out the highest quality stream or streams (if audio and video separate).

This script also includes caching functionality. This functionality ensures that on subsequent streams of the same channel, it will reach out to the predetermined best stream directly rather than look it up again.

When using docker, you'll need to download a yt-dlp binary and include it into your xteve/threadfin container. I generally map the binary to /usr/sbin/yt-dlp.

To add the script to xteve/threadfin, the following config can be used. This script also supports http proxies if using those settings in threadfin.

![image](https://github.com/user-attachments/assets/a664adad-1c65-4bd8-a711-b916a84b581a)
