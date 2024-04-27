#!/bin/bash

#
# All the actual work performed by this script is thanks to the work of others.
#
# Thank you: yt-dlp, whisper.cpp, ffmpeg, ollama, curl and Mixtral
#


OLLAMA_HOST=127.0.0.1:11434
OLLAMA_MODEL=llama3
#OLLAMA_MODEL=mixtral
OLLAMA_CONTEXT_SIZE=8192
# >80GB RAM needed to use the full context width of Mixtral
#OLLAMA_CONTEXT_SIZE=32768
WHISPER_CPP_PATH="$HOME/whisper.cpp"
WHISPER_CPP_MODEL=ggml-large-v3.bin
WHISPER_CPP_NTHREADS=4
WHISPER_CPP_NPROCESSORS=1
# Possible speedup to the transcribing phase
#WHISPER_CPP_NPROCESSORS=3
STORAGE_DIR=".summarize.data"

function help {
	echo "Usage: summarize.sh [-q] [-c] [-d] <Youtube url>"
	echo
	echo "Optional parameters:"
	echo
	echo "  -q : Quiet, does not print any progress information or execution time"
	echo "  -c : Conversational, waits for further questions after the summary is printed"
	echo "  -C : Conversational, immediately prompts without first doing a summary"
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
	if [ ! -z ${orig_audio} ]; then
		rm ${orig_audio}.wav
	fi
	if [ ! -z ${audio} ]; then
		rm ${audio}.wav
	fi
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
	arg+="\"prompt\": \"$@\","
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
	resp=$(echo ${arg} | curl -s http://$OLLAMA_HOST/api/generate -d @-)
	if (( $? )); then
		error
		error "Unable to reach ollama server at $OLLAMA_HOST."
		error
		fail=true
	fi
	error=$(echo ${resp} | jq '.error')
	if [ ! -z "$error" ] && [ "null" != "$error" ]; then
		error
		error "LLM summary failed with the message: $error"
		error
		fail=true
	fi
	if [ true = $fail ]; then
		cleanup
		exit
	fi
	notokens=$(echo ${resp} | jq '.prompt_eval_count')
	if (( $notokens > $OLLAMA_CONTEXT_SIZE )); then
		resp+="WARNING: The size of the input to the LLM exceeded its configured max size! Output might be unreliable.\n\n"
	fi
	echo "$resp"
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
		-C )
			conv=true
			skipsum=true
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

# create storage directory if it doesn't exist
mkdir -p "$STORAGE_DIR"
# create a hash from the URL to store/recall data
storage=$(echo $video | md5sum - | awk '{print $1}')
if [ -d "$STORAGE_DIR/$storage" ]; then
	print "Existing data found for this URL ($storage) - reusing"
else
	mkdir -p "$STORAGE_DIR/$storage"
	echo "$video" > "$STORAGE_DIR/$storage/url.txt"
fi
if [ -f "$STORAGE_DIR/$storage/transcription.txt" ]; then
	print " transcribed audio"
	input=$(cat "$STORAGE_DIR/$storage/transcription.txt")
else
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
		input=$($WHISPER_CPP_PATH/main -p $WHISPER_CPP_NPROCESSORS -t $WHISPER_CPP_NTHREADS -m $WHISPER_CPP_PATH/models/$WHISPER_CPP_MODEL -np -nt -f ${audio}.wav)
	else
		input=$($WHISPER_CPP_PATH/main -p $WHISPER_CPP_NPROCESSORS -t $WHISPER_CPP_NTHREADS -m $WHISPER_CPP_PATH/models/$WHISPER_CPP_MODEL -np -nt -f ${audio}.wav 2>/dev/null)
	fi
	echo "$input" > $STORAGE_DIR/$storage/transcription.txt
fi
if [ -z "${input}" ]; then
	error
	error "Failure when transcribing, or no audio possible to transcribe detected."
	error
	cleanup
	exit
fi
if [ -z $skipsum ]; then
	print "Summarizing text... "
	input=${input//\"/\\\"}
	prompt="Please summarize the following audio transcription: $input"
	resp=$(query "$prompt")
	summary=$(echo ${resp} | jq '.response')
	context=$(echo ${resp} | jq '.context')
fi

end=$(date +%s)

if [ -z $skipsum ]; then
	print "Completed in $(($end-$start)) seconds."
	echo
	echo
	echo -e $summary
fi

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
		resp=$(query "$question. Make sure to only use knowledge found in the following audio transcription: $input")
		answer=$(echo ${resp} | jq '.response')
		context=$(echo ${resp} | jq '.context')
		echo -e $answer
		echo
	fi
done

unload
