## Backup scripts for Uamuzi Bora

### Getting backup-server.sh to work for log files

Make sure that `sudoers` has the following line **at the bottom of it** to allow the `backup` user to use `tar` to archive log files in `/var/log` when creating it's backup archive:

`backup ALL=NOPASSWD: /bin/tar`