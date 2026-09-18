#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# CONFIGURATION & CONTROL FLAGS
# ==============================================================================
REQUEST_QUOTA_INCREASE=false  # set to true or false
SERVICE_NAME="compute.googleapis.com"
QUOTA_ID_C3_VCPU="C3-CPUS-per-project-region"
CONFIG_FILE="config.yaml"   

# ==============================================================================
# HELPER FUNCTIONS (Sanitizadas contra \r de Windows)
# ==============================================================================

get_yaml_value() {
  local key=$1
  if command -v yq &> /dev/null; then
    yq eval ".${key} // \"\"" "$CONFIG_FILE" | tr -d '\r' | xargs
  else
    awk -F ':' -v k="$key" '$1 ~ "^[[:space:]]*"k"$" {gsub(/[ "\r]/, "", $2); print $2}' "$CONFIG_FILE"
  fi
}

get_nested_yaml_value() {
  local parent=$1
  local child=$2
  if command -v yq &> /dev/null; then
    yq eval ".${parent}.${child} // 0" "$CONFIG_FILE" | tr -d '\r' | xargs
  else
    awk -v p="$parent" -v c="$child" '
      $0 ~ "^"p":" { in_parent=1; next }
      in_parent && /^[a-zA-Z0-9_-]+:/ { in_parent=0 }
      in_parent && $1 ~ "^[[:space:]]*"c":" { gsub(/[ "\r]/, "", $2); print $2 }
    ' "$CONFIG_FILE"
  fi
}

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

echo "================================================================================"
echo "GCP QUOTA AUTOMATION - VCPU METRIC CHECK (Pure Bash + gcloud CLI)"
echo "================================================================================"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Configuration file not found at: $CONFIG_FILE"
  exit 1
fi

# 1. Read values from config.yml
PROJECT_ID=$(get_yaml_value "project_id")
REGION=$(get_yaml_value "region")
CONTACT_EMAIL=$(get_yaml_value "contact_email")

WORKERS_RAW=$(get_nested_yaml_value "spark" "workers")
CPU_PER_WORKER_RAW=$(get_nested_yaml_value "spark" "cpu_per_worker")

# Limpieza estricta para asegurar que solo contengan dígitos numéricos
WORKERS=$(echo "$WORKERS_RAW" | tr -cd '0-9')
CPU_PER_WORKER=$(echo "$CPU_PER_WORKER_RAW" | tr -cd '0-9')

WORKERS=${WORKERS:-0}
CPU_PER_WORKER=${CPU_PER_WORKER:-0}

# 2. Calculate required vCPUs
REQUIRED_CPUS=$(( WORKERS * CPU_PER_WORKER ))

echo "Project ID    : ${PROJECT_ID}"
echo "Region        : ${REGION}"
echo "Contact Email : ${CONTACT_EMAIL}"
echo "Flag Status   : REQUEST_QUOTA_INCREASE = ${REQUEST_QUOTA_INCREASE}"
echo "--------------------------------------------------------------------------------"
echo "[CALCULATION] Workers: ${WORKERS} | CPU/Worker: ${CPU_PER_WORKER} => Total Required vCPUs: ${REQUIRED_CPUS}"
echo "--------------------------------------------------------------------------------"

# ==============================================================================
# 3. Fetch current quota limit using Cloud Quotas REST API via curl + gcloud token
# ==============================================================================
echo "[QUERY] Fetching quota details for '${QUOTA_ID_C3_VCPU}'..."

ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "[ABORT] Could not get gcloud access token. Run 'gcloud auth login' or 'gcloud auth application-default login'."
  exit 1
fi

QUOTA_URL="https://cloudquotas.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/services/${SERVICE_NAME}/quotaInfos/${QUOTA_ID_C3_VCPU}"

QUOTA_INFO=$(curl -s -X GET "$QUOTA_URL" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json")

if echo "$QUOTA_INFO" | grep -q '"error"'; then
  echo "[ABORT] API Error while fetching quota info:"
  echo "$QUOTA_INFO" | jq -r '.error.message // .error'
  exit 1
fi

# 4. Extract metric name and region quota limit using jq
METRIC_NAME=$(echo "$QUOTA_INFO" | jq -r '.metricDisplayName // ""')

CURRENT_LIMIT=$(echo "$QUOTA_INFO" | jq -r --arg REGION "$REGION" '
  .dimensionsInfos[]? 
  | select(.dimensions.region == $REGION or (.applicableLocations[]? == $REGION)) 
  | (.details.value // .quotaBuckets[]?.effectiveLimit // 0)
' | head -n 1)

CURRENT_LIMIT=$(echo "${CURRENT_LIMIT:-0}" | tr -cd '0-9')

echo "Metric Display Name : ${METRIC_NAME}"
echo "Current Limit in GCP (${REGION}): ${CURRENT_LIMIT}"
echo "Calculated Target   : ${REQUIRED_CPUS}"
echo "--------------------------------------------------------------------------------"

# 5. Compare current vs required quota
if (( CURRENT_LIMIT >= REQUIRED_CPUS )); then
  echo "[STATUS] OK - Current quota limit is sufficient for the workload."
  exit 0
fi

echo "[WARNING] Current limit (${CURRENT_LIMIT}) is lower than required (${REQUIRED_CPUS})."

# ==============================================================================
# 6. Submit quota preference request via REST API if flag is enabled
# ==============================================================================
if [[ "$REQUEST_QUOTA_INCREASE" == "true" ]]; then
  CLEAN_QUOTA_ID=$(echo "$QUOTA_ID_C3_VCPU" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  PREFERENCE_ID="inc-${CLEAN_QUOTA_ID:0:10}-${REQUIRED_CPUS}"

  echo "[ACTION] Submitting quota preference request for ${REQUIRED_CPUS} units in '${REGION}'..."

  PREF_URL="https://cloudquotas.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/quotaPreferences?quotaPreferenceId=${PREFERENCE_ID}"

  PAYLOAD=$(cat <<EOF
{
  "service": "${SERVICE_NAME}",
  "quotaId": "${QUOTA_ID_C3_VCPU}",
  "contactEmail": "${CONTACT_EMAIL}",
  "dimensions": {
    "region": "${REGION}"
  },
  "quotaConfig": {
    "preferredValue": ${REQUIRED_CPUS}
  }
}
EOF
)

  RESPONSE=$(curl -s -X POST "$PREF_URL" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  echo "[SUCCESS] Response from GCP Cloud Quotas API:"
  echo "$RESPONSE" | jq .
else
  echo "[NOTICE] REQUEST_QUOTA_INCREASE is set to false."
  echo "         No request was submitted to GCP. Set flag to true to auto-request."
fi