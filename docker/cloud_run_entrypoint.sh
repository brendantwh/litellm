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
#   Backblaze B2 auth (optional):
#   BACKBLAZE_KEY_ID / B2_KEY_ID                       - Backblaze application key ID
#   BACKBLAZE_APPLICATION_KEY / B2_APPLICATION_KEY     - Backblaze application key
#   BACKBLAZE_AUTH_URL                                 - Override auth endpoint
#                                                        (default: https://api.backblazeb2.com/b2api/v2/b2_authorize_account)
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
BACKBLAZE_AUTH_URL="${BACKBLAZE_AUTH_URL:-https://api.backblazeb2.com/b2api/v2/b2_authorize_account}"
BACKBLAZE_KEY_ID="${BACKBLAZE_KEY_ID:-${B2_KEY_ID:-}}"
BACKBLAZE_APPLICATION_KEY="${BACKBLAZE_APPLICATION_KEY:-${B2_APPLICATION_KEY:-}}"
BACKBLAZE_AUTH_HEADER=""
BACKBLAZE_DOWNLOAD_URL=""

# Create config directory
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

# Extract string field from a small JSON payload (no jq dependency)
extract_json_field() {
    json_payload="$1"
    field_name="$2"
    printf '%s' "$json_payload" | tr -d '\n' | sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# Determine whether URL is likely a Backblaze B2 file URL
is_backblaze_url() {
    url="$1"

    if [ -n "$BACKBLAZE_DOWNLOAD_URL" ] && [ "${url#"$BACKBLAZE_DOWNLOAD_URL"/}" != "$url" ]; then
        return 0
    fi

    case "$url" in
        *backblazeb2.com/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Optionally authorize with Backblaze B2 and reuse the auth token for file downloads
if [ -n "$BACKBLAZE_KEY_ID" ] || [ -n "$BACKBLAZE_APPLICATION_KEY" ]; then
    if [ -z "$BACKBLAZE_KEY_ID" ] || [ -z "$BACKBLAZE_APPLICATION_KEY" ]; then
        echo "Both BACKBLAZE_KEY_ID (or B2_KEY_ID) and BACKBLAZE_APPLICATION_KEY (or B2_APPLICATION_KEY) must be set" >&2
        exit 1
    fi

    echo "Authorizing with Backblaze B2..."
    backblaze_auth_response=$(curl -fsSL -u "${BACKBLAZE_KEY_ID}:${BACKBLAZE_APPLICATION_KEY}" "$BACKBLAZE_AUTH_URL")
    backblaze_auth_token=$(extract_json_field "$backblaze_auth_response" "authorizationToken")
    BACKBLAZE_DOWNLOAD_URL=$(extract_json_field "$backblaze_auth_response" "downloadUrl")

    if [ -z "$backblaze_auth_token" ]; then
        echo "Failed to read Backblaze authorizationToken from auth response" >&2
        exit 1
    fi

    BACKBLAZE_AUTH_HEADER="Authorization: $backblaze_auth_token"
fi

# Helper function to fetch a file
fetch_file() {
    url="$1"
    dest="$2"
    echo "Fetching $url -> $dest"
    if [ -n "$AUTH_HEADER" ]; then
        curl -fsSL -H "$AUTH_HEADER" "$url" -o "$dest"
    elif [ -n "$BACKBLAZE_AUTH_HEADER" ] && is_backblaze_url "$url"; then
        curl -fsSL -H "$BACKBLAZE_AUTH_HEADER" "$url" -o "$dest"
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
