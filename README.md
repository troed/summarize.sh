# summarize.sh

A bit of glue between components that is able to textually summarize Youtube videos - offline. The script takes a Youtube URL as argument, downloads and extracts the audio, transcribes the spoken words to text and then finally prints a summary of the content. No external services are used by this script except for the initial video download.

This script doesn't do anything clever, it just makes use of the great work done by other projects. Since the purpose is to not have to sit through 8-12 minutes of someone explaining what should've just been a short blog post, it's imperative that the summary is factually correct. That's the reason behind the default usage of the very capable Mixtral 8x7b LLM.

# Prerequisites

* yt-dlp - to download Youtube videos
* ffmpeg - to transcode the original audio to 16kHz
* whisper.cpp - transcribe the audio into text
* curl - pass the command and arguments to...
* ollama - model manager for various LLMs
* mixtral 8x7b - the default LLM used to summarize the transcribed text

# Installation

1. Install https://github.com/yt-dlp/yt-dlp in whatever way is most suitable for you.
2. Clone and make https://github.com/ggerganov/whisper.cpp and install a model. Edit the script to reflect your installation path and model name.
3. Install https://github.com/ollama/ollama - I run it as a system service and that's what the script expects. If you run it differently you need to edit the script yourself.
4. Install a suitable LLM for ollama and edit the script if it's not the default (Mixtral).
5. Clone/download this script and make it executable.
   
# Usage

./summarize.sh \<Youtube URL\>

# Performance

I made this script for my personal use, where I run it on a quite beefy 20 core workstation with 96GB RAM and a 12GB VRAM GPU. Even on my workstation the script will need 1-2 minutes to summarize an 8-16 minute video. The time is mostly spent in the Mixtral model, so to increase performance that's where you should try others.

Make sure to compile/configure both whisper.cpp and ollama to make use of GPU if you have a suitable one.

# Planned development

* After having printed the summary I will switch to a conversational interface where it's possible to ask the LLM questions regarding the transcribed content.
* Possibly: Make use of timestamped Whisper output to be able to query from which point in the original video a certain claim is made.
* 
