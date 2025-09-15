#!/usr/bin/env zsh
#!/usr/bin/env zsh

# Candidate filenames for actionfile
actions_candidate_files=("Actionfile.md" "Actfile.md" "README.md")

# Find the actionfile in a given directory
actions_find_actionfile() {
  local dir="$1"
  for fname in "${actions_candidate_files[@]}"; do
    if [[ -f "$dir/$fname" ]]; then
      echo "$dir/$fname"
      return 0
    fi
  done
  return 1
}

# Extract all markdown sections mapping each header key to its body
actions_extract_action_sections() {
  local file="$1"
  awk '
    BEGIN {in_code=0; keys=""; body=""}
    /^### / {
      # Output previous section for ALL keys
      if (body != "" && keys != "") {
        n = split(keys, arr, /[[:space:]]+/)
        for (i=1; i<=n; i++)
          printf("SECTIONSEP%sKEYSEP%sBODYSEP%sBODYEND\n", arr[i], body, "");
      }
      keys = substr($0, 5);
      body = "";
      in_code = 0;
      next;
    }
    /^```sh/ {in_code=1; next}
    in_code && /^```/ {in_code=0; next}
    in_code {body = body $0 "\n"}
    END {
      # Output last section
      if (body != "" && keys != "") {
        n = split(keys, arr, /[[:space:]]+/)
        for (i=1; i<=n; i++)
          printf("SECTIONSEP%sKEYSEP%sBODYSEP%sBODYEND\n", arr[i], body, "");
      }
    }
  ' "$file"
}

# Extract default section, only one allowed
actions_extract_default_section() {
  local file="$1"
  awk '
    BEGIN {found=0}
    /^### default[ ]+/ {
      if (found==0) {
        found=1
        action=substr($0, 13)
      }
    }
    found && /^```sh/ {in_code=1; next}
    found && in_code && /^```/ {exit}
    found && in_code {print}
  ' "$file"
}

# Extract config and vars
actions_extract_ini_vars() {
  local file="$1"
  awk '
    BEGIN {section=""}
    /^\[([A-Za-z0-9_]+)\]$/ {match($0, /^\[([A-Za-z0-9_]+)\]$/, m); section=toupper(m[1]); next}
    /^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*"([^"]*)"/ {
      match($0, /^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*"([^"]*)"/, m);
      key=toupper(m[1]); value=m[2];
      printf "export %s_%s=\"%s\"\n", section, key, value;
      next
    }
    /^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*([^"]\S*)[[:space:]]*$/ {
      match($0, /^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*([^"]\S*)[[:space:]]*$/, m);
      key=toupper(m[1]); value=m[2];
      printf "export %s_%s=\"%s\"\n", section, key, value;
      next
    }
  ' "$file"
}

actions_extract_vars_block() {
  local file="$1"
  awk '
    BEGIN {in_vars=0}
    /^### vars/ {in_vars=1; next}
    in_vars && /^```sh/ {in_code=1; next}
    in_vars && in_code && /^```/ {exit}
    in_vars && in_code {print}
  ' "$file"
}

# Platform detection (for context fallback)
actions_detect_platform() {
  if [[ -f /etc/os-release ]]; then
    local os_id=$(awk -F= '$1=="ID"{print $2}' /etc/os-release)
    echo $os_id
  fi
}

action() {
  local shell="${ACTIONFILE_SHELL:-bash}"
  local search_dir=""
  local act=""
  local ctx=""
  local file=""
  local interactive=0
  local background=0
  local -A arg_vars

  local i=1
  while (( i <= $# )); do
    if [[ "${@[i]}" == --shell=* ]]; then
      shell="${@[i]#--shell=}"
    elif [[ "${@[i]}" == "--arg" ]]; then
      ((i++))
      if [[ "${@[i]}" == *"="* ]]; then
        local kv="${@[i]}"
        local k="${kv%%=*}"
        local v="${kv#*=}"
        arg_vars[$k]="$v"
      fi
    elif [[ "${@[i]}" == --arg=* ]]; then
      local kv="${@[i]#--arg=}"
      local k="${kv%%=*}"
      local v="${kv#*=}"
      arg_vars[$k]="$v"
    elif [[ "${@[i]}" == "--interactive" ]]; then
      interactive=1
    elif [[ "${@[i]}" == "--background" ]]; then
      background=1
    elif [[ "${@[i]}" == "." || "${@[i]}" == */ || -d "${@[i]}" ]]; then
      search_dir="${@[i]}"
    elif [[ "${@[i]}" == *".md" ]]; then
      file="${@[i]}"
    elif [[ -z "$act" ]]; then
      act="${@[i]}"
    elif [[ -z "$ctx" ]]; then
      ctx="${@[i]}"
    fi
    ((i++))
  done

  # File resolution logic
  if [[ -z "$file" ]]; then
    local dir="${search_dir:-.}"
    file=$(actions_find_actionfile "$dir")
    if [[ -z "$file" ]]; then
      echo "ERROR: No Actionfile.md, Actfile.md or README.md found in directory: $dir" >&2
      return 2
    fi
  elif [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file" >&2
    return 2
  fi

  # Prepare environment variables from config and vars
  local setenv
  setenv="$(actions_extract_ini_vars "$file")"
  eval "$setenv"
  local varsblock
  varsblock="$(actions_extract_vars_block "$file")"
  eval "$varsblock"

  # Apply --arg overrides
  for k v in "${(@kv)arg_vars}"; do
    export "$k"="$v"
  done

  # Parse action sections
  local -A sections
  local sectiondump
  sectiondump="$(actions_extract_action_sections "$file")"
  local key="" body=""
  # Use process substitution for robust line reading
  while IFS= read -r line; do
    if [[ "$line" == SECTIONSEP*KEYSEP* ]]; then
      key="${line#SECTIONSEP}"
      key="${key%%KEYSEP*}"
      body="${line#*KEYSEP}"
    elif [[ "$line" == BODYSEPBODYEND ]]; then
      if [[ -n "$key" ]]; then
        sections[$key]="$body"
        key="" body=""
      fi
    elif [[ -n "$key" ]]; then
      body="$body"$'\n'"$line"
    fi
  done < <(printf "%s\n" "$sectiondump")

  # Extract default section
  local default_section
  default_section="$(actions_extract_default_section "$file")"

  local script=""
  if [[ -z "$act" ]]; then
    if [[ -n "$default_section" ]]; then
      script="$default_section"
    else
      echo "ERROR: No action specified and no default section found in $file" >&2
      return 2
    fi
  elif [[ -n "$ctx" ]]; then
    local composite="${ctx}-${act}"
    script="${sections[$composite]}"
    if [[ -z "$script" ]]; then
      echo "ERROR: Section \"$composite\" not found and fallback is not allowed." >&2
      return 2
    fi
  else
    script="${sections[$act]}"
    if [[ -z "$script" ]]; then
      local platform="$(actions_detect_platform)"
      if [[ -n "$platform" ]]; then
        local platform_key="${platform}-${act}"
        script="${sections[$platform_key]}"
      fi
      if [[ -z "$script" ]]; then
        echo "ERROR: Section \"$act\" not found and no suitable ctx-specific section available." >&2
        return 2
      fi
    fi
  fi

  # Run the script with flags
  if (( background )); then
    if (( interactive )); then
      nohup "$shell" -i -c "$script" &>/dev/null &
    else
      nohup "$shell" -c "$script" &>/dev/null &
    fi
  else
    if (( interactive )); then
      "$shell" -i -c "$script"
    else
      "$shell" -c "$script"
    fi
  fi
}

# If you want to allow direct invocation, uncomment:
# action "$@"
