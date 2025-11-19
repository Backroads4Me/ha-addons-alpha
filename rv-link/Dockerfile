ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install dependencies
# can-utils, mosquitto-clients, python3: For CAN-MQTT Bridge
# git, curl, jq: For Orchestrator
RUN apk add --no-cache \
    git \
    curl \
    jq \
    bash \
    can-utils \
    mosquitto-clients \
    python3 \
    iproute2 \
    procps \
    coreutils \
    openssl \
    ca-certificates

# Bundle the Node-RED Project
# We clone it to /opt/rv-link-project so it's available in the image
RUN git clone https://github.com/Backroads4Me/rv-link-node-red /opt/rv-link-project

# Copy run script and make it executable
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
