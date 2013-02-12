#!/bin/bash

# This script is located our Linode web server and is run daily by cron as root. 
# It establishes a VPN connection with Kasha (our server in Kakamega). It uses
# SCP with a passwordless key to a chrooted user (backup) with no terminal on
# Kasha to copy the latest backup file to this server.
# It then decrypts the anonymised database dump and logfiles, puts the logfiles
# into logstash and reloads the anonymised database dump into the MoH HIV
# reports OpenMRS instance.

# Customisable options #########################################################

# Where do you want everything done?  ROOTDIR/{tmp,dumps,config} should already
# exist and be writable by the user invoking this script
ROOTDIR=/var/backups-kasha

# Make sure important things are in our path
PATH=/bin:/usr/bin

# Where is the equivalent of ~/.gnupg?
GPGHOME=${ROOTDIR}/config/gnupg

# The Amazon S3 bucket we use
BUCKET=uamuzibora-backups

# Path to the s3cmd config file
S3CMDCONFIG=${ROOTDIR}/config/s3cmd.config

# Functions ####################################################################

function send_log () {
	curl -X POST "https://api.postmarkapp.com/email" \
	-H "Accept: application/json" \
	-H "Content-Type: application/json" \
	-H "X-Postmark-Server-Token: [TOKEN]" \
	-d "{From: '[EMAIL]', To: '[EMAIL]', Subject: 'Backup Retrieval: FAILED - `date -R`', TextBody: '`cat ${LOG}`'}"
}

# Cue the music ################################################################

# Create a directory in ROOTDIR/tmp to work in (in case multiple instances of
# this script are running)
TMP=${ROOTDIR}/tmp/${RANDOM}
mkdir -p ${TMP}
cd ${TMP}
LOG=${TMP}/backup.log

echo "`date -R` - Starting backup collection" > ${LOG}

# Create a VPN connection to Kasha
#/etc/init.d/vpnc stop
/etc/init.d/vpnc start

# Wait for the VPN to come up
sleep 60

echo "`date -R` - Starting SCP..." >> ${LOG}
# Copy the latest backup file across
scp -C -i ${ROOTDIR}/config/ssh/backup_user \
    backup@[IPADDRESS]:~/data/latest/* ${TMP}

SCPEXITCODE=$?
echo "`date -R` - SCP exit code ${SCPEXITCODE}" >> ${LOG}
# Close our VPN connection to prevent future race conditions
/etc/init.d/vpnc stop
echo "`date -R` - VPNC stopped" >> ${LOG}

# Catch SCP's exit code if it fails
if [[ ${SCPEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from SCP. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${SCPEXITCODE}
fi

# Find out what the filename is
FULLFILENAME=$(basename `ls ${TMP}/*.gpg`)
EXTENSION="${FULLFILENAME##*.}"
FILENAME="${FULLFILENAME%.*}"
echo "`date -R` - Downloaded dump to ${FULLFILENAME}" >> ${LOG}
echo "`date -R` - Starting decryption..." >> ${LOG}

# Verify and Decrypt the latest dump

gpg --homedir ${GPGHOME} \
    --no-verbose \
    --quiet \
    --batch \
    --no-tty \
    --output ${TMP}/${FILENAME} \
    --decrypt \
    ${TMP}/${FULLFILENAME}

GPGEXITCODE=$?
echo "`date -R` - GPG exit code ${GPGEXITCODE}" >> ${LOG}

# Check GPG exit code
if [[ ${GPGEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from GPG decryption and verification. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${GPGEXITCODE}
fi

echo "`date -R` - Decompressing archive..." >> ${LOG}
# Decompress the archive
tar -xjf ${TMP}/${FILENAME}

TARFILENAME="${FILENAME%.*}"
DIRNAME="${TARFILENAME%.*}"

echo "`date -R` - Importing into MySQL: ${TMP}/${DIRNAME}/anonymous.sql" >> ${LOG}
# Load the anonymous dump into emr/hiv/reports
cat /var/backups-kasha/bin/start.sql \
    ${TMP}/${DIRNAME}/anonymous.sql \
    /var/backups-kasha/bin/finish.sql  \
    | mysql \
    --batch \
    --socket=/var/run/mysqld/mysqld.sock \
    --user=[USER] \
    --password=[PASSWORD] \
	[DBNAME]

MYSQLEXITCODE=$?
echo "`date -R` - MySQL exit code ${MYSQLEXITCODE}" >> ${LOG}

# Check MySQL exit code
if [[ ${MYSQLEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from MySQL. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${MYSQLEXITCODE}
fi

echo "`date -R` - Importing into MySQL: ${TMP}/${DIRNAME}/piwik.sql" >> ${LOG}
# Load the Piwik dump into db
cat /var/backups-kasha/bin/start.sql \
    ${TMP}/${DIRNAME}/piwik.sql \
    /var/backups-kasha/bin/finish.sql  \
    | mysql \
    --batch \
    --socket=/var/run/mysqld/mysqld.sock \
	--user=[USER] \
	--password=[PASSWORD] \
	[DBNAME]


MYSQLEXITCODE=$?
echo "`date -R` - MySQL exit code ${MYSQLEXITCODE}" >> ${LOG}

# Check MySQL exit code
if [[ ${MYSQLEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from MySQL. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${MYSQLEXITCODE}
fi

# Copy dump to webroot
cp ${TMP}/${FULLFILENAME} $ROOTDIR/dumps

# Copy dump to S3
echo "`date -R` - Starting upload to S3..." >> ${LOG}
s3cmd -c ${S3CMDCONFIG} put ${TMP}/${FULLFILENAME} s3://${BUCKET}

S3CMDEXITCODE=$?
echo "`date -R` - s3cmd exit code ${S3CMDEXITCODE}" >> ${LOG}

if [[ ${S3CMDEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from s3cmd. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${S3CMDEXITCODE}
fi

# Run our aggregation script
echo "`date -R` - Starting aggregation..." >> ${LOG}
python /var/www/dashboard/aggregate.py

PYTHONEXITCODE=$?
echo "`date -R` - Aggregation exit code ${PYTHONEXITCODE}" >> ${LOG}

if [[ ${PYTHONEXITCODE} != 0 ]] ; then
    echo "`date -R` - ERROR: Non-zero exit code from aggregation. Abort." >> ${LOG}
    send_log
    # Remove temporary files
    rm -rf ${TMP}
    exit ${PYTHONEXITCODE}
fi


# TODO: Put the logfiles into logstash

echo "`date -R` - Backup successfully retrieved. Goodbye." >> ${LOG}

# Email notification to interested parties of success
curl -X POST "https://api.postmarkapp.com/email" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Postmark-Server-Token: [TOKEN]" \
    -d "{From: '[EMAIL]', To: '[EMAIL]', Subject: 'Backup Retrieval: Success - `date -R`', TextBody: '`cat ${LOG}`'}"

# Remove temporary files
rm -rf ${TMP}

exit 0
