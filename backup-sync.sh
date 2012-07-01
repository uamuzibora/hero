#!/bin/sh

# This script is designed to be run from cron on the netbooks.  It uses rsync
# to keep a copy a month's worth of backups.

# Customisable options #########################################################

# Where shall we keep the backups on the netbooks?
NETBOOK_DIR=/home/uamuzibora/server-backup

# Where are the backups stored on the server?  It is VERY IMPORTANT that there
# is no trailing slash
SERVER_DIR=/backup/data

# What is the server's address?
SERVER=192.168.1.2

# What user can I access the backups directory as on the server?
USER=backup


# Business time ################################################################

# We need a temporary file for storing the list of files to rsync
FILES=/tmp/`date | openssl dgst -md5`

# What are the files we want?
ssh ${USER}@${SERVER} \
    "find /backup/data -name '*\.tar\.bz2\.gpg' -mtime -31" \
    > ${FILES}

# Lets rsync them (hopefully only one file will be transferred, the most recent
# one)
rsync -aqz --files-from=${FILES} ${USER}@${SERVER}:/ ${NETBOOK_DIR}

# Remove locally any files that are too old
find ${NETBOOK_DIR} -name '*\.tar\.bz2\.gpg' -mtime +30 -exec rm -f {} \;

# chmod these files
chmod 400 ${NETBOOK_DIR}/backup/data/*.tar.bz2.gpg

# Tidy up time
rm ${FILES}

exit 0
