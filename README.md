## Backup scripts for Uamuzi Bora

### Overview

Uamuzi Bora runs on a server airgapped from the Internet on a private network. Client machines connect to the web application over a wireless network.

To facilitate regular, redundant, secure backups, `backup-server.sh` is a script that is run daily on the server as a cronjob. It dumps the database, compresses it, encrypts and signs the dump with GnuPG. It also clears any backups fromt the server older than a year. More recently, it now includes the contents of `/var/log` for diagnostics.

`backup-sync.sh` is the other half of the script that runs as a cronjob on netbook client machines. It connects to the server over SSH and uses rsync to copy the most recent encrypted dump onto the netbook. This ensures that there are several copies of the most recent backup on the netbook clients for redundancy.

The private key for decrypting the dumps is not kept in-country.

### Getting backup-server.sh to work for log files

Make sure that `sudoers` has the following line **at the bottom of it** to allow the `backup` user to use `tar` to archive log files in `/var/log` when creating it's backup archive:

`backup ALL=NOPASSWD: /bin/tar`