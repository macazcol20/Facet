# Containerfile
FROM eclipse-temurin:17-jre-jammy

# Non-root user + dirs
RUN useradd -r -u 10001 -g root appuser && \
    mkdir -p /app /app/config /app/lib /var/logs/springboot && \
    chown -R appuser:root /app /var/logs/springboot && \
    chmod -R 775 /app /var/logs/springboot

WORKDIR /app

# Copy artifact + optional runtime config/libs
COPY build/networkx-pricer-facets.war /app/app.war
COPY config/ /app/config/
COPY lib/ /app/lib/

# Defaults (override with env file or podman -e)
ENV SERVER_PORT=9080 \
    LOG_DIR=/var/logs/springboot \
    JAVA_XMS=256m \
    JAVA_XMX=1024m \
    LOADER_PATH="WEB-INF/lib-provided,WEB-INF/lib,WEB-INF/classes,file:/app/lib/,file:/app/config/" \
    JASYPT_ENCRYPTOR_PASSWORD=""

EXPOSE 9080
USER appuser

# Simple TCP healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -lc "exec 3<>/dev/tcp/127.0.0.1/${SERVER_PORT} && exit 0 || exit 1"

ENTRYPOINT ["bash","-lc", "\
  exec java \
    -Xms${JAVA_XMS} -Xmx${JAVA_XMX} \
    -Djasypt.encryptor.password=${JASYPT_ENCRYPTOR_PASSWORD} \
    -Dcom.trizetto.networkx.logDirectory=${LOG_DIR} \
    -Dserver.port=${SERVER_PORT} \
    -Dloader.path=${LOADER_PATH} \
    -cp /app/app.war \
    org.springframework.boot.loader.launch.PropertiesLauncher \
"]

## .env
# JVM & app
JAVA_XMS=256m
JAVA_XMX=1024m
SERVER_PORT=9080
JASYPT_ENCRYPTOR_PASSWORD=REPLACE_ME

# DB (from application.properties)
SPRING_DATASOURCE_DRIVERCLASSNAME=com.microsoft.sqlserver.jdbc.SQLServerDriver
SPRING_DATASOURCE_URL=jdbc:sqlserver://<sql-host>:1433;databaseName=fabcndv2;trustServerCertificate=true
SPRING_DATASOURCE_USERNAME=facetsnw
SPRING_DATASOURCE_PASSWORD=REPLACE_ME

# ActiveMQ (if using external broker; comment if not)
SPRING_ACTIVEMQ_BROKER_URL=tcp://<activemq-host>:61616
SPRING_ACTIVEMQ_IN_MEMORY=true
### build
# create a local logs dir so logs persist
mkdir -p ./logs

# run
podman run -d --name facets \
  --env-file ./.env \
  -p 9080:9080 \
  -v ./config:/app/config:ro,Z \
  -v ./lib:/app/lib:ro,Z \
  -v ./logs:/var/logs/springboot:Z \
  localhost/facets:local



