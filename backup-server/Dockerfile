FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends default-mysql-client cron tzdata procps && \
    rm -rf /var/lib/apt/lists/*

COPY backup.sh /backup.sh
COPY restore.sh /restore.sh
COPY crontab /etc/cron.d/backup-cron

RUN chmod +x /backup.sh /restore.sh && \
    chmod 0644 /etc/cron.d/backup-cron && \
    crontab /etc/cron.d/backup-cron

CMD printenv > /etc/environment && cron -f
