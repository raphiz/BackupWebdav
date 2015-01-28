FROM ubuntu:latest

# Install rsync and davfs2
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -yqq
RUN apt-get install rsync -yqq
RUN apt-get install davfs2 -yqq

# Install devcron
RUN apt-get install python python-pip mercurial -yqq
RUN pip2 install -e hg+https://bitbucket.org/dbenamy/devcron#egg=devcron

# Mail configuration
RUN apt-get install ssmtp -yqq
RUN rm /etc/ssmtp/ssmtp.conf
RUN ln -s /backup/ssmtp.conf /etc/ssmtp/ssmtp.conf

# Append certificate configuration in davfs2 config
RUN echo "servercert    cert.pem" >> "/etc/davfs2/davfs2.conf"

# Link for the certificate to be used...
RUN ln -s /backup/cert.pem /etc/davfs2/certs/cert.pem

# Add crontab config and script
ADD backup_webdav.sh /cron/backup_webdav.sh

VOLUME /backup

CMD ["devcron.py", "/backup/crontab"]
