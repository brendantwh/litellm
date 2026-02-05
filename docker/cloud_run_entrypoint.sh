#!/bin/sh
set -e

# Cloud Run entrypoint with remote config and handler fetching support
#
# Environment variables:
#   CONFIG_DIR          - Directory to store fetched files (default: /app/config)
#
#   Config fetching (use any of these patterns):
#   LITELLM_CONFIG_URL  - URL to fetch main config.yaml from
#   CONFIG_URL_*        - Additional config files (e.g., CONFIG_URL_TEAMS, CONFIG_URL_MODELS)
#
#   Custom handler fetching:
#   HANDLER_URL_*       - Python handler files (e.g., HANDLER_URL_CUSTOM=https://.../custom_handler.py)
#
#   AUTH_HEADER         - Optional auth header for all fetches (e.g., "Authorization: Bearer token")
#
# Example usage:
#   docker run \
#     -e LITELLM_CONFIG_URL="https://storage.googleapis.com/bucket/config.yaml" \
#     -e CONFIG_URL_TEAMS="https://storage.googleapis.com/bucket/teams.yaml" \
#     -e HANDLER_URL_CUSTOM="https://storage.googleapis.com/bucket/custom_handler.py" \
#     litellm-cloud-run --config /app/config/config.yaml
#
# Your config.yaml can reference:
#   include:
#     - /app/config/teams.yaml
#   litellm_settings:
#     custom_provider_map:
#       - provider: my-custom-llm
#         custom_handler: custom_handler.my_custom_llm

CONFIG_DIR="${CONFIG_DIR:-/app/config}"

# Create config directory
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

# Helper function to fetch a file
fetch_file() {
    url="$1"
    dest="$2"
    echo "Fetching $url -> $dest"
    if [ -n "$AUTH_HEADER" ]; then
        curl -fsSL -H "$AUTH_HEADER" "$url" -o "$dest"
    else
        curl -fsSL "$url" -o "$dest"
    fi
}

# Fetch main config if URL is specified
if [ -n "$LITELLM_CONFIG_URL" ]; then
    fetch_file "$LITELLM_CONFIG_URL" "$CONFIG_DIR/config.yaml"
fi

# Fetch additional config files (CONFIG_URL_*)
env | grep '^CONFIG_URL_' | while IFS='=' read -r name url; do
    if [ -n "$url" ]; then
        # Extract suffix (e.g., CONFIG_URL_TEAMS -> teams)
        suffix=$(echo "$name" | sed 's/^CONFIG_URL_//' | tr '[:upper:]' '[:lower:]')
        filename="${suffix}.yaml"
        fetch_file "$url" "$CONFIG_DIR/$filename"
    fi
done

# Fetch custom handler files (HANDLER_URL_*)
env | grep '^HANDLER_URL_' | while IFS='=' read -r name url; do
    if [ -n "$url" ]; then
        # Extract suffix (e.g., HANDLER_URL_CUSTOM -> custom_handler.py)
        suffix=$(echo "$name" | sed 's/^HANDLER_URL_//' | tr '[:upper:]' '[:lower:]')
        filename="${suffix}_handler.py"
        fetch_file "$url" "$CONFIG_DIR/$filename"
    fi
done

# List fetched files for debugging
if [ -d "$CONFIG_DIR" ] && [ "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]; then
    echo "Files in $CONFIG_DIR:"
    ls -la "$CONFIG_DIR"
fi

# Add config dir to Python path so custom handlers can be imported
export PYTHONPATH="${CONFIG_DIR}:${PYTHONPATH:-}"

# Call the original entrypoint
exec /app/docker/prod_entrypoint.sh "$@"
