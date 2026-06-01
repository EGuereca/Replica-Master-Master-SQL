FROM alpine:3.18

RUN apk update && \
    apk add --no-cache mariadb-client bash tzdata

COPY backup.sh /backup.sh
COPY restore.sh /restore.sh
COPY crontab /etc/crontabs/root

RUN chmod +x /backup.sh /restore.sh

CMD ["crond", "-f", "-d", "8"]
