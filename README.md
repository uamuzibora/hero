# hero - backup scripts for Uamuzi Bora

## Overview

Uamuzi Bora runs on a server airgapped from the Internet on a private network. Client machines connect to the web application over a wireless network.

To facilitate regular, redundant, secure backups, `backup-server.sh` is a script that is run daily on the server as a cronjob. It dumps the database, compresses it, encrypts and signs the dump with GnuPG. It also clears any backups fromt the server older than a year. More recently, it now includes the contents of `/var/log` for diagnostics.

The private key for decrypting the dumps is not kept in-country.

`backup-client.sh` is a script that is run daily on our public facing website as a cronjob. It establishes an SCP connection to our server in country over a Cisco IPsec VPN and copies the latest backup file. Once downloaded, it decrypts the anonymised OpenMRS and Piwik database dumps with GPG and imports them into MySQL. It also uploads them to an S3 bucket for further redundancy. Further, it runs a component of [dashboard](https://github.com/uamuzibora/dashboard), `aggregate.py`, which imports aggregata data from the newly imported MySQL db to a MongoDB db.

## backup-server.sh

Run daily as the **backup** system user.

Expects to find the script at `/usr/local/bin/backup-server.sh`.

Expects the following directory structure at `/backup`:

	.
	├── config
	│   ├── gnupg
	│   |   ├── pubring.gpg
	│   |   ├── secring.gpg
	│   |   └── trustdb.gpg
	|   └── ssh
	|       └── authorized_keys
	├── data
	│   ├── [lots of dumps]
	│   └── latest
	|       └── [copy of latest dump]
	└── tmp

### Getting backup-server.sh to work for log files

Make sure that `sudoers` has the following line **at the bottom of it** to allow the `backup` user to use `tar` to archive log files in `/var/log` when creating it's backup archive:

`backup ALL=NOPASSWD: /bin/tar`


## backup-client.sh

Run daily at 02:10 UTC as **root** from root's crontab.

### Prerequisites

Lots - this is all custom code for our unique use case. Broadly however:
 * SSH with passwordless public key for a limited user (setup on Kasha to only permit SCP)
 * vpnc configured to run as a daemon
 * GnuPG with (passwordless) private key to decrypt
 * s3cmd
 * cron - if you want to run this regularly

### Directory structure

Our current configuration on Skunkworks (our receiving server) is like this (at `/var/backups-kasha`):

	.
	├── bin
	│   ├── backupsRobot.sh
	│   ├── finish.sql
	│   └── start.sql
	├── config
	│   ├── gnupg
	│   │   ├── pubring.gpg
	│   │   ├── secring.gpg
	│   │   └── trustdb.gpg
	│   ├── s3cmd.config
	│   └── ssh
	│       └── backup_user
	├── dumps
	├── tmp
	└── webroot
	    └── dumps -> /symlink/path/to/dumps


## Deprecated components

`backup-sync.sh` is a script that runs as a cronjob on netbook client machines. It connects to the server over SSH and uses rsync to copy the most recent encrypted dump onto the netbook. This ensures that there are several copies of the most recent backup on the netbook clients for redundancy.