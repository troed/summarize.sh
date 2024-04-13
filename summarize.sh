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

function help {
	echo "Usage: summarize.sh [-q] [-c] <Youtube url>"
	echo
	echo "Optional parameters:"
  echo
	echo "  -q : Quiet, does not print any progress information or execution time"
	echo "  -c : Conversational, waits for further questions after the summary is printed"
	echo "  -d : Debug, prints all output from the called programs"
	echo
}

# unload ollama model from GPU in the background
function unload {
	(
		arg="{\"model\": \"$OLLAMA_MODEL\", \
				  \"keep_alive\": 0
		     }"
		resp=$(echo ${arg} | curl -s http://$OLLAMA_HOST/api/generate -d @-)
		resp=$(echo ${resp} | jq '.done')
		if [[ "true" != "${resp}" ]]; then
			error
			error "Ollama failed to unload memory used by the model. This might mean subsequent running of the script will fail."
			error
		fi
	) &
}

function cleanup {
	rm ${orig_audio}.wav
	rm ${audio}.wav
}

function print {
  if [[ -z $quiet ]]; then
		echo -n "$1"
  fi
}

function error {
	>&2 echo "$1"
}


function query {
	arg="{";
	arg+="\"model\": \"$OLLAMA_MODEL\","
	arg+="\"prompt\": \"$1\","
	arg+="\"stream\": false,"
	if [ ! -z "$context" ]; then
		arg+="\"context\": ${context},"
	fi
	arg+="\"options\": {"
	arg+="\"seed\": ${seed},"
	arg+="\"temperature\": ${temp},"
	arg+="\"num_ctx\": $OLLAMA_CONTEXT_SIZE"
	arg+="}"
	arg+="}"
	echo ${arg} | curl -s http://$OLLAMA_HOST/api/generate -d @-
	if (( $? )); then
		echo error
	fi
}

# setting these makes the output reproducible
seed=99065467
temp=1

echo

fail=false
debug=false
context=""

if [ -z $1 ]; then
	help
	fail=true
fi

while (( "$#" )); do
	case $1 in
		-h )
			help
			fail=true
			;;
		-q )
			quiet=true
			;;
		-c )
			conv=true
			;;
		-d )
			debug=true
			;;
		http* )
			video="$1"
			;;
		* )
			help
			fail=true
			;;
	esac
	shift
done

if [ -z $(which yt-dlp) ]; then
	echo "Unable to find the yt-dlp executable"
	echo
	fail=true
fi

if [ -z $(which jq) ]; then
	echo "Unable to find the JSON parser 'jq', please install it"
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

start=$(date +%s)

orig_audio=$(mktemp -u)
print "Downloading audio... "
if [ true = $debug ]; then
	yt-dlp -x --audio-format wav -o ${orig_audio}.wav "$video"
else
	yt-dlp -x --audio-format wav -o ${orig_audio}.wav "$video" &>/dev/null
fi
print "Converting audio... "
audio=$(mktemp -u)
if [ true = $debug ]; then
	ffmpeg -i ${orig_audio}.wav -ar 16000 -ac 1 -c:a pcm_s16le ${audio}.wav
else
	ffmpeg -i ${orig_audio}.wav -ar 16000 -ac 1 -c:a pcm_s16le ${audio}.wav &>/dev/null
fi
print "Transcribing audio... "
if [ true = $debug ]; then
	input=$($WHISPER_CPP_PATH/main -m $WHISPER_CPP_PATH/models/$WHISPER_CPP_MODEL -np -nt -f ${audio}.wav)
else
	input=$($WHISPER_CPP_PATH/main -m $WHISPER_CPP_PATH/models/$WHISPER_CPP_MODEL -np -nt -f ${audio}.wav 2>/dev/null)
fi
if [ -z "${input}" ]; then
	error
	error "Failure when transcribing, or no audio possible to transcribe detected."
	error
	cleanup
	exit
fi
print "Summarizing text... "
input=${input//\"/\\\"}
prompt="Please summarize the following textual contents of a video: $input"
resp=$(query "$prompt")
if [[ "error" == "$resp" ]]; then
	error
	error "Unable to reach ollama server at $OLLAMA_HOST."
	error
	cleanup
	exit
fi
summary=$(echo ${resp} | jq '.response')
context=$(echo ${resp} | jq '.context')

end=$(date +%s)
print "Completed in $(($end-$start)) seconds."

echo
echo
echo -e $summary
echo
cleanup

if [ -z $conv ]; then
	unload
	exit
fi

# Conversational code follows
while true; do
		echo
    read -p "Enter question (enter to exit): " question
    echo
    if [ -z "$question" ]; then
			break
    else
			resp=$(query "$question in the following textual representation of a video: $input")
			answer=$(echo ${resp} | jq '.response')
			context=$(echo ${resp} | jq '.context')
			echo -e $answer
			echo
    fi
done

unload
