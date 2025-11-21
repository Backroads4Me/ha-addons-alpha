ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install dependencies
# git, curl, jq, bash: For Orchestrator
# mosquitto-clients: For MQTT connectivity verification
RUN apk add --no-cache \
    git \
    curl \
    jq \
    bash \
    rsync \
    mosquitto-clients \
    procps \
    coreutils \
    openssl \
    ca-certificates

# Bundle the Node-RED Project
# Always pulls latest from main branch
RUN git clone --depth 1 https://github.com/Backroads4Me/rv-link-node-red /opt/rv-link-project && \
    rm -rf /opt/rv-link-project/.git && \
    rm -f /opt/rv-link-project/.gitignore /opt/rv-link-project/.gitattributes /opt/rv-link-project/flows_cred.json

# Copy run script and make it executable
COPY run.sh /run.sh
COPY settings.js /settings.js
RUN chmod a+x /run.sh

CMD ["/run.sh"]
