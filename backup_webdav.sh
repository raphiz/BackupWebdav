#!/usr/bin/env bash
set -e

# **Author** Raphael Zimmermann <development@raphael.li>
# 
# **License** [BSD-3-Clause](http://opensource.org/licenses/BSD-3-Clause)
# 
# Copyright (c) 2014, Raphael Zimmermann, All rights reserved.
# 
# ## TODO
# * Write the whole Duration into the mail!
# * Run script as root - OR how can webdav be mounted else?
# * Only send email if RECIPIENT is provided
# * Check if the mountpoint is empty
# * Allow external configuration using environemnt variables or source 
# * Rename/Refactor the `Main Code` section. Fucntion?
# * Log everything into the log file (see http://mostlyunixish.franzoni.eu/blog/2013/10/08/quick-log-for-bash-scripts/)
# * Rename variables (TODAY) and stuff like this
# * Fix Extend usage/prerequisites
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
# Usage : backup_webdav.sh
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

# ## Configuration

# The variable `DAV_URL` contains the address of the webdav share to backup,
# for example `https://example.com:80`.
# _Please do not add a trailing slash._
DAV_URL="https://example.com:80"

# The `DAV_SOURCE` contains a relative path on the webdav share 
# pointing to the directory to backup. If the whole share shall
# be backed up, leave this empty. For specific excludes, checkout the `RSYNC_OPTIONS`
# variable below.
# _Please do not add a trailing slash._
DAV_SOURCE="/"

# `DAV_USER` represents the name of the user to connect to the webdav share.
DAV_USER="backup"

# The `DAV_PASSWORD` variable contains the password of the user used to connect
# to the webdav share. Yes, plain text passwords ARE evil ... :(
DAV_PASSWORD="top-secrit"

# An email is sent at the end to the `RECIPIENT` address using the `mail` command.
# If this variable is empty, no email is sent.
RECIPIENT="notify@example.com"

# The `SENDER` E-Mail adress is passed to `mail` to be used as sender address.
SENDER="notify@example.com"

# The `LOCAL_MOUNTPOINT` points to where in the local file system the webdav share will be
# mountet temporarly. Note that this directory must be empty if it already exists.
# _Please do not add a trailing slash._
LOCAL_MOUNTPOINT="/mnt/backup"

# The backup archives as well as a directory called mirror will be stored
# in `LOCAL_BACKUP_DESTINATION`. This is the effective backup destination.
# This directory should ONLY be used for this script and not contain any 
# other data. This could potentially break the script.
# _Please do not add a trailing slash._
LOCAL_BACKUP_DESTINATION="/backup"

# The `RSYNC_OPTIONS` are passed to rsync. `-azvh --delete` is the highly recommended
# default. If this is modified wrongly, the script might not work properly anymore - so be careful!
# You can add here for example exclude directives etc. Checkout the rsync manpage for further details.
RSYNC_OPTIONS="-azvh --delete"

# Load configuration from external file if it exists
# This will be optimized....
if [ -e "./config.sh" ]; then
	source "./config.sh"
fi


# ## Main
# The configuration section ENDS here...Do not modify the following contents unless
# you know what you are doing! You have been warned...

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
		tar -xf "$PREVIOUS_FILE" -C "$MIRROR_DIRECTORY">>$STDOUT_LOG
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
$DAV_PASSWORD" >>$STDOUT_LOG
#" 

# After succesful mounting, the syncronization can start. The synchronization
# is based on rsync.
echo "Synchronizing data...(this can take a veeeery long time...)"
rsync $RSYNC_OPTIONS "$LOCAL_MOUNTPOINT/" "$MIRROR_DIRECTORY">>"$STDOUT_LOG"

# After the sync is done, the webdav share can be unmounted.
echo "Unmount the webdav share..."
sudo umount "$LOCAL_MOUNTPOINT">>"$STDOUT_LOG"

# The mirror directory is now archived and compressed.
echo "Creating backup archive...."
cd "$MIRROR_DIRECTORY"
tar cfz "../$TODAY_FOLDER.tar.gz" * >>"$STDOUT_LOG"

echo "Backup done! Archive created at $TODAY_FOLDER.tar.gz"

# A confirmation email is sent to notify the responsible person.
# The log file is attached.
echo "Yay! The backup is complete!" | mail -s "Backup complete!" -a $STDOUT_LOG -r $SENDER $RECIPIENT

# The log file is deleted.
rm $STDOUT_LOG

