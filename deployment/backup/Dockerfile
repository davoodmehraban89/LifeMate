FROM postgres:16-alpine
RUN apk add --no-cache bash
COPY backend/scripts/backup.sh backend/scripts/restore.sh /opt/lifeguide/
COPY deployment/backup/entrypoint.sh deployment/backup/run-backup.sh /opt/lifeguide/
RUN chmod +x /opt/lifeguide/*.sh
ENTRYPOINT ["/opt/lifeguide/entrypoint.sh"]
