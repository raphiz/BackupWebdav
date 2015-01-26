#!/usr/bin/env bash
#set -e
# **Author** Raphael Zimmermann <development@raphael.li>
#
# **License** [BSD-3-Clause](http://opensource.org/licenses/BSD-3-Clause)
#
# Copyright (c) 2014, Raphael Zimmermann, All rights reserved.
#
# ## TODO
# * Run script as root - OR how can webdav be mounted else?
# * Check if the mountpoint is empty
# * Rename/Refactor the `Main Code` section. Fucntion?
# * Fix Extend usage/prerequisites
#
#
# # Requirements
# Please enusre that the following software is installed on the client:
#
# * rsync
# * davfs2
#
# ## WARNING
# This is not a complete backup solution! It was designed to be a foundation for a custom
# backup solution. Don't use this in production or any safety-critical environments!
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
# THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# ## Usage and Prerequisites
# This script aims to perform backups from webdav shares.
#
# Usage : backup_webdav.sh [configuration_file]
#
# ### Trust the servers SSL Certificate
# Before you start, you have to ensure you trust the servers SSL certifcate.
# Therefore, copy the PEM with the full chain to /etc/davfs2/certs/, for example:
#
# 	cp MY_CERTIFICATE.pem /etc/davfs2/certs/MY_CERTIFICATE.pem
#
# Next, uncomment the following line in the /etc/davfs2/davfs2.conf and replace
# the backup_cert with the name of the previously copied certificate name.
#
# 	trust_server_cert MY_CERTIFICATE
#
# See http://ubuntuforums.org/showthread.php?t=1034909 for more details on this...
#
# ### Setup `mail` (optional)
# You must also have setup mail properly!

# ## Duration
# The complete duration of the script is measured and sent via E-Mail (if configured).
START=$(date +%s)

#
# ## Configuration
#
# The configuration file to read specific values from.
# By default, the first argument of the script is used here.
# It's also possible to define the path to the config file via the environment
# variable "BACKUP_WEBDAV_CONFIGURATION_FILE"
configfile=$1
if [ "$configfile" == "" ];then
	env_value=$(printenv BACKUP_WEBDAV_CONFIGURATION_FILE)
	if [ "$env_value" != "" ];then
		configfile=$env_value
	fi
fi

#
# ## Read Configurations Method
# A secure way to read configuration values from a given configuration file.
# The method is called with the key name to load as first argument.
# If the configuration file exists and declares the variable (eg. FOO=BAA),
# the local variable (given as first argument) is overridden with the string value of the
# defined value of the configuration file.
# If "true" is passed as a second argument, the
function read_configuration_value {
	configuration_name="$1"
	default_value="$3"

	# If a configuration file is provided, parse the given value and
	# assign it
	if [ -f "$configfile" ]; then
		variable=$(sed -n "s/^$configuration_name= *//p" "$configfile")
		if [ "$variable" != "" ];then
			eval "cfg_$configuration_name"="$variable" # Aahhhrg! Eval is Evil!
		fi
	fi

	# Evaluate if the given configuration is required as well as
	# the contents of the variable with the name.
	required=$(echo "$2" | awk '{print tolower($0)}')

	# The alue from the config file
	value=$(set -o posix ; set | sed -n "s/^cfg_$configuration_name= *//p")

	env_value=$(printenv "$configuration_name")

	if [ "$value" == "" ];then
		if [ "$env_value" != "" ];then
			echo "Using value from environment for $configuration_name" | log "DEBUG"
			value=$env_value
		else
			echo "Using default value for $configuration_name" | log "DEBUG"
			value=$default_value
		fi
	else
		echo "Using value from configuration file for $configuration_name" | log "DEBUG"
	fi

	export "$configuration_name=$value"

	# Stop execution if a required varaible is empty/not set
	if [ "$required" == "true"  ] && [ "$value" == "" ];then
		echo "No value set for configuration $configuration_name. Please provide one in a config file or inside the script"
		exit 1
	fi
}
# ## Log Method
# The log method allows to pipe standart output into a parsable logger output.
# The log method takes an argument which is the log level (eg. INFO, ERROR etc.)
# as well as an optional prefix, eg "RSYNC" to indicate a sub-sequence of the program.
# eg. echo "Hello world" | log "INFO"
function log() {
	level=$(echo "$1" | awk '{print toupper($0)}')
	prefix="[$2] "

	# If the prefix is emtpy, remove the brackets
	if [ "$prefix" == "[] " ]; then
		prefix=""
	fi

	# Read from the pipe
	while read data; do
		# Skip empty lines
		if [ "$data" == "" ]; then
			continue
		fi

		# Log if debug is enabled or log level is not debug
		if [ \( "$VERBOSE" != "false" -a "$level" == "DEBUG" \) -o "$level" != "DEBUG" ]; then
			timestamp=$(date +'%d/%b/%Y:%X %z')
			printf "[%-5s] [%s] %s%s\n" "$level" "$timestamp" "$prefix" "$data"
		fi
	done
}

# ## convertsecs Method
# This method is used to convert the total duration into
# a human readable format: hh:mm:ss.
convertsecs() {
	h=$(($1 / 3600))
	m=$(($1  % 3600 / 60))
	s=$(($1 % 60))
	printf "%02d:%02d:%02d\n" "$h" "$m" "$s"
}


# The variable `DAV_URL` contains the address of the webdav share to backup,
# for example `https://example.com:80`.
# _Please do not add a trailing slash._
#DAV_URL=""
read_configuration_value 'DAV_URL' true ""

# The `DAV_SOURCE` contains a relative path on the webdav share
# pointing to the directory to backup. If the whole share shall
# be backed up, leave this empty. If files/directories must be excluded,
# use RSYNC_OPTIONS.
# _Please do not add a trailing slash._
read_configuration_value 'DAV_SOURCE' true "/"

# `DAV_USER` represents the name of the user to connect to the webdav share.
read_configuration_value 'DAV_USER' true ""

# The `DAV_PASSWORD` variable contains the password of the user used to connect
# to the webdav share. Yes, plain text passwords ARE evil ... :(
read_configuration_value 'DAV_PASSWORD'  true ""

# An email is sent at the end to the `RECIPIENT` address using the `mail` command.
# If this variable is empty, no email is sent.
read_configuration_value 'RECIPIENT' false ""

# The `SENDER` E-Mail adress is passed to `mail` to be used as sender address.
read_configuration_value 'SENDER' false ""

# The `LOCAL_MOUNTPOINT` points to where in the local file system the webdav share will be
# mountet temporarly. Note that this directory must be empty if it already exists.
# _Please do not add a trailing slash._
read_configuration_value 'LOCAL_MOUNTPOINT' true "/mnt/backup"

# The backup archives as well as a directory called mirror will be stored
# in `LOCAL_BACKUP_DESTINATION`. This is the effective backup destination.
# This directory should ONLY be used for this script and not contain any
# other data. This could potentially break the script.
# _Please do not add a trailing slash._
read_configuration_value 'LOCAL_BACKUP_DESTINATION' true "/backup"

# The `RSYNC_OPTIONS` are passed directly to rsync. `-avzh --deleted`
# is the highly recommended
# default. If this is modified wrongly, the script might not work properly anymore - so be careful!
# Checkout the rsync documentation for further details.
# shellcheck disable=SC2089
read_configuration_value 'RSYNC_OPTIONS' true "-avzh --delete"
IFS=' ' read -a RSYNC_OPTIONS <<< "$RSYNC_OPTIONS" # Convert the string int an array (See: SC2089)

# If the `MIRROR_ONLY` value is set to true, the webdav share is only mirrored to the
# mirror directory. The mirror directory will not be archived in this case!
read_configuration_value 'MIRROR_ONLY' false "false"
MIRROR_ONLY=$(echo "$MIRROR_ONLY" | awk '{print tolower($0)}')


# If the `VERBOSE` value is set to false, the output of the rsync command will not
# show up in the standart output. If set to true, it will logged as DEBUG log with the
# rsync prefix.
read_configuration_value 'VERBOSE' true "true"
VERBOSE=$(echo "$VERBOSE" | awk '{print tolower($0)}')

# ## Main
# The configuration section ENDS here...Do not modify the following contents unless
# you know what you are doing! You have been warned...
#
# Temporary log file. This will be sent via email after successful execution.
STDOUT_LOG=$(mktemp)

# `TODAY_FOLDER` defines how the backup achive is called.
# The naming is important for the whole script beacuse some of its logic
# is dependant on the sorting order. When sort all files in the `LOCAL_BACKUP_DESTINATION`, the last one
# must be the most up-to-date backup archive.
TODAY_FOLDER=$(date +%Y-%m-%d_%H-%M)

# The mirror directory stores a mirrored version of the webdav share.
# By having this mirror directory, the performance is much better since not all files
# must be transfered every time.
MIRROR_DIRECTORY="$LOCAL_BACKUP_DESTINATION/mirror"

