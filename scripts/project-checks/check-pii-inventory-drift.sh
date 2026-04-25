#!/usr/bin/env bash
# Drift validator: every external sub-processor SDK the application
# instantiates must be declared in {project-docs}/pii-inventory.md
# (per gdpr-pii.md GD-011).
#
# A sub-processor is detected by the namespaced SDK class import. The
# KNOWN_PROVIDERS list below is curated; projects extend it as new
# providers are introduced.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

if [ -n "${INVENTORY_PATH:-}" ]; then
  INVENTORY="$INVENTORY_PATH"
elif [ -f ai-standards/.workspace-config-path ]; then
  DOCS_DIR="$(cat ai-standards/.workspace-config-path)"
  INVENTORY="$DOCS_DIR/pii-inventory.md"
else
  printf "ERROR: cannot resolve pii-inventory.md path (no INVENTORY_PATH and no ai-standards/.workspace-config-path)\n" >&2
  exit 2
fi

if [ ! -f "$INVENTORY" ]; then
  printf "ERROR: %s does not exist\n" "$INVENTORY" >&2
  exit 2
fi

# Each entry: provider_name|grep_pattern. The provider_name is what the
# inventory is expected to mention; the pattern matches the SDK import or
# obvious instantiation. Patterns are intentionally loose — false positives
# are cheaper than false negatives here.
declare -a KNOWN_PROVIDERS=(
  "stripe|Stripe\\\\StripeClient|use Stripe\\\\"
  "openai|OpenAI\\\\Client|use OpenAI\\\\"
  "anthropic|Anthropic\\\\Sdk|use Anthropic\\\\"
  "gemini|Gemini\\\\Client|use Gemini\\\\"
  "mistral|Mistral\\\\Client|use Mistral\\\\"
  "sendgrid|SendGrid\\\\Mail|use SendGrid\\\\"
  "twilio|Twilio\\\\Rest|use Twilio\\\\"
  "mailgun|Mailgun\\\\Mailgun|use Mailgun\\\\"
  "signaturit|Signaturit\\\\Sdk|use Signaturit\\\\"
  "docusign|DocuSign\\\\eSign|use DocuSign\\\\"
  "yousign|Yousign\\\\|use Yousign\\\\"
  "adobe-sign|Adobe\\\\Sign|use Adobe\\\\Sign"
  "mapbox|Mapbox\\\\|use Mapbox\\\\"
  "google-maps|GoogleMaps\\\\|GoogleMapsClient"
  "aws-s3|Aws\\\\S3\\\\S3Client|use Aws\\\\S3\\\\"
  "minio|Minio\\\\Client|use Minio\\\\"
  "launchdarkly|LaunchDarkly\\\\|use LaunchDarkly\\\\"
  "configcat|ConfigCat\\\\|use ConfigCat\\\\"
  "statsig|Statsig\\\\|use Statsig\\\\"
)

src_dirs=()
[ -d src ] && src_dirs+=(src)
[ -d app ] && src_dirs+=(app)
if [ ${#src_dirs[@]} -eq 0 ]; then
  printf "WARN: no source directories found (src/, app/) — nothing to check\n" >&2
  exit 0
fi

inventory_lc=$(tr '[:upper:]' '[:lower:]' < "$INVENTORY")
missing_any=0

for entry in "${KNOWN_PROVIDERS[@]}"; do
  provider="${entry%%|*}"
  patterns="${entry#*|}"
  pattern_a="${patterns%%|*}"
  pattern_b="${patterns#*|}"

  found=$(grep -rEl "($pattern_a|$pattern_b)" "${src_dirs[@]}" 2>/dev/null | head -5 || true)
  [ -z "$found" ] && continue

  # Provider is in code; assert it appears in the inventory (case-insensitive).
  if ! printf "%s" "$inventory_lc" | grep -q "$provider"; then
    if [ $missing_any -eq 0 ]; then
      printf "ERROR: providers used in code but missing from %s:\n" "$INVENTORY" >&2
    fi
    missing_any=1
    printf "  - %s\n" "$provider" >&2
    while IFS= read -r f; do
      printf "      %s\n" "$f" >&2
    done <<< "$found"
  fi
done

if [ $missing_any -eq 1 ]; then
  printf "\nFix: add a sub-processor entry for each missing provider in %s (per gdpr-pii.md GD-011), naming the affected fields and the provider's region.\n" "$INVENTORY" >&2
  exit 1
fi

printf "PII inventory: OK (no sub-processor drift)\n"
exit 0
