#!/bin/bash

#
# All the actual work performed by this script is thanks to the work of others.
#
# Thank you: yt-dlp, whisper.cpp, ffmpeg, ollama, curl and Mixtral
#

OLLAMA_HOST=127.0.0.1:11434
OLLAMA_MODEL=mixtral
OLLAMA_CONTEXT_SIZE=8192
WHISPER_CPP_PATH="$HOME/whisper.cpp"
WHISPER_CPP_MODEL=ggml-large-v3.bin

function cleanup {
	rm ${orig_audio}.wav
	rm ${audio}.wav
}

# setting these makes the output reproducible
seed=99065467
temp=1

echo

fail=false

if [ -z $1 ]; then
	echo "Usage: summarize.sh <Youtube url>"
	echo
	fail=true
fi

if [ -z $(which yt-dlp) ]; then
	echo "Unable to find the yt-dlp executable"
	echo
	fail=true
fi

if [ -z $(which ffmpeg) ]; then
	echo "Unable to find the ffmpeg executable"
	echo
	fail=true
fi

if [ ! -f "${WHISPER_CPP_PATH}"/main ]; then
	echo "Unable to find the main executable for the whisper.cpp project"
	echo
	fail=true
fi

if [ ! -f "${WHISPER_CPP_PATH}/models/${WHISPER_CPP_MODEL}" ]; then
	echo "Unable to find the $WHISPER_CPP_MODEL model in the whisper.cpp project"
	echo
	fail=true
fi

if [ true = $fail ]; then
	exit
fi

orig_audio=$(mktemp -u)
echo -n "Downloading audio... "
yt-dlp -x --audio-format wav -o ${orig_audio}.wav "$1" &>/dev/null
echo -n "Converting audio... "
audio=$(mktemp -u)
ffmpeg -i ${orig_audio}.wav -ar 16000 -ac 1 -c:a pcm_s16le ${audio}.wav &>/dev/null
echo -n "Transcribing audio... "
input=$($WHISPER_CPP_PATH/main -m $WHISPER_CPP_PATH/models/$WHISPER_CPP_MODEL -np -nt -f ${audio}.wav 2>/dev/null)
if [ -z "${input}" ]; then
	echo
	echo "Failure when transcribing, or no audio possible to transcribe detected."
	echo
	cleanup
	exit
fi
echo -n "Summarizing text... "
prompt="Please summarize the following textual contents of a video: $input"
prompt=${prompt//\"/\\\"}
arg="{\"model\": \"$OLLAMA_MODEL\", \
      \"prompt\": \"${prompt}\", \
      \"stream\": false, \
      \"options\": { \
        \"seed\": ${seed}, \
        \"temperature\": ${temp}, \
        \"num_ctx\": $OLLAMA_CONTEXT_SIZE
      } \
     }"
resp=$(echo ${arg} | curl -s http://$OLLAMA_HOST/api/generate -d @-)
if (( $? )); then
	echo
	echo "Unable to reach ollama server at $OLLAMA_HOST."
	echo
	cleanup
	exit
fi
resp=$(echo ${resp} | jq '.response')
echo
echo
echo -e $resp
echo
cleanup
# unload ollama model from GPU
arg="{\"model\": \"$OLLAMA_MODEL\", \
		  \"keep_alive\": 0
     }"
resp=$(echo ${arg} | curl -s http://$OLLAMA_HOST/api/generate -d @-)
resp=$(echo ${resp} | jq '.done')
if [[ "true" != "${resp}" ]]; then
	echo
	echo "Ollama failed to unload memory used by the model. This might mean subsequent running of the script will fail."
	echo
fi
