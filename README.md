# Webdav Backup

This script aims to perform backups from webdav shares.

For details and installation instructions go to the project website:
https://raphiz.github.io/BackupWebdav/

# Docker usage:
If you use this via docker, the `/backup` volume *must* contain the following files:
* `crontab`, a crontab configuration to be used (See https://en.wikipedia.org/wiki/Cron)
* `cert.pem` the SSL certificate which is used on the server side
* `ssmtp.conf` the config for ssmtp used for SMTP authentication (if emails shall be sent)

To run a job with a specific configuration file you can use the `BACKUP_WEBDAV_CONFIGURATION_FILE`
variable.

```
* * * * *  BACKUP_WEBDAV_CONFIGURATION_FILE=/backup/mirror.cfg /cron/backup_webdav.sh
```

Alternatively, you can feed all variables via environment variables into docker.

*Note that the container must run in privileged mode because fuse is used.*
