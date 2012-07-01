#!/bin/sh

# This script is located on the server and is run regularly by cron.  It 
# performs a dump of the database as well as /var/log.  This is stored in an
# encrypted, signed and compressed format.  It also clears out any backups that
# are older than a year.

# Customisable options #########################################################

# Where do you want everything done?  ROOTDIR/{tmp,data} should already exist 
# and be writable by the user invoking this script
ROOTDIR=/backup

# Make sure important things are in our path
PATH=/bin:/usr/bin

# Where is the equivalent of ~/.gnupg?
GPGHOME=/backup/config/gnupg

# What are the keyIDs that we want to encrypt and sign to?
ENCRYPT_KEYID=0xEEABA323
SIGN_KEYID=0x7FCE6178

# MySQL user with SELECT privileges only on the openmrs database
MYSQLUSER=backup
MYSQLPASS=password

# Business time ################################################################

# Set the timestamp so that it is consistent across the script
TIMESTAMP=`date +'%Y-%m-%dT%H%M%S%Z'`

# Create a directory in ROOTDIR/tmp to work in (in case multiple instances of
# this script are running)
TMP=${ROOTDIR}/tmp/${RANDOM}
mkdir -p ${TMP}

# Dump the database
mysqldump -u ${MYSQLUSER} --password=${MYSQLPASS} \
	  --compact \
	  --single-transaction \
          --skip-extended-insert \
          --order-by-primary \
          --default-character-set=latin1 \
          openmrs > ${TMP}/openmrs.sql

# Create a file containing the timestamp
echo ${TIMESTAMP} > ${TMP}/TIMESTAMP

# Move everything into a timestamped directory, ready for processing
mkdir ${TMP}/${TIMESTAMP}
mv ${TMP}/openmrs.sql ${TMP}/${TIMESTAMP}
mv ${TMP}/TIMESTAMP ${TMP}/${TIMESTAMP}

# Compress
cd ${TMP}
/usr/bin/sudo /bin/tar cjf ${TIMESTAMP}.tar.bz2 ${TIMESTAMP} /var/log

# Encrypt and sign
gpg --homedir ${GPGHOME} \
    --no-verbose \
    --quiet \
    --batch \
    --no-tty \
    --output ${TMP}/${TIMESTAMP}.tar.bz2.gpg \
    --encrypt \
    --recipient ${ENCRYPT_KEYID} \
    --sign \
    --local-user ${SIGN_KEYID} \
    --always-trust \
    ${TMP}/${TIMESTAMP}.tar.bz2

# Move to data directory
mv ${TMP}/${TIMESTAMP}.tar.bz2.gpg ${ROOTDIR}/data

# Remove temporary files
rm -Rf ${TMP}

# Remove any backups older than one year
find ${ROOTDIR}/data/*.tar.bz2.gpg -mtime +365 -exec rm {} \;

# chmod files
chmod 644 ${ROOTDIR}/data/*.tar.bz2.gpg

exit 0
