# summarize.sh

A bit of glue between components that is able to textually summarize videos and podcasts - offline. The script takes a URL as argument, downloads and extracts the audio, transcribes the spoken words to text and then finally prints a summary of the content. No external services are used by this script except for the initial audio download. Examples of URLs that work are Youtube videos and Apple podcasts, see the yt-dlp project for the full list.

This script doesn't do anything clever, it just makes use of the great work done by other projects. Since the purpose is to not have to sit through 8-12 minutes of someone explaining what should've just been a short blog post. The default model used is LLaMa-3 to support medium spec hardware. If you have a large system, Mixtral 8x7b is another great option with a much larger context window (= able to work with longer transcriptions).

With Mixtral, this script has been tested on a 1 hour long podcast, where the conversation mode was subsequently used to dive into more details on one of the subjects mentioned in the summary.

The script saves transcriptions to a folder in the same directory, and if the same URL is later used again it will not re-download the audio and create a new transcription but use the existing one. This means it's possible to later use the conversational mode to ask questions on the content, even if not done the first time.

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

./summarize.sh [-q] [-c] [-d] \<Youtube url\>

Optional parameters:

  -q : Quiet, does not print any progress information or execution time  
  -c : Conversational, waits for further questions after the summary is printed  
  -C : Conversational, immediately prompts without first doing a summary  
  -d : Debug, prints all output from the called programs  
 
# Performance

I made this script for my personal use, where I run it on a quite beefy 20 core workstation with 96GB RAM and a 12GB VRAM GPU. To give an estimate on what performance you could expect to see I've chosen two videos randomly:

| Video                                       | Length   | Mixtral    | LLaMa-3    |
|---------------------------------------------|----------|------------|------------|
| https://www.youtube.com/watch?v=NngCHTImH1g | 20 min   | 6 min 40s  | 3 min 57s  |
| https://www.youtube.com/watch?v=emFf4W3WzYI | 11 min   | 3 min 13s  | 1 min 34s  |

There are a number of things that can be done to increase performance. The script contains two variables for number of threads and number of processors to use for whisper.cpp. On my 12GB VRAM I can use 4 processors, while someone with a 24GB 3090 has been able to run 11.

The time is however mostly spent in the Mixtral model, and it is both GPU and RAM hungry. The default context of 8192 tokens should work for most, but if you want to summarize very long videos you can increase it up to the maximum 32768 if you have enough RAM.

Of course, most importantly is to make sure to compile/configure both whisper.cpp and ollama to make use of GPU to start with.

# Planned development

* ~~After having printed the summary I will switch to a conversational interface where it's possible to ask the LLM questions regarding the transcribed content.~~
* Automatically run on predefined subscriptions and send summaries through some means
* Possibly: Make use of timestamped Whisper output to be able to query from which point in the original video a certain claim is made.
* ...

# Tips & tricks

With all transcriptions saved, finding from which source you read about something interesting becomes a simple command:

$ grep -H <something> .summarize.data/*/transcription.txt | while read line; do cat "${line%/*}"/url.txt; done < <(awk '{print $1}')
