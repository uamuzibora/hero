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
ENCRYPT_KEYID=0xEEABA323 # UB Ops team i.e. for full backup for disaster recovery
SIGN_KEYID=0x7FCE6178 # Kasha server signing only key
ANON_ENCRYPT_KEYID=0x7496054D # UB Anonymous Data i.e. for the logs and anonymised dump

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
    --add-drop-table \
    --skip-extended-insert \
    --order-by-primary \
    --default-character-set=latin1 \
    openmrs > ${TMP}/openmrs.sql

# Make an anonymous copy of the dump
# Make a new temporary database and restore the dump
mysql -u ${MYSQLUSER} --password=${MYSQLPASS} anonymiser \
    -e "SET foreign_key_checks = 0; SOURCE ${TMP}/openmrs.sql; SET foreign_key_checks = 1;"

# Anonymise data in the temporary database
# Anonymise the following fields:
    # 1. Delete UPN: DELETE FROM patient_identifier;
    # 2. Change Forename: person_name.given_name
    # 4. Change Surname: person_name.family_name
    # 5. Delete:
          # person_name.middle_name
          # person_name.prefix
          # person_name.family_name_prefix
          # person_name.family_name2
          # person_name.family_name_suffix
          # person_name.degree
    # 6. Round DoB to nearest month
    # 7. Delete 1st line of address
    # 8. Delete telephone number
    # 9. Delete:
          # Treatment supporter name
          # Treatment supporter phone
          # Treatment supporter address
mysql -u ${MYSQLUSER} --password=${MYSQLPASS} anonymiser \
    -e "SET foreign_key_checks = 0;
        DELETE FROM patient_identifier;
        UPDATE person_name SET given_name = 'Unknown',
                              family_name = 'Unknown';
        UPDATE person_name SET prefix = NULL,
                              middle_name = NULL,
                              family_name_prefix = NULL,
                              family_name2 = NULL,
                              family_name_suffix = NULL,
                              degree = NULL;
        UPDATE person SET birthdate = CONCAT(YEAR(birthdate),'-',LPAD(MONTH(birthdate),2,'00'),'-','01');
        UPDATE person_address SET address1 = NULL,
                                  latitude = NULL,
                                  longitude = NULL;
        DELETE FROM person_attribute WHERE person_attribute_type_id = 8;
        DELETE FROM obs WHERE concept_id = 6252;
        DELETE FROM obs WHERE concept_id = 6254;
        DELETE FROM obs WHERE concept_id = 6255;
        SET foreign_key_checks = 1;"

# Dump the anonymised database
mysqldump -u ${MYSQLUSER} --password=${MYSQLPASS} \
    --compact \
    --single-transaction \
    --add-drop-table \
    --skip-extended-insert \
    --order-by-primary \
    --default-character-set=latin1 \
    anonymiser > ${TMP}/anonymous.sql


# Create a file containing the timestamp
echo ${TIMESTAMP} > ${TMP}/TIMESTAMP

# Move backups into a timestamped directory, ready for processing
mkdir ${TMP}/${TIMESTAMP}
mv ${TMP}/openmrs.sql ${TMP}/${TIMESTAMP}
mv ${TMP}/anonymous.sql ${TMP}/${TIMESTAMP}
mv ${TMP}/TIMESTAMP ${TMP}/${TIMESTAMP}

# Compress the full backup
bzip2 -z -9 ${TMP}/${TIMESTAMP}/openmrs.sql

# Encrypt and sign the full backup
gpg --homedir ${GPGHOME} \
    --no-verbose \
    --quiet \
    --batch \
    --no-tty \
    --output ${TMP}/${TIMESTAMP}/openmrs.sql.bz2.gpg \
    --encrypt \
    --recipient ${ENCRYPT_KEYID} \
    --sign \
    --local-user ${SIGN_KEYID} \
    --always-trust \
    ${TMP}/${TIMESTAMP}/openmrs.sql.bz2

# Remove the unencrypted full backup dump from the timestamp dir
rm ${TMP}/${TIMESTAMP}/openmrs.sql.bz2


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
    --recipient ${ANON_ENCRYPT_KEYID} \
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
