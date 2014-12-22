#!/usr/bin/env bash
#set -e
# **Author** Raphael Zimmermann <development@raphael.li>
#
# **License** [BSD-3-Clause](http://opensource.org/licenses/BSD-3-Clause)
#
# Copyright (c) 2014, Raphael Zimmermann, All rights reserved.
#
# ## TODO
# * Write the whole Duration into the mail!
# * Run script as root - OR how can webdav be mounted else?
# * Check if the mountpoint is empty
# * Allow external configuration using environemnt variables or source
# * Rename/Refactor the `Main Code` section. Fucntion?
# * Log everything into the log file (see http://mostlyunixish.franzoni.eu/blog/2013/10/08/quick-log-for-bash-scripts/)
# * Rename variables (TODAY) and stuff like this
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
#
# ## Configuration
#
# The configuration file to read specific values from.
# By default, the first argument of the script is used here.
configfile=$1
#
# ## Read Configurations Method
# A secure way to read configuration values from a given configuration file.
# The method is called with the key name to load as first argument.
# If the configuration file exists and declares the variable (eg. FOO=BAA),
# the local variable (given as first argument) is overridden with the string value of the
# defined value of the configuration file.
# If "true" is passed as a second argument, the
function read_configuration_value {
	configuration_name=$1

	# If a configuration file is provided, parse the given value and
	# assign it
	if [ -f "$configfile" ]; then
		variable=$(sed -n "s/^$configuration_name= *//p" "$configfile")
		if [ "$variable" != "" ];then
			eval "$configuration_name"="$variable" # Aahhhrg! Eval is Evil!
		fi
	fi

	# Evaluate if the given configuration is required as well as
	# the contents of the variable with the name.
	required=$(echo "$2" | awk '{print tolower($0)}')

	value=$(set -o posix ; set | sed -n "s/^$configuration_name= *//p")


	# Stop execution if a required varaible is empty/not set
	if [ "$required" == "true"  ] && [ "$value" == "" ];then
		echo "No value set for configuration $configuration_name. Please provide one in a config file or inside the script"
		exit 1
	fi
}


# The variable `DAV_URL` contains the address of the webdav share to backup,
# for example `https://example.com:80`.
# _Please do not add a trailing slash._
DAV_URL=""
read_configuration_value 'DAV_URL' true

# The `DAV_SOURCE` contains a relative path on the webdav share
# pointing to the directory to backup. If the whole share shall
# be backed up, leave this empty. If files/directories must be excluded,
# use RSYNC_OPTIONS.
# _Please do not add a trailing slash._
DAV_SOURCE="/"
read_configuration_value 'DAV_SOURCE' true

# `DAV_USER` represents the name of the user to connect to the webdav share.
DAV_USER=""
read_configuration_value 'DAV_USER' true

# The `DAV_PASSWORD` variable contains the password of the user used to connect
# to the webdav share. Yes, plain text passwords ARE evil ... :(
DAV_PASSWORD=""
read_configuration_value 'DAV_PASSWORD'  true

# An email is sent at the end to the `RECIPIENT` address using the `mail` command.
# If this variable is empty, no email is sent.
RECIPIENT=""
read_configuration_value 'RECIPIENT' false

# The `SENDER` E-Mail adress is passed to `mail` to be used as sender address.
SENDER=""
read_configuration_value 'SENDER' false

# The `LOCAL_MOUNTPOINT` points to where in the local file system the webdav share will be
# mountet temporarly. Note that this directory must be empty if it already exists.
# _Please do not add a trailing slash._
LOCAL_MOUNTPOINT="/mnt/backup"
read_configuration_value 'LOCAL_MOUNTPOINT' true

# The backup archives as well as a directory called mirror will be stored
# in `LOCAL_BACKUP_DESTINATION`. This is the effective backup destination.
# This directory should ONLY be used for this script and not contain any
# other data. This could potentially break the script.
# _Please do not add a trailing slash._
LOCAL_BACKUP_DESTINATION=""
read_configuration_value 'LOCAL_BACKUP_DESTINATION' true