# The name of the last backed up archive is evaluated.
# If the mirror directory does not exist yet, this archive will be extracted there to improve performance
# by minimizing the network usage.

PREVIOUS_FILE=""
if [ -d "$LOCAL_BACKUP_DESTINATION" ]; then
	PREVIOUS_FILE=$(find "$LOCAL_BACKUP_DESTINATION" -maxdepth 1 -type f | sort | awk '/./{line=$0} END{print line}')
fi

# The existance of the mirror directory is evaluated.
if [ -d "$MIRROR_DIRECTORY" ]; then
	echo "Using existing mirror directory...." | log "INFO"
else
	# The mirror directory is created because does not exist yet.
	echo "No mirror directory found..." | log "INFO"

	mkdir -p "$MIRROR_DIRECTORY" 2>/dev/null
	if [ "$?" != "0" ]; then
		echo "Can not create new mirror directory $MIRROR_DIRECTORY: Permission denied!" | log "ERROR"
		exit 1
	fi

	echo "New mirror directory created..." | log "INFO"

	# To reduce network usage, the `PREVIOUS_FILE` is extracted into
	# the empty mirror directory. Therefore, only the difference between
	# the last backup and now has to be exchanged via the network.
	if [ -e "$PREVIOUS_FILE" ]; then
		echo "Last backup archive was $PREVIOUS_FILE" | log "INFO"
		echo "Using last backed up archive as base to reduce transfer time" | log "INFO"
		tar -xf "$PREVIOUS_FILE" -C "$MIRROR_DIRECTORY">>"$STDOUT_LOG"
	else
		echo "no previous backup files found..." | log "INFO"
	fi
fi

# It's time to prepare the mount process. Therefore, the mountpoint is created
# if it does not yet exist.
if [ ! -d "$LOCAL_MOUNTPOINT" ]; then
	mkdir -p "$LOCAL_MOUNTPOINT"
fi
# Next, the webdav share is mounted.
echo "Mounting webdav share...." | log "INFO"
mount -t davfs "$DAV_URL$DAV_SOURCE/" "$LOCAL_MOUNTPOINT"<<<"$DAV_USER
$DAV_PASSWORD" | tee -a "$STDOUT_LOG" > /dev/null
#"

# After succesful mounting, the begin with the rsync syncronization.
echo "Mirroring webdav share...(this can take a veeeery long time...)" | log "INFO"

# Now This is carzy! The rsync command is called with the provided options and the
# Provided mountpoint of the Webdav share as well ash the mirror directory as destination.
# Then the output is piped into tee to append it to the log file (to be sent via E-Mail later)
# Afterwards, the Info messages (STDOUT) are passed to the log function and so are the error messages (STDERR)
{ { rsync "${RSYNC_OPTIONS[@]}" "$LOCAL_MOUNTPOINT/" "$MIRROR_DIRECTORY" | tee -a "$STDOUT_LOG" } 2>&3; } 2>&3 | log "INFO" "RSYNC"; } 3>&1 1>&2 | log "ERROR" "RSYNC" 2>&1;

# After the sync is done, the webdav share can be unmounted.
echo "Unmount the webdav share..." | log "INFO"
umount "$LOCAL_MOUNTPOINT" | tee -a "$STDOUT_LOG" > /dev/null

if [ "$MIRROR_ONLY" == "true" ]; then
	echo "Skipping archive creation (mirror-only mode is on)" | log "INFO"
else

	# The mirror directory is now archived and compressed.
	echo "Creating backup archive....(this can take quite a bit if a lot of data has to be compressed" | log "INFO"
	cd "$MIRROR_DIRECTORY"
	tar cfz "../$TODAY_FOLDER.tar.gz" ./* >>"$STDOUT_LOG"
	echo "Backup done! Archive created at $TODAY_FOLDER.tar.gz" | log "INFO"
fi

END=$(date +%s)
runtime=$(convertsecs $((END-START)))

# A confirmation email is sent to notify the responsible person.
# The log file is attached.
if [ "$RECIPIENT" != "" ];then
  message=$(printf "The Backup with timestamp %s is done! Overall duration: %s. Rsync result output:\\n\\n" "$TODAY_FOLDER" "$runtime")
  printf "To:%s \nFrom:%s\nSubject: %s\n\n%s" "$RECIPIENT" "$SENDER" "Backup complete!" "$message" | cat - "$STDOUT_LOG" |ssmtp "$RECIPIENT"

  rm "$STDOUT_LOG"
else
  echo "Done ! Checkout the log at $STDOUT_LOG" | log "INFO"
  echo "Duration: $runtime" | log "INFO"
fi
