ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install dependencies
RUN apk add --no-cache git curl jq bash

# Copy run script and make it executable
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Copy Node-RED setup script and make it executable
COPY setup-node-red.sh /setup-node-red.sh
RUN chmod +x /setup-node-red.sh

CMD ["/run.sh"]