# The `RSYNC_OPTIONS` are passed directly to rsync. `-avzh --exclude 'Thumbs.db' --exclude '/lost+found/' --delete`
# is the highly recommended
# default. If this is modified wrongly, the script might not work properly anymore - so be careful!
# Checkout the rsync documentation for further details.
# shellcheck disable=SC2089
RSYNC_OPTIONS="-avzh --exclude=Thumbs.db --exclude=lost+found --delete"
read_configuration_value 'RSYNC_OPTIONS' true
IFS=' ' read -a RSYNC_OPTIONS <<< "$RSYNC_OPTIONS" # Convert the string int an array (See: SC2089)

# If the `MIRROR_ONLY` value is set to true, the webdav share is only mirrored to the
# mirror directory. The mirror directory will not be archived in this case!
MIRROR_ONLY="false"
read_configuration_value 'MIRROR_ONLY' false
MIRROR_ONLY=$(echo $MIRROR_ONLY | awk '{print tolower($0)}')

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
PREVIOUS_FILE=$(find "$LOCAL_BACKUP_DESTINATION" -maxdepth 1 -type f | sort | awk '/./{line=$0} END{print line}')

# The existance of the mirror directory is evaluated.
if [ -d "$MIRROR_DIRECTORY" ]; then
	echo "Using existing mirror directory...."
else
	# The mirror directory is created because does not exist yet.
	echo "No mirror directory found...it will be created..."
	mkdir -p "$MIRROR_DIRECTORY"

	# To reduce network usage, the `PREVIOUS_FILE` is extracted into
	# the empty mirror directory. Therefore, only the difference between
	# the last backup and now has to be exchanged via the network.
	if [ -e "$PREVIOUS_FILE" ]; then
		echo "Last backup archive was $PREVIOUS_FILE"
		echo "Using last backed up archive as base to reduce transfer time"
		tar -xf "$PREVIOUS_FILE" -C "$MIRROR_DIRECTORY">>"$STDOUT_LOG"
	else
		echo "no previous backup files found..."
	fi
fi

# It's time to prepare the mount process. Therefore, the mountpoint is created
# if it does not yet exist.
if [ ! -d "$LOCAL_MOUNTPOINT" ]; then
	mkdir -p "$LOCAL_MOUNTPOINT"
fi

# Next, the webdav share is mounted.
echo "Mounting webdav share...."
sudo mount -t davfs $DAV_URL$DAV_SOURCE/ $LOCAL_MOUNTPOINT<<<"$DAV_USER
$DAV_PASSWORD" | sudo tee -a "$STDOUT_LOG" > /dev/null
#"

# After succesful mounting, the begin with the rsync syncronization.
echo "Mirroring webdav share...(this can take a veeeery long time...)"
rsync "${RSYNC_OPTIONS[@]}" "$LOCAL_MOUNTPOINT/" "$MIRROR_DIRECTORY" >> "$STDOUT_LOG"

# After the sync is done, the webdav share can be unmounted.
echo "Unmount the webdav share..."
sudo umount "$LOCAL_MOUNTPOINT" | sudo tee -a "$STDOUT_LOG" > /dev/null

if [ "$MIRROR_ONLY" == "true" ]; then
	echo "Skipping archive creation (mirror-only mode is on)"
else

	# The mirror directory is now archived and compressed.
	echo "Creating backup archive....(this can take quite a bit if a lot of data has to be compressed"
	cd "$MIRROR_DIRECTORY"
	tar cfz "../$TODAY_FOLDER.tar.gz" ./* >>"$STDOUT_LOG"
	echo "Backup done! Archive created at $TODAY_FOLDER.tar.gz"
fi

# A confirmation email is sent to notify the responsible person.
# The log file is attached.
if [ "$RECIPIENT" != "" ];then
  echo "The Backup with timestam $TODAY_FOLDER is done!\
  Checkout the attached log file for details."  | mail -s "Backup complete" -a "$STDOUT_LOG" -r "$SENDER" "$RECIPIENT"
  rm "$STDOUT_LOG"
else
  echo "Done! Checkout the log at $STDOUT_LOG"
fi
