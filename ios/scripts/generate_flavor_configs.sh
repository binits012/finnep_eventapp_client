#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="${SCRIPT_DIR}/.."
FLUTTER_DIR="${IOS_DIR}/Flutter"
OUT="${FLUTTER_DIR}/FlavorValues.xcconfig"
GENERATED_XCCONFIG="${FLUTTER_DIR}/Generated.xcconfig"
DEFINE_KEYS=()
DEFINE_VALUES=()
XCODE_ENV_FILE="${IOS_DIR}/.xcode.env"

load_xcode_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
    fi

    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"

    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [[ -n "$key" ]]; then
      export "$key=$value"
    fi
  done < "$file"
}

load_xcode_env_file "$XCODE_ENV_FILE"

read_existing_value() {
  local key="$1"
  if [[ -f "$OUT" ]]; then
    local line
    line="$(grep -E "^${key} =" "$OUT" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s' "${line#*= }"
      return 0
    fi
  fi
  return 1
}

decode_dart_define() {
  local encoded="$1"
  local padded="${encoded}"
  local mod=$(( ${#padded} % 4 ))
  if [[ $mod -eq 2 ]]; then
    padded="${padded}=="
  elif [[ $mod -eq 3 ]]; then
    padded="${padded}="
  fi
  printf '%s' "$padded" | tr '_-' '/+' | base64 --decode 2>/dev/null || true
}

encode_dart_define() {
  local pair="$1"
  printf '%s' "$pair" | base64 | tr -d '\n'
}

read_dart_define() {
  local key="$1"
  if [[ ! -f "$GENERATED_XCCONFIG" ]]; then
    return 1
  fi

  local dart_defines
  dart_defines="$(grep -E '^DART_DEFINES=' "$GENERATED_XCCONFIG" | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [[ -z "$dart_defines" ]]; then
    return 1
  fi

  local encoded decoded define_key
  IFS=',' read -ra encoded_pairs <<< "$dart_defines"
  for encoded in "${encoded_pairs[@]}"; do
    decoded="$(decode_dart_define "$encoded")"
    define_key="${decoded%%=*}"
    if [[ "$define_key" == "$key" ]]; then
      printf '%s' "${decoded#*=}"
      return 0
    fi
  done
  return 1
}

read_config() {
  local key="$1"
  local default="$2"
  local value=""

  value="${!key:-}"
  if [[ -z "${value// }" ]]; then
    value="$(read_dart_define "$key" || true)"
  fi
  if [[ -z "${value// }" ]]; then
    value="$(read_existing_value "$key" || true)"
  fi
  if [[ -z "${value// }" ]]; then
    value="$default"
  fi
  printf '%s' "$value"
}

get_define_value() {
  local search_key="$1"
  local i
  for i in "${!DEFINE_KEYS[@]}"; do
    if [[ "${DEFINE_KEYS[$i]}" == "$search_key" ]]; then
      printf '%s' "${DEFINE_VALUES[$i]}"
      return 0
    fi
  done
  return 1
}

set_define_value() {
  local key="$1"
  local value="$2"
  local i

  if [[ -z "${value// }" ]]; then
    return 0
  fi

  for i in "${!DEFINE_KEYS[@]}"; do
    if [[ "${DEFINE_KEYS[$i]}" == "$key" ]]; then
      DEFINE_VALUES[$i]="$value"
      return 0
    fi
  done

  DEFINE_KEYS+=("$key")
  DEFINE_VALUES+=("$value")
}

clear_define_values() {
  DEFINE_KEYS=()
  DEFINE_VALUES=()
}

should_keep_generated_define() {
  local key="$1"
  case "$key" in
    ENV_FILE|FLUTTER_APP_FLAVOR|STRIPE_PUBLISHABLE_KEY)
      return 1
      ;;
  esac
  return 0
}

load_dart_defines_from_generated() {
  clear_define_values

  if [[ ! -f "$GENERATED_XCCONFIG" ]]; then
    return 0
  fi

  local dart_defines
  dart_defines="$(grep -E '^DART_DEFINES=' "$GENERATED_XCCONFIG" | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [[ -z "$dart_defines" ]]; then
    return 0
  fi

  local encoded decoded define_key define_value
  IFS=',' read -ra encoded_pairs <<< "$dart_defines"
  for encoded in "${encoded_pairs[@]}"; do
    [[ -z "$encoded" ]] && continue
    decoded="$(decode_dart_define "$encoded")"
    define_key="${decoded%%=*}"
    define_value="${decoded#*=}"
    if [[ -n "$define_key" ]] && should_keep_generated_define "$define_key"; then
      set_define_value "$define_key" "$define_value"
    fi
  done
}

apply_stripe_define() {
  local flavor="$1"
  local flavor_upper

  case "$flavor" in
    eu) flavor_upper="EU" ;;
    au) flavor_upper="AU" ;;
    *) flavor_upper="$flavor" ;;
  esac

  local specific_var="STRIPE_PUBLISHABLE_KEY_${flavor_upper}"
  local specific_key="${!specific_var:-}"

  if [[ -n "${specific_key// }" ]]; then
    set_define_value "STRIPE_PUBLISHABLE_KEY" "$specific_key"
  elif [[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ]]; then
    set_define_value "STRIPE_PUBLISHABLE_KEY" "$STRIPE_PUBLISHABLE_KEY"
  fi
}

write_dart_defines_xcconfig() {
  local flavor="$1"
  local env_file="$2"
  local out_file="${FLUTTER_DIR}/DartDefines-${flavor}.xcconfig"
  local encoded_pairs=()
  local i pair

  for i in "${!DEFINE_KEYS[@]}"; do
    pair="${DEFINE_KEYS[$i]}=${DEFINE_VALUES[$i]}"
    encoded_pairs+=("$(encode_dart_define "$pair")")
  done

  local joined=""
  if ((${#encoded_pairs[@]} > 0)); then
    local IFS=,
    joined="${encoded_pairs[*]}"
  fi

  cat > "$out_file" <<EOF
// Generated by ios/scripts/generate_flavor_configs.sh — do not edit manually.
DART_DEFINES = ${joined}
EOF

  echo "Generated ${out_file}"
  echo "  ENV_FILE=${env_file}"
  echo "  FLUTTER_APP_FLAVOR=${flavor}"
  if get_define_value "STRIPE_PUBLISHABLE_KEY" >/dev/null; then
    echo "  STRIPE_PUBLISHABLE_KEY=(set from ios/.xcode.env)"
  else
    echo "  STRIPE_PUBLISHABLE_KEY=(loaded from bundled ${env_file})"
  fi
}

AU_BUNDLE_ID="$(read_config AU_APPLICATION_ID 'com.finnep.okazzo.au')"
EU_BUNDLE_ID="$(read_config EU_APPLICATION_ID 'com.finnep.okazzo.eu')"
AU_DISPLAY_NAME="$(read_config AU_APP_NAME 'Okazzo AUS')"
EU_DISPLAY_NAME="$(read_config EU_APP_NAME 'Okazzo EU')"

cat > "$OUT" <<EOF
// Generated by ios/scripts/generate_flavor_configs.sh — do not edit manually.
AU_BUNDLE_ID = ${AU_BUNDLE_ID}
EU_BUNDLE_ID = ${EU_BUNDLE_ID}
AU_DISPLAY_NAME = ${AU_DISPLAY_NAME}
EU_DISPLAY_NAME = ${EU_DISPLAY_NAME}
EOF

echo "Generated ${OUT}"
echo "  AU_BUNDLE_ID=${AU_BUNDLE_ID}"
echo "  EU_BUNDLE_ID=${EU_BUNDLE_ID}"
echo "  AU_DISPLAY_NAME=${AU_DISPLAY_NAME}"
echo "  EU_DISPLAY_NAME=${EU_DISPLAY_NAME}"

load_dart_defines_from_generated
apply_stripe_define "eu"
set_define_value "ENV_FILE" ".env.eu"
set_define_value "FLUTTER_APP_FLAVOR" "eu"
write_dart_defines_xcconfig "eu" ".env.eu"

load_dart_defines_from_generated
apply_stripe_define "au"
set_define_value "ENV_FILE" ".env.au"
set_define_value "FLUTTER_APP_FLAVOR" "au"
write_dart_defines_xcconfig "au" ".env.au"
