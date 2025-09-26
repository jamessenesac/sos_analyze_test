#!/bin/bash

# ---- safety guard: stop if merge-conflict markers are present ----
if grep -Eq '^(<<<<<<<|=======|>>>>>>>)' "$0"; then
  echo "ERROR: merge-conflict markers present in $0" >&2
  exit 2
fi
# ---- end safety guard ----

#
# Created ....: 03/04/2019
# Developer ..: Waldirio M Pinheiro <waldirio@gmail.com / waldirio@redhat.com>
# Purpose ....: Analyze sosreport and summarize the information (focus on Satellite info)
#

FOREMAN_REPORT="/tmp/$$.log"

ENABLE_COLOR=1
QUIET_MODE=0

if [ -n "$NO_COLOR" ]; then
  ENABLE_COLOR=0
fi

init_colors() {
  if [ "$ENABLE_COLOR" -eq 0 ]; then
    RESET=""
    BOLD=""
    DIM=""
    CYAN=""
    BLUE=""
    GREEN=""
    YELLOW=""
    RED=""
    MAGENTA=""
    WHITE=""
    BRIGHT_RED=""
    BOLD_CYAN=""
    BOLD_BLUE=""
    BOLD_MAGENTA=""
    BOLD_WHITE=""
    return
  fi

  if command -v tput >/dev/null 2>&1; then
    BOLD=$(tput bold)
    DIM=$(tput dim 2>/dev/null || printf '')
    CYAN=$(tput setaf 6)
    BLUE=$(tput setaf 4)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    MAGENTA=$(tput setaf 5)
    WHITE=$(tput setaf 7)
    RESET=$(tput sgr0)
  else
    BOLD=""
    DIM=""
    CYAN=""
    BLUE=""
    GREEN=""
    YELLOW=""
    RED=""
    MAGENTA=""
    WHITE=""
    RESET=""
  fi

  BRIGHT_RED="${BOLD}${RED}"
  BOLD_CYAN="${BOLD}${CYAN}"
  BOLD_BLUE="${BOLD}${BLUE}"
  BOLD_MAGENTA="${BOLD}${MAGENTA}"
  BOLD_WHITE="${BOLD}${WHITE}"
}

color_for_tag() {
  local tag="$1"

  if [ "$ENABLE_COLOR" -eq 0 ]; then
    printf ""
    return
  fi

  case "$tag" in
    ERROR) printf "%s" "$BRIGHT_RED" ;;
    DENIED) printf "%s" "$BRIGHT_RED" ;;
    WARN) printf "%s" "$YELLOW" ;;
    OK) printf "%s" "$GREEN" ;;
    STATUS) printf "%s" "$BOLD_WHITE" ;;
    INFO) printf "%s" "${DIM}${BLUE}" ;;
    QUERY) printf "%s" "$CYAN" ;;
    *) printf "" ;;
  esac
}

wrap_tag() {
  local tag="$1"
  local color

  color=$(color_for_tag "$tag")

  if [ -n "$color" ]; then
    printf "%s[%s]%s" "$color" "$tag" "$RESET"
  else
    printf "[%s]" "$tag"
  fi
}

render_tagged_line() {
  local tag="$1"
  local text="$2"
  local critical="${3:-0}"

  local message="$text"

  if [ "$critical" -eq 1 ] && [ "$ENABLE_COLOR" -eq 1 ]; then
    local color
    color=$(color_for_tag "$tag")
    if [ -n "$color" ]; then
      if [[ "$message" == *" // "* ]]; then
        local command_part="${message%% // *}"
        local comment_part="${message#"$command_part"}"
        message="${command_part}${color}${comment_part}${RESET}"
      else
        message="${color}${message}${RESET}"
      fi
    fi
  fi

  if [ -z "$tag" ]; then
    printf "%s" "$message"
    return
  fi

  local colored_tag
  colored_tag=$(wrap_tag "$tag")

  if [ -n "$message" ]; then
    printf "%s %s" "$colored_tag" "$message"
  else
    printf "%s" "$colored_tag"
  fi
}

classify_text_line() {
  local text="$1"

  if [ -z "$text" ]; then
    printf ":0"
    return
  fi

  if printf "%s" "$text" | grep -Eiq '(traceback \(most recent call last\)|\b(error|exception|keyerror|failed|failure|fatal|panic)\b|no space left|permission denied)'; then
    printf "ERROR:1"
    return
  fi

  if printf "%s" "$text" | grep -Eiq '\bwarning\b|\bwarn\b'; then
    printf "WARN:0"
    return
  fi

  if printf "%s" "$text" | grep -Eiq '\bdenied\b'; then
    printf "DENIED:0"
    return
  fi

  printf ":0"
}

print_line() {
  local tag="$1"
  shift
  local text="$*"

  render_tagged_line "$tag" "$text" 0
  printf "\n"
}

print_critical() {
  local tag="$1"
  shift
  local text="$*"

  render_tagged_line "$tag" "$text" 1
  printf "\n"
}

append_report_line() {
  local line="$1"

  if [ -z "$line" ]; then
    printf "\n" >> "$FOREMAN_REPORT"
  else
    printf "%b\n" "$line" >> "$FOREMAN_REPORT"
  fi
}

tag_is_suppressed() {
  local tag="$1"
  if [ "$QUIET_MODE" -eq 1 ] && [ "$tag" = "INFO" ]; then
    return 0
  fi
  return 1
}

emit_tagged_line() {
  local tag="$1"
  local text="$2"
  local critical="${3:-0}"
  local to_stdout="${4:-0}"

  if tag_is_suppressed "$tag"; then
    return
  fi

  local line
  line=$(render_tagged_line "$tag" "$text" "$critical")
  append_report_line "$line"

  if [ "$to_stdout" -eq 1 ]; then
    printf "%b\n" "$line"
  fi
}

emit_label_line() {
  local label_text="$1"
  local to_stdout="${2:-0}"
  local colored_label="$label_text"

  if [ "$ENABLE_COLOR" -eq 1 ]; then
    colored_label="${BOLD_BLUE}${label_text}${RESET}"
  fi

  local line="// ${colored_label}"
  append_report_line "$line"

  if [ "$to_stdout" -eq 1 ]; then
    printf "%b\n" "$line"
  fi
}

format_plain_line() {
  local text="$1"
  printf "%s" "$text"
}

# capture long options first
PARSED_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-color)
      ENABLE_COLOR=0
      shift
      ;;
    --quiet)
      QUIET_MODE=1
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        PARSED_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      PARSED_ARGS+=("$1")
      shift
      ;;
    *)
      PARSED_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ ${#PARSED_ARGS[@]} -gt 0 ]; then
  set -- "${PARSED_ARGS[@]}"
else
  set --
fi

# the following while block captures three flags from the command line
# -c copies the output file from the /tmp directory to the current directory
# -l opens the output file from the current directory
# -t opens the output file from the /tmp directory

while getopts "clt" opt "${NULL[@]}"; do
 case $opt in
    c )
    COPY_TO_CURRENT_DIR=true
    ;;
   l )   # open copy from local directory.  Requires option 'c' above.
   OPEN_IN_VIM_RO_LOCAL_DIR=true
#   echo "This is l"
   ;;
   t )   # open copy from /tmp/directory
   OPEN_IN_EDITOR_TMP_DIR=true
#   echo "This is t"
   ;;
    \? )
    ;;
 esac
done
shift "$(($OPTIND -1))"

init_colors

MYPWD=`pwd`


main()
{
  > $FOREMAN_REPORT

  sos_path=$1
  base_dir=$sos_path
  final_name=$(echo $base_dir | sed -e 's#/$##g' | grep -o sos.* | awk -F"/" '{print $NF}')

  if [ ! -f $base_dir/version.txt ]; then
    echo "This is not a sosreport dir, please inform the path to the correct one."
    exit 1
  fi

  if [ -d $base_dir/sos_commands/foreman/foreman-debug ]; then
    base_foreman="/sos_commands/foreman/foreman-debug/"
    sos_version="old"
  else
    sos_version="new"
    base_foreman="/"
  fi

  if which rg &>/dev/null; then
    # ripgrep is installed.
    RGOPTS=" -N "
    GREP="$(which rg) $RGOPTS"
    EGREP="$GREP"
  else
    # ripgrep is not installed; use good old GNU grep instead.
    GREP="$(which grep)"
    EGREP="$(which egrep || echo 'grep -E')"
  fi

  echo "The sosreport is: $base_dir"												| tee -a $FOREMAN_REPORT

  #report $base_dir $sub_dir $base_foreman $sos_version
  report $base_dir $base_foreman $sos_version
}

choose_icon() {
  local title_lower
  title_lower=$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')
  local icon="📁"

  case "$title_lower" in
    *service*|*daemon*|*systemctl*) icon="🔧" ;;
    *hardware*|*bios*|*firmware*) icon="🛠️" ;;
    *repo*|*repository*|*package*|*yum*|*dnf*) icon="📦" ;;
    *network*|*naming*|*dns*|*hostname*) icon="🌐" ;;
    *performance*|*cpu*|*load*) icon="🚀" ;;
    *memory*|*swap*|*ram*) icon="🧠" ;;
    *storage*|*disk*|*volume*|*filesystem*|*lvm*) icon="💾" ;;
    *database*|*postgres*|*postgresql*) icon="🗄️" ;;
    *task*|*job*|*queue*) icon="🧾" ;;
    *log*|*audit*) icon="📝" ;;
    *subscription*|*entitlement*|*license*) icon="🪙" ;;
    *proxy*|*httpd*|*apache*) icon="🛡️" ;;
    *security*|*ssl*|*certificate*) icon="🔐" ;;
    *satellite*|*capsule*) icon="🛰️" ;;
    *welcome*|*introduction*) icon="👋" ;;
  esac

  printf "%s" "$icon"
}

LAST_LABEL=""
PENDING_COMMAND=""
CURRENT_SECTION=""
SELINUX_DENIAL_ENFORCING=0
SELINUX_DENIAL_PERMISSIVE=0

reset_selinux_counters() {
  SELINUX_DENIAL_ENFORCING=0
  SELINUX_DENIAL_PERMISSIVE=0
}

should_mark_query() {
  local command_text="$1"
  local lower_label=$(printf "%s" "$LAST_LABEL" | tr '[:upper:]' '[:lower:]')
  local lower_cmd=$(printf "%s" "$command_text" | tr '[:upper:]' '[:lower:]')

  if [[ "$lower_label" == *"search"* || "$lower_label" == *"lookup"* || "$lower_label" == *"query"* ]]; then
    return 0
  fi

  if [[ "$lower_cmd" == *"search"* || "$lower_cmd" == *"lookup"* || "$lower_cmd" == *"query"* ]]; then
    return 0
  fi

  return 1
}

format_label_text() {
  local label="$1"
  printf "%s" "$label"
}

is_command_reference() {
  local text="$1"
  local trimmed
  trimmed=$(printf "%s" "$text" | sed 's/^ *//')

  case "$trimmed" in
    cat\ *|grep\ *|egrep\ *|awk\ *|sed\ *|tail\ *|head\ *|sort\ *|find\ *|ls\ *|for\ *|ps\ *|systemctl\ *|journalctl\ *|bash\ *|sh\ *|rg\ *|diff\ *|cut\ *|uniq\ *|tr\ *|wc\ *|printf\ *|python\ *|perl\ *|while\ *|xargs\ *|du\ *)
      return 0
      ;;
  esac

  if [[ "$trimmed" == /* ]]; then
    return 0
  fi

  if [[ "$trimmed" == *" | "* || "$trimmed" == *" > "* || "$trimmed" == *" < "* || "$trimmed" == *" || "* ]]; then
    return 0
  fi

  return 1
}

emit_section_heading() {
  local title="$1"
  local level="$2"
  local color="$BOLD_MAGENTA"
  if [ -z "$color" ]; then
    color="$BOLD_CYAN"
  fi
  local prefix="==="
  local suffix="==="

  if [ "$level" = "sub" ]; then
    color="$BOLD_WHITE"
    prefix="---"
    suffix="---"
  fi

  local heading="${prefix} ${title} ${suffix}"
  if [ "$ENABLE_COLOR" -eq 1 ]; then
    append_report_line "${color}${heading}${RESET}"
    printf "%b\n" "${color}${heading}${RESET}"
  else
    append_report_line "$heading"
    printf "%s\n" "$heading"
  fi
}

emit_selinux_status() {
  local status=""
  local status_file=""

  if [ -f "$base_dir/sos_commands/selinux/getenforce" ]; then
    status=$(head -n1 "$base_dir/sos_commands/selinux/getenforce" 2>/dev/null)
  elif [ -f "$base_dir/sos_commands/selinux/sestatus" ]; then
    status=$(grep -i "^Current mode:" "$base_dir/sos_commands/selinux/sestatus" 2>/dev/null | awk '{print $3}')
  fi

  if [ -z "$status" ]; then
    return
  fi

  local normalized
  normalized=$(printf "%s" "$status" | tr '[:upper:]' '[:lower:]')
  local display
  display=$(printf "%s" "$status" | tr '[:lower:]' '[:upper:]')

  local message="SELINUX STATUS: $display"
  if [ "$ENABLE_COLOR" -eq 1 ] && [ -n "$BOLD_WHITE" ]; then
    message="SELINUX STATUS: ${BOLD_WHITE}${display}${RESET}"
  fi

  emit_tagged_line "STATUS" "$message" 0 0

  if [ "$normalized" = "disabled" ]; then
    emit_tagged_line "WARN" "SELinux is disabled at runtime" 1 0
  fi
}

highlight_permissive_flag() {
  local text="$1"
  local flag="$2"
  local color="$3"

  if [ "$ENABLE_COLOR" -eq 0 ] || [ -z "$color" ]; then
    printf "%s" "$text"
    return
  fi

  local escaped_flag
  escaped_flag=$(printf '%s' "$flag" | sed -e 's/[.[\*^$(){}+?|\\/]/\\&/g')
  printf "%s" "$(printf "%s" "$text" | sed -E "s|($escaped_flag)|${color}\\1${RESET}|g")"
}

highlight_denied_keyword() {
  local text="$1"

  if [ "$ENABLE_COLOR" -eq 0 ]; then
    printf "%s" "$text"
    return
  fi

  printf "%s" "$(printf "%s" "$text" | sed -E "s|(denied)|${BRIGHT_RED}\\1${RESET}|Ig")"
}

highlight_selinux_setting() {
  local line="$1"

  if [ "$ENABLE_COLOR" -eq 0 ]; then
    printf "%s" "$line"
    return
  fi

  local pattern=""

  if [[ "$line" =~ ^SELINUX= ]]; then
    pattern='(SELINUX=)([^[:space:]#]+)'
  elif [[ "$line" =~ ^SELINUXTYPE= ]]; then
    pattern='(SELINUXTYPE=)([^[:space:]#]+)'
  else
    printf "%s" "$line"
    return
  fi

  if [ -z "$BOLD_WHITE" ]; then
    printf "%s" "$line"
    return
  fi

  local escaped_color
  escaped_color=$(printf '%s' "$BOLD_WHITE" | sed -e 's/[&/\\]/\\&/g')
  local escaped_reset
  escaped_reset=$(printf '%s' "$RESET" | sed -e 's/[&/\\]/\\&/g')

  printf "%s" "$(printf "%s" "$line" | sed -E "s/${pattern}/\\1${escaped_color}\\2${escaped_reset}/")"
}

process_selinux_config() {
  local config_path="$1"

  if [ ! -f "$config_path" ]; then
    emit_tagged_line "WARN" "SELinux config not found // $config_path" 0 0
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^SELINUX= ]]; then
      local value=${line#SELINUX=}
      local lower=$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')
      local decorated
      decorated=$(highlight_selinux_setting "$line")
      emit_tagged_line "STATUS" "$decorated" 0 0
      if [ "$lower" = "disabled" ]; then
        emit_tagged_line "WARN" "SELinux is disabled in the configuration" 1 0
      fi
    elif [[ "$line" =~ ^SELINUXTYPE= ]]; then
      local decorated
      decorated=$(highlight_selinux_setting "$line")
      emit_tagged_line "STATUS" "$decorated" 0 0
    else
      emit_tagged_line "INFO" "$line" 0 0
    fi
  done < "$config_path"
}

process_selinux_denials() {
  local audit_log="$1"

  if [ ! -f "$audit_log" ]; then
    emit_tagged_line "WARN" "audit.log not found // $audit_log" 0 0
    return
  fi

  local tmpfile
  tmpfile=$(mktemp)
  awk 'tolower($0) ~ /denied/ {idx=index($0, "denied"); if (idx > 0) print substr($0, idx)}' "$audit_log" | sort -u > "$tmpfile"

  while IFS= read -r entry || [ -n "$entry" ]; do
    if [ -z "$entry" ]; then
      continue
    fi

    local processed="$entry"

    if [ "$ENABLE_COLOR" -eq 1 ]; then
      processed=$(highlight_denied_keyword "$processed")
      processed=$(highlight_permissive_flag "$processed" "permissive=0" "$BRIGHT_RED")
      processed=$(highlight_permissive_flag "$processed" "permissive=1" "$YELLOW")
    fi

    if [[ "$entry" == *"permissive=0"* ]]; then
      SELINUX_DENIAL_ENFORCING=$((SELINUX_DENIAL_ENFORCING + 1))
    elif [[ "$entry" == *"permissive=1"* ]]; then
      SELINUX_DENIAL_PERMISSIVE=$((SELINUX_DENIAL_PERMISSIVE + 1))
    fi

    emit_tagged_line "DENIED" "$processed" 0 0
  done < "$tmpfile"

  rm -f "$tmpfile"

  local summary
  summary=$(printf "Denials (enforcing): %d  | Denials (permissive logged): %d" "$SELINUX_DENIAL_ENFORCING" "$SELINUX_DENIAL_PERMISSIVE")
  emit_tagged_line "INFO" "$summary" 0 0
}

format_size_value() {
  local kib="$1"
  if [ -z "$kib" ]; then
    printf "0.0M"
    return
  fi

  local mib
  mib=$(awk -v val="$kib" 'BEGIN {printf "%.1f", val/1024}')
  awk -v mib="$mib" 'BEGIN { if (mib >= 1024) printf "%.1fG", mib/1024; else printf "%.1fM", mib }'
}

to_mib() {
  local value="$1"
  local unit="${2:-KiB}"

  awk -v val="$value" -v unit="$unit" 'BEGIN {
    if (val == "") { printf "0.0"; exit }
    if (unit == "bytes" || unit == "B" || unit == "bytes") {
      printf "%.1f", val/1048576
    } else if (unit == "MiB" || unit == "mib" || unit == "MB" || unit == "mb" || unit == "M") {
      printf "%.1f", val
    } else {
      printf "%.1f", val/1024
    }
  }'
}

col_trunc() {
  local string="$1"
  local max_len="$2"
  local ellipsis="${3:-...}"

  local length=${#string}
  local ellipsis_length=${#ellipsis}

  if [ "$max_len" -le 0 ]; then
    printf "%s" ""
    return
  fi

  if [ "$length" -le "$max_len" ]; then
    printf "%s" "$string"
    return
  fi

  local cut=$((max_len - ellipsis_length))
  if [ "$cut" -le 0 ]; then
    printf "%s" "$ellipsis"
    return
  fi

  printf "%s%s" "${string:0:cut}" "$ellipsis"
}

print_table_row() {
  local fmt="$1"
  shift
  printf "$fmt\n" "$@"
}

render_disk_table() {
  local df_path="$1"

  if [ ! -f "$df_path" ]; then
    emit_tagged_line "WARN" "df data not found // $df_path" 0 0
    return
  fi

  local header
  header=$(print_table_row "%-24s %10s %11s %6s %-s" "Filesystem" "Used(MiB)" "Avail(MiB)" "Use%" "Mount")
  emit_tagged_line "INFO" "$header" 0 0

  local separator
  separator=$(print_table_row "%-24s %10s %11s %6s %-s" "------------------------" "----------" "-----------" "------" "-----")
  emit_tagged_line "INFO" "$separator" 0 0

  local data
  data=$(awk 'NR>1 {fs=$1; used=$3; avail=$4; usep=$5; mount=$6; if (NF>6) {for(i=7;i<=NF;++i){mount=mount" "$i}}; printf "%s\t%s\t%s\t%s\t%s\n", fs, used, avail, usep, mount}' "$df_path")

  while IFS=$'\t' read -r fs used avail usepct mount || [ -n "$fs" ]; do
    if [ -z "$fs" ]; then
      continue
    fi

    local fs_col
    fs_col=$(col_trunc "$fs" 24 "...")
    local mount_col
    mount_col=$(col_trunc "$mount" 40 "...")
    local used_fmt
    used_fmt=$(format_size_value "$used")
    local avail_fmt
    avail_fmt=$(format_size_value "$avail")

    local row
    row=$(print_table_row "%-24s %10s %11s %6s %-s" "$fs_col" "$used_fmt" "$avail_fmt" "$usepct" "$mount_col")
    emit_tagged_line "INFO" "$row" 0 0
  done <<EOF
$data
EOF
}

render_network_addresses() {
  local ip_path="$1"

  if [ ! -f "$ip_path" ]; then
    emit_tagged_line "WARN" "ip address data not found // $ip_path" 0 0
    return
  fi

  local -a lines=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
  done < "$ip_path"

  if [ ${#lines[@]} -eq 0 ]; then
    emit_tagged_line "INFO" "No network address data available." 0 0
    return
  fi

  local header
  header=$(print_table_row "%-12s %-7s %-38s %-10s %-s" "INTERFACE" "FAMILY" "ADDRESS" "SCOPE" "DETAILS")
  emit_tagged_line "INFO" "$header" 0 0

  local separator
  separator=$(print_table_row "%-12s %-7s %-38s %-10s %-s" "------------" "-------" "--------------------------------------" "----------" "------------------------------")
  emit_tagged_line "INFO" "$separator" 0 0

  local total=${#lines[@]}
  local idx=0
  local iface=""

  while [ $idx -lt $total ]; do
    line="${lines[$idx]}"

    if [ -z "$line" ]; then
      idx=$((idx + 1))
      continue
    fi

    if [[ "$line" =~ ^[0-9]+: ]]; then
      iface=$(printf "%s" "$line" | sed -E 's/^[0-9]+: *([^: ]+).*/\1/')
      idx=$((idx + 1))
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]+inet ]]; then
      local trimmed
      trimmed=$(printf "%s" "$line" | sed 's/^ *//')

      local -a parts=()
      read -r -a parts <<< "$trimmed"
      if [ ${#parts[@]} -lt 2 ]; then
        idx=$((idx + 1))
        continue
      fi

      local family="${parts[0]}"
      local address="${parts[1]}"
      local scope="-"
      local -a details_parts=()
      local j=2
      while [ $j -lt ${#parts[@]} ]; do
        local token="${parts[$j]}"
        if [ "$token" = "scope" ] && [ $((j + 1)) -lt ${#parts[@]} ]; then
          scope="${parts[$((j + 1))]}"
          j=$((j + 2))
          continue
        fi
        if [ -n "$iface" ] && [ "$token" = "$iface" ]; then
          j=$((j + 1))
          continue
        fi
        details_parts+=("$token")
        j=$((j + 1))
      done

      local skip_next=0
      if [ $((idx + 1)) -lt $total ]; then
        local next_line="${lines[$((idx + 1))]}"
        if [[ "$next_line" =~ ^[[:space:]]+valid_lft ]]; then
          local lifetime
          lifetime=$(printf "%s" "$next_line" | sed 's/^ *//')
          details_parts+=("$lifetime")
          skip_next=1
        fi
      fi

      local details=""
      if [ ${#details_parts[@]} -gt 0 ]; then
        details="${details_parts[*]}"
      fi

      local row
      row=$(print_table_row "%-12s %-7s %-38s %-10s %-s" "$iface" "$family" "$address" "$scope" "$details")
      emit_tagged_line "INFO" "$row" 0 0

      if [ $skip_next -eq 1 ]; then
        idx=$((idx + 2))
      else
        idx=$((idx + 1))
      fi
      continue
    fi

    idx=$((idx + 1))
  done
}

render_memory_table() {
  local free_path="$1"

  if [ ! -f "$free_path" ]; then
    emit_tagged_line "WARN" "free output not found // $free_path" 0 0
    return
  fi

  local header
  header=$(print_table_row "%-6s %12s %11s %11s %17s %11s" "Type" "Total(MiB)" "Used(MiB)" "Free(MiB)" "Buff/Cache(MiB)" "Avail(MiB)")
  emit_tagged_line "INFO" "$header" 0 0

  local separator
  separator=$(print_table_row "%-6s %12s %11s %11s %17s %11s" "------" "------------" "-----------" "-----------" "-----------------" "-----------")
  emit_tagged_line "INFO" "$separator" 0 0

  local mem_line
  mem_line=$(awk '/^Mem:/ {print $2" "$3" "$4" "$6" "$7}' "$free_path")
  if [ -n "$mem_line" ]; then
    read -r mem_total mem_used mem_free mem_buff mem_avail <<EOF
$mem_line
EOF
    local row
    row=$(print_table_row "%-6s %12s %11s %11s %17s %11s" "Mem" "$(format_size_value "$mem_total")" "$(format_size_value "$mem_used")" "$(format_size_value "$mem_free")" "$(format_size_value "$mem_buff")" "$(format_size_value "$mem_avail")")
    emit_tagged_line "INFO" "$row" 0 0
  fi

  local swap_line
  swap_line=$(awk '/^Swap:/ {print $2" "$3" "$4}' "$free_path")
  if [ -n "$swap_line" ]; then
    read -r swap_total swap_used swap_free <<EOF
$swap_line
EOF
    local row
    row=$(print_table_row "%-6s %12s %11s %11s %17s %11s" "Swap" "$(format_size_value "$swap_total")" "$(format_size_value "$swap_used")" "$(format_size_value "$swap_free")" "-" "-")
    emit_tagged_line "INFO" "$row" 0 0
  fi
}

render_top_memory_consumers() {
  local ps_path="$1"

  if [ ! -f "$ps_path" ]; then
    emit_tagged_line "WARN" "process listing not found // $ps_path" 0 0
    return
  fi

  local header
  header=$(print_table_row "%-10s %7s %9s %6s %-s" "USER" "PID" "RSS(MiB)" "%MEM" "COMMAND")
  emit_tagged_line "INFO" "$header" 0 0

  local separator
  separator=$(print_table_row "%-10s %7s %9s %6s %-s" "----------" "-------" "---------" "------" "-------")
  emit_tagged_line "INFO" "$separator" 0 0

  local tmpfile
  tmpfile=$(mktemp)
  awk 'NR>1 {rss=$6; pmem=$4; user=$1; pid=$2; cmd=$11; if (NF>11){for(i=12;i<=NF;++i){cmd=cmd" "$i}}; printf "%s\t%s\t%s\t%s\t%s\n", user, pid, rss, pmem, cmd}' "$ps_path" | sort -k3 -nr | head -n5 > "$tmpfile"

  while IFS=$'\t' read -r user pid rss pmem cmd || [ -n "$user" ]; do
    if [ -z "$user" ]; then
      continue
    fi
    local rss_fmt
    rss_fmt=$(to_mib "$rss")
    local cmd_col
    cmd_col=$(col_trunc "$cmd" 60 "...")
    local row
    row=$(print_table_row "%-10s %7s %9.1f %6.1f %-s" "$user" "$pid" "$rss_fmt" "$pmem" "$cmd_col")
    emit_tagged_line "INFO" "$row" 0 0
  done < "$tmpfile"

  rm -f "$tmpfile"
}

render_user_memory_totals() {
  local ps_path="$1"

  if [ ! -f "$ps_path" ]; then
    emit_tagged_line "WARN" "process listing not found // $ps_path" 0 0
    return
  fi

  local tmpfile
  tmpfile=$(mktemp)
  awk 'NR>1 {rss[$1]+=$6} END {for (user in rss) printf "%s\t%s\n", user, rss[user]}' "$ps_path" | sort -k2 -nr > "$tmpfile"

  local -a users=()
  local -a rss_values=()
  local total_rss=0

  while IFS=$'\t' read -r user rss || [ -n "$user" ]; do
    if [ -z "$user" ]; then
      continue
    fi
    users+=("$user")
    rss_values+=("$rss")
    if [ -n "$rss" ]; then
      total_rss=$((total_rss + rss))
    fi
  done < "$tmpfile"

  rm -f "$tmpfile"

  if [ ${#users[@]} -eq 0 ]; then
    emit_tagged_line "" "No per-user memory consumption data available." 0 0
    return
  fi

  local header
  header=$(print_table_row "%-4s %-16s %12s %10s" "#" "USER" "RSS(MiB)" "% of total")
  emit_tagged_line "" "$header" 0 0

  local separator
  separator=$(print_table_row "%-4s %-16s %12s %10s" "----" "----------------" "------------" "----------")
  emit_tagged_line "" "$separator" 0 0

  local idx=0
  for idx in "${!users[@]}"; do
    local rank=$((idx + 1))
    local user="${users[$idx]}"
    local rss="${rss_values[$idx]}"
    local rss_fmt
    rss_fmt=$(to_mib "$rss")
    local percent="0.0"
    if [ "$total_rss" -gt 0 ]; then
      percent=$(awk -v r="$rss" -v t="$total_rss" 'BEGIN { if (t > 0) printf "%.1f", (r/t)*100; else printf "0.0" }')
    fi
    local percent_display
    percent_display=$(printf "%s%%" "$percent")
    local row
    row=$(print_table_row "%-4s %-16s %12.1f %10s" "$rank" "$user" "$rss_fmt" "$percent_display")
    emit_tagged_line "" "$row" 0 0
  done

  local total_mib
  total_mib=$(to_mib "$total_rss")
  local total_row
  total_row=$(print_table_row "%-4s %-16s %12.1f %10s" "" "Total" "$total_mib" "100.0%")
  emit_tagged_line "" "$total_row" 0 0
}

render_third_party_packages() {
  local package_data="$1"

  if [ ! -f "$package_data" ]; then
    emit_tagged_line "INFO" "No third-party package data found // $package_data" 0 0
    return
  fi

  local data
  data=$(awk -F'\t' '
    NR>1 {
      pkg=$1
      vendor=$4
      gsub(/^ +| +$/, "", pkg)
      gsub(/^ +| +$/, "", vendor)
      if (vendor ~ /Red Hat/) next
      if (pkg ~ /^katello-ca-consumer-/) next
      if (vendor == "") vendor="(none)"
      print pkg "\t" vendor
    }
  ' "$package_data" | LC_ALL=C sort -t$'\t' -k2,2 -k1,1)

  if [ -z "$data" ]; then
    emit_tagged_line "INFO" "No third-party packages were detected." 0 0
    return
  fi

  local header
  header=$(print_table_row "%-45s %-35s" "PACKAGE" "VENDOR")
  emit_tagged_line "INFO" "$header" 0 0

  local separator
  separator=$(print_table_row "%-45s %-35s" "---------------------------------------------" "-----------------------------------")
  emit_tagged_line "INFO" "$separator" 0 0

  while IFS=$'\t' read -r package vendor || [ -n "$package" ]; do
    if [ -z "$package" ]; then
      continue
    fi
    local row
    row=$(print_table_row "%-45s %-35s" "$package" "$vendor")
    emit_tagged_line "INFO" "$row" 0 0
  done <<< "$data"
}

emit_memory_usage_summary() {
  local total_kib="$1"

  if [ -z "$total_kib" ]; then
    return
  fi

  local readable_total
  readable_total=$(format_size_value "$total_kib")

  local gib_value
  gib_value=$(awk -v val="$total_kib" 'BEGIN { printf "%.2f", val/1048576 }')

  local summary_line
  summary_line=$(print_table_row "%-32s %15s" "Total memory consumed" "$readable_total")
  emit_tagged_line "" "$summary_line" 0 0

  local gib_line
  gib_line=$(print_table_row "%-32s %15s" "Total memory consumed (GiB)" "$gib_value")
  emit_tagged_line "" "$gib_line" 0 0

  local kib_line
  kib_line=$(print_table_row "%-32s %15s" "Total memory consumed (KiB)" "$total_kib")
  emit_tagged_line "" "$kib_line" 0 0
}

log_tee() {
  if [ $# -eq 0 ]; then
    append_report_line ""
    printf "\n"
    return
  fi

  local msg="$1"

  if [[ "$msg" == \#\#\#* ]]; then
    local title="$msg"
    while [[ "$title" == \#* ]]; do
      title="${title#\#}"
    done
    title="$(printf "%s" "$title" | sed 's/^ *//; s/ *$//')"
    emit_section_heading "$title" "top"
    CURRENT_SECTION="$title"
    return
  fi

  if [[ "$msg" == \#\#* ]]; then
    local title="$msg"
    while [[ "$title" == \#* ]]; do
      title="${title#\#}"
    done
    title="$(printf "%s" "$title" | sed 's/^ *//; s/ *$//')"
    emit_section_heading "$title" "sub"
    CURRENT_SECTION="$title"
    if [[ "${title,,}" == *"selinux"* ]]; then
      reset_selinux_counters
      emit_selinux_status
    fi
    return
  fi

  emit_tagged_line "INFO" "$msg" 0 1
}

log() {
  if [ $# -eq 0 ]; then
    append_report_line ""
    return
  fi

  local msg="$1"

  if [ -z "$msg" ]; then
    append_report_line ""
    return
  fi

  if [[ "$msg" == "---" ]]; then
    append_report_line ""
    return
  fi

  if [[ "$msg" == //\ * ]]; then
    local label="${msg#// }"
    LAST_LABEL="$label"
    emit_label_line "$label" 1
    return
  fi

  if is_command_reference "$msg"; then
    PENDING_COMMAND="$msg"
    return
  fi

  local classification
  classification=$(classify_text_line "$msg")
  local log_tag=""
  local log_critical=0
  IFS=: read -r log_tag log_critical <<< "$classification"
  emit_tagged_line "$log_tag" "$msg" "${log_critical:-0}" 0
}

log_cmd() {
  local raw_command="$*"
  local display_command="$raw_command"

  if [ -n "$PENDING_COMMAND" ]; then
    display_command="$PENDING_COMMAND"
    PENDING_COMMAND=""
  fi

  local command_tag="INFO"
  if ! should_mark_query "$display_command"; then
    command_tag="QUERY"
  fi

  emit_tagged_line "$command_tag" "$display_command" 0 0

  case "$raw_command" in
    "cat $base_dir/df")
      render_disk_table "$base_dir/df"
      return
      ;;
    "cat $base_dir/ip_addr")
      render_network_addresses "$base_dir/ip_addr"
      return
      ;;
    "cat $base_dir/free")
      render_memory_table "$base_dir/free"
      return
      ;;
    "cat $base_dir/ps | sort -nrk6 | head -n5")
      render_top_memory_consumers "$base_dir/ps"
      return
      ;;
    "cat $base_dir/ps | sort -nr | awk '{print \\\$1, \\\$6}' |"*)
      render_user_memory_totals "$base_dir/ps"
      return
      ;;
    "cat $base_dir/etc/selinux/config")
      process_selinux_config "$base_dir/etc/selinux/config"
      return
      ;;
    "cat $base_dir/sos_commands/rpm/package-data | cut -f1,4 | "*)
      render_third_party_packages "$base_dir/sos_commands/rpm/package-data"
      return
      ;;
  esac

  if [[ "$raw_command" == *"var/log/audit/audit.log"* && "$raw_command" == *"denied"* ]]; then
    process_selinux_denials "$base_dir/var/log/audit/audit.log"
    return
  fi

  local cmd_output
  cmd_output=$(bash -lc "$raw_command" 2>&1)
  local status=$?

  while IFS= read -r line || [ -n "$line" ]; do
    local classification
    classification=$(classify_text_line "$line")
    local line_tag=""
    local line_critical=0
    IFS=: read -r line_tag line_critical <<< "$classification"
    emit_tagged_line "$line_tag" "$line" "${line_critical:-0}" 0
  done <<< "$cmd_output"

  if [ $status -ne 0 ]; then
    local trimmed_output
    trimmed_output=$(printf "%s" "$cmd_output" | tr -d '[:space:]')
    if { [ $status -eq 1 ] || [ $status -eq 2 ]; } && [ -z "$trimmed_output" ]; then
      emit_tagged_line "INFO" "No output returned (exit status $status) // $display_command" 0 0
    else
      emit_tagged_line "STATUS" "command exited with status $status // $display_command" 1 0
    fi
  fi
}

# ref: https://unix.stackexchange.com/questions/44040/a-standard-tool-to-convert-a-byte-count-into-human-kib-mib-etc-like-du-ls1
# Converts bytes value to human-readable string [$1: bytes value]
bytesToHumanReadable() {
    local i=${1:-0} d="" s=0 S=("Bytes" "KiB" "MiB" "GiB" "TiB" "PiB" "EiB" "YiB" "ZiB")
    while ((i > 1024 && s < ${#S[@]}-1)); do
        printf -v d ".%02d" $((i % 1024 * 100 / 1024))
        i=$((i / 1024))
        s=$((s + 1))
    done
    echo "$i$d ${S[$s]}"
}

report()
{

  base_dir=$1
  # sub_dir=$2
  # base_foreman=$base_dir/$3
  # sos_version=$4
  base_foreman=$base_dir/$2
  sos_version=$3

  #base_foreman="$1/sos_commands/foreman/foreman-debug/"

  log_tee "### Welcome to Report ###"
  log_tee "### CEE/SysMGMT ###"
  log
  log

  log_tee "## Naming Resolution"
  log

  log "// hosts entries"
  log "cat $base_dir/etc/hosts"
  log "---"
  log_cmd "cat $base_dir/etc/hosts"
  log "---"
  log

  log "// resolv.conf"
  log "cat $base_dir/etc/resolv.conf"
  log "---"
  log_cmd "cat $base_dir/etc/resolv.conf"
  log "---"
  log
  
  log "// hostname"
  log "cat $base_dir/etc/hostname"
  log "---"
  log_cmd "cat $base_dir/etc/hostname"
  log "---"
  log

  log_tee "## Hardware"
  log

  log "// baremetal or vm?"
  log "cat $base_dir/dmidecode | $EGREP '(Vendor|Manufacture)' | head -n3"
  log "---"
  log_cmd "cat $base_dir/dmidecode | $EGREP '(Vendor|Manufacture)' | head -n3"
  log "---"
  log



  log_tee "## Network Information"
  log

  log "// ip address"
  log "cat $base_dir/ip_addr"
  log "---"
  log_cmd "cat $base_dir/ip_addr"
  log "---"
  log

  log "// current route"
  log "cat $base_dir/ip_route"
  log "---"
  log_cmd "cat $base_dir/ip_route"
  log "---"
  log

  log_tee "## Selinux"
  log

  log "// selinux conf"
  log "cat $base_dir/etc/selinux/config"
  log "---"
  log_cmd "cat $base_dir/etc/selinux/config"
  log "---"
  log

  log "// setroubleshoot package"
  log "$GREP setroubleshoot $base_dir/installed-rpms"
  log "---"
  log_cmd "$GREP setroubleshoot $base_dir/installed-rpms"
  log "---"
  log

  log "// sealert information"
  log "$GREP -o sealert.* $base_dir/var/log/messages | sort -u"
  log "---"
  log_cmd "$GREP -o sealert.* $base_dir/var/log/messages | sort -u"
  log "---"
  log




  log_tee "## Installed Packages (satellite)"
  log

  log "// all installed packages which contain satellite"
  log "$GREP satellite $base_dir/installed-rpms"
  log "---"
  log_cmd "$GREP satellite $base_dir/installed-rpms"
  log "---"
  log

  log "// packages provided by 3rd party vendors"
  log "cat $base_dir/sos_commands/rpm/package-data | cut -f1,4 | $GREP -v -e \"Red Hat\" -e katello-ca-consumer- | sort -k2"
  log "---"
  log_cmd "cat $base_dir/sos_commands/rpm/package-data | cut -f1,4 | $GREP -v -e \"Red Hat\" -e katello-ca-consumer- | sort -k2"
  log "---"
  log


  log_tee "## Subscriptions"
  log

  log "// subscription identity"
  log "cat $base_dir/sos_commands/subscription_manager/subscription-manager_identity"
  log "---"
  log_cmd "cat $base_dir/sos_commands/subscription_manager/subscription-manager_identity"
  log "---"
  log

  log "// installed katello-agent and/or gofer"
  log "$EGREP '(^katello-agent|^gofer)' $base_dir/installed-rpms"
  log "---"
  log_cmd "$EGREP '(^katello-agent|^gofer)' $base_dir/installed-rpms"
  log "---"
  log

  log "// goferd service"
  log "$EGREP '(^katello-agent|^gofer)' $base_dir/installed-rpms"
  log "cat $base_dir/sos_commands/systemd/systemctl_list-units | $GREP goferd"
  log "---"
  log_cmd "cat $base_dir/sos_commands/systemd/systemctl_list-units | $GREP goferd"
  log "---"
  log

  log "// subsman list installed"
  log "cat $base_dir/sos_commands/subscription_manager/subscription-manager_list_--installed"
  log "---"
  log_cmd "cat $base_dir/sos_commands/subscription_manager/subscription-manager_list_--installed"
  log "---"
  log

  log "// subsman list consumed"
  log "cat $base_dir/sos_commands/subscription_manager/subscription-manager_list_--consumed"
  log "---"
  log_cmd "cat $base_dir/sos_commands/subscription_manager/subscription-manager_list_--consumed"
  log "---"
  log


  log_tee "## Repos"
  log


  log "// enabled repos"
  log "cat $base_dir/sos_commands/dnf/dnf_-C_repolist_--verbose"
  log "---"
  log_cmd "cat $base_dir/sos_commands/dnf/dnf_-C_repolist_--verbose"
  log "---"
  log

  log "// yum history"
  log "cat $base_dir/sos_commands/dnf/dnf_history"
  log "---"
  log_cmd "cat $base_dir/sos_commands/dnf/dnf_history"
  log "---"
  log

#  TODO
#  improve this one, once the dnf.log has too much info
#
#  log "// yum.log info"
#  log "cat $base_dir/var/log/dnf.log"
#  log "---"
#  log_cmd "cat $base_dir/var/log/dnf.log"
#  log "---"
#  log


  log_tee "## Upgrade"
  log


# grep "Running installer with args" /var/log/foreman-installer/satellite.log
  log "// Last flag used with satellite-installer"

  if [ "$sos_version" == "old" ];then
    cmd="$EGREP \"(Running installer with args|signal was)\" $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log"
  else
    cmd="$EGREP \"(Running installer with args|signal was)\" $base_dir/var/log/foreman-installer/satellite.log"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log "// All the flags used with satellite-installer"

  if [ "$sos_version" == "old" ];then
    cmd="$GREP \"Running installer with args\" $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.* | sort -rk3 | cut -d: -f2-"
  else
    cmd="$GREP \"Running installer with args\" $base_dir/var/log/foreman-installer/satellite.* | sort -rk3 | cut -d: -f2-"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log




  log "// # of error on the upgrade file"

  if [ "$sos_version" == "old" ];then
    cmd="$GREP '^\[ERROR' $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log -c"
  else
    cmd="$GREP '^\[ERROR' $base_dir/var/log/foreman-installer/satellite.log -c"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log "// Error on the upgrade file (full info)"

  if [ "$sos_version" == "old" ];then
    cmd="$GREP '^\[ERROR' $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log"
  else
    cmd="$GREP '^\[ERROR' $base_dir/var/log/foreman-installer/satellite.log"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log

  log "// Upgrade Completed? (6.4 or greater)"

  if [ "$sos_version" == "old" ];then
   #cmd="grep \"Upgrade completed\" $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log | wc -l"
    cmd="$GREP \"Upgrade completed\" $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log -c"
  else
   #cmd="grep \"Upgrade completed\" $base_dir/var/log/foreman-installer/satellite.log | wc -l"
    cmd="$GREP \"Upgrade completed\" $base_dir/var/log/foreman-installer/satellite.log -c"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log "// last 20 lines from upgrade log"

  if [ "$sos_version" == "old" ];then
    cmd="tail -20 $base_dir/sos_commands/foreman/foreman-debug/var/log/foreman-installer/satellite.log"
  else
    cmd="tail -20 $base_dir/var/log/foreman-installer/satellite.log"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log_tee "## Disk"
  log

  log "// full disk info"
  log "cat $base_dir/df"
  log "---"
  log_cmd "cat $base_dir/df"
  log "---"
  log

#  log "// disk space output"
#  log "cat $base_dir/sos_commands/foreman/foreman-debug/disk_space_output"
#  log "---"
#  log_cmd "cat $base_dir/sos_commands/foreman/foreman-debug/disk_space_output"
#  log "---"
#  log

  log "// no space left on device"
  log "$GREP \"No space left on device\" $base_dir/* 2>/dev/null"
  log "---"
  log_cmd "$GREP \"No space left on device\" $base_dir/* 2>/dev/null"
  log "---"
  log



  log_tee "## Memory"
  log

  log "// memory usage"
  log "cat $base_dir/free"
  log "---"
  log_cmd "cat $base_dir/free"
  log "---"
  log

  log "// TOP 5 memory consumers"
  log "cat $base_dir/ps | sort -nrk6 | head -n5"
  log "---"
  log_cmd "cat $base_dir/ps | sort -nrk6 | head -n5"
  log "---"
  log

  log "// users memory consumers"
  log "cat $base_dir/ps | sort -nr | awk '{print \$1, \$6}' | $GREP -v ^USER | $GREP -v ^COMMAND | $GREP -v \"^ $\" | awk  '{a[\$1] += \$2} END{for (i in a) print i, a[i]}' | sort -nrk2"
  log "and"
  log "memory_usage=\$(cat $base_dir/ps | sort -nr | awk '{print \$6}' | grep -v ^-$ | $GREP -v ^RSS | $GREP -v ^$ | paste -s -d+ | bc)"
  log "and"
  log "memory_usage_gb=\$(echo \"scale=2;$memory_usage/1024/1024\" | bc)"
  log "---"
  log_cmd "cat $base_dir/ps | sort -nr | awk '{print \$1, \$6}' | $GREP -v ^USER | $GREP -v ^COMMAND | $GREP -v \"^ $\" | awk  '{a[\$1] += \$2} END{for (i in a) print i, a[i]}' | sort -nrk2"
  log
  memory_usage=$(cat $base_dir/ps | sort -nr | awk '{print $6}' | grep -v ^-$ | $GREP -v ^RSS | $GREP -v ^$ | paste -s -d+ | bc)
  emit_memory_usage_summary "$memory_usage"
  log

  log "// Postgres idle process (candlepin)"
  log "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | $GREP \"candlepin candlepin\" | wc -l"
  log "---"
  log_cmd "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | $GREP \"candlepin candlepin\" | wc -l"
  log "---"
  log

  log "// Postgres idle process (foreman)"
  log "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | $GREP \"foreman foreman\" | wc -l"
  log "---"
  log_cmd "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | $GREP \"foreman foreman\" | wc -l"
  log "---"
  log

  log "// Postgres idle process (everything)"
  log "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | wc -l"
  log "---"
  log_cmd "cat $base_dir/ps | $GREP ^postgres | $GREP idle$ | wc -l"
  log "---"
  log

  log "// Processes running for a while (TOP 5 per time)"
  log "cat $base_dir/ps | sort -nr -k10 | head -n5"
  log "---"
  log_cmd "cat $base_dir/ps | sort -nr -k10 | head -n5"
  log "---"
  log



  log_tee "## CPU"
  log

  log "// cpu's number"
  log "cat $base_dir/proc/cpuinfo | $GREP processor | wc -l"
  log "---"
  log_cmd "cat $base_dir/proc/cpuinfo | $GREP processor | wc -l"
  log "---"
  log


  log_tee "## Messages"
  log

  log "// error on message file"
  log "$GREP ERROR $base_dir/var/log/messages"
  log "---"
  log_cmd "$GREP ERROR $base_dir/var/log/messages"
  log "---"
  log


  log_tee "## Out of Memory"
  log

  log "// out of memory"
  log "$GREP \"Out of memory\" $base_dir/var/log/messages"
  log "---"
  log_cmd "$GREP \"Out of memory\" $base_dir/var/log/messages"
  log "---"
  log

  log "Pavel Moravec Script to check the memory usage during the oom killer"
  log " - https://gitlab.cee.redhat.com/mna-emea/oom-process-stats"
  log ""
  log "// Memory Consumption"
  log "/usr/bin/python3 /tmp/script/oom-process-stats.py $base_dir/var/log/messages"
  log "---"
  log_cmd "/usr/bin/python3 /tmp/script/oom-process-stats.py $base_dir/var/log/messages"
  log "---"
  log


  log_tee "## Performance"
  log

  log "// Analyzing '/var/log/sa/sa' files and checking for values with low time"
  log "for b in \$(ls \$base_dir/var/log/sa/sa[0-9]*); do echo - \$b;sar -f \$b | grep -E '(CPU|all)' | grep -E '( [0-9].[0-9]2\$)'; done"
  log "---"
  log_cmd "for b in \$(ls \$base_dir/var/log/sa/sa[0-9]*); do echo - \$b;sar -f \$b | grep -E '(CPU|all)' | grep -E '( [0-9].[0-9]2\$)'; done"
  log "---"
  log




  log_tee "## Foreman Tasks"
  log

  
  if [ "$sos_version" == "old" ];then
    cmd="cat $base_dir/sos_commands/foreman/foreman-debug/foreman_tasks_tasks.csv | wc -l"
  else
    cmd="cat $base_dir/sos_commands/foreman/foreman_tasks_tasks | wc -l"
  fi

  log "// total # of foreman tasks"
  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  if [ "$sos_version" == "old" ];then
    cmd="cat $base_dir/sos_commands/foreman/foreman-debug/foreman_tasks_tasks.csv | cut -d, -f3 | $GREP Actions | sort | uniq -c | sort -nr"
  else
    cmd="cat $base_dir/sos_commands/foreman/foreman_tasks_tasks | sed '1,3d' | cut -d, -f3 | $GREP Actions | sort | uniq -c | sort -nr"
  fi


  log "// Tasks TOP"
  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  if [ "$sos_version" == "old" ];then
    cmd="cat $base_dir/etc/cron.d/foreman-tasks"
  else
    cmd="cat $base_dir/etc/cron.d/foreman-tasks"
  fi

  log "// foreman tasks cleanup script"
  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log



  log "// paused foreman tasks"
  log "$GREP '(^                  id|paused)' $base_dir/sos_commands/foreman/foreman_tasks_tasks | sed 's/  //g' | sed -e 's/ |/|/g' | sed -e 's/| /|/g' | sed -e 's/^ //g' | sed -e 's/|/,/g'"
  log "---"
  log_cmd "$GREP '(^                  id|paused)' $base_dir/sos_commands/foreman/foreman_tasks_tasks | sed 's/  //g' | sed -e 's/ |/|/g' | sed -e 's/| /|/g' | sed -e 's/^ //g' | sed -e 's/|/,/g'"
  log "---"
  log



#  log_tee "## Pulp"
#  log
#
#  log "// number of tasks not finished"
#  log "$GREP '\"task_id\"' $base_dir/sos_commands/pulp/pulp-running_tasks -c"
#  log "---"
#  log_cmd "$GREP '\"task_id\"' $base_dir/sos_commands/pulp/pulp-running_tasks -c"
#  log "---"
#  log
#
#
##grep "\"task_id\"" 02681559/0050-sosreport-pc1ustsxrhs06-2020-06-26-kfmgbpf.tar.xz/sosreport-pc1ustsxrhs06-2020-06-26-kfmgbpf/sos_commands/pulp/pulp-running_tasks | wc -l
#
#  log "// pulp task not finished"
#  log "$EGREP '(\"finish_time\" : null|\"start_time\"|\"state\"|\"pulp:|^})' $base_dir/sos_commands/pulp/pulp-running_tasks"
#  log "---"
#  log_cmd "$EGREP '(\"finish_time\" : null|\"start_time\"|\"state\"|\"pulp:|^})' $base_dir/sos_commands/pulp/pulp-running_tasks"
#  log "---"
#  log




  log_tee "## Hammer Ping"
  log

  log "// hammer ping output"

  if [ "$sos_version" == "old" ];then
    cmd="cat $base_dir/sos_commands/foreman/foreman-debug/hammer-ping"
  else
    cmd="cat $base_dir/sos_commands/foreman/hammer_ping"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log "## Katello service status"
  log

  log "// katello-service status output"

  if [ "$sos_version" == "old" ];then
    cmd="cat $base_dir/sos_commands/foreman/foreman-debug/katello_service_status"
  else
    cmd="cat $base_dir/sos_commands/foreman_installer/foreman-maintain_service_status"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log "// katello-service status output - condensed"

  if [ "$sos_version" == "old" ];then
    cmd="$EGREP '(^\*|Active)' $base_dir/sos_commands/foreman/foreman-debug/katello_service_status | tr '^\*' '\n'"
  else
    cmd="$EGREP '(^\*|Active)' $base_dir/sos_commands/foreman_installer/foreman-maintain_service_status | tr '^\*' '\n'"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log_tee "## Puppet Server"
  log

  log "// Puppet Server Error"
  log "$GREP ERROR $base_dir/var/log/puppetlabs/puppetserver/puppetserver.log"
  log "---"
  log_cmd "$GREP ERROR $base_dir/var/log/puppetlabs/puppetserver/puppetserver.log"
  log "---"
  log


  log_tee "## Audit"
  log

  log "// denied in audit.log"
  log "$GREP -o denied.* $base_dir/var/log/audit/audit.log  | sort -u"
  log "---"
  log_cmd "$GREP -o denied.* $base_dir/var/log/audit/audit.log  | sort -u"
  log "---"
  log


  log_tee "## PostgreSQL"
  log

  log "// Checking the process/path"
  log "cat $base_dir/ps | grep postgres | grep data"
  log "---"
  log_cmd "cat $base_dir/ps | grep postgres | grep data"
  log "---"
  log

  log "// postgres storage consumption - /var/lib/psql"
  log "cat $base_dir/sos_commands/postgresql/du_-sh_.var.lib.pgsql"
  log "---"
  log_cmd "cat $base_dir/sos_commands/postgresql/du_-sh_.var.lib.pgsql"
  log "---"
  log

  log "// postgres storage consumption - /var/opt/rh/rh-postgresql12/lib/pgsql/data"
  log "cat $base_dir/sos_commands/postgresql/du_-sh_.var..opt.rh.rh-postgresql12.lib.pgsql"
  log "---"
  log_cmd "cat $base_dir/sos_commands/postgresql/du_-sh_.var..opt.rh.rh-postgresql12.lib.pgsql"
  log "---"
  log

  log "// TOP foreman tables consumption"
  log "head -n30 $base_dir/sos_commands/foreman/foreman_db_tables_sizes"
  log "---"
  log_cmd "head -n30 $base_dir/sos_commands/foreman/foreman_db_tables_sizes"
  log "---"
  log  


  log_tee "## PostgreSQL Log - /var/lib/pgsql/"
  log

  log "// Deadlock count"
  log "$GREP -I -i deadlock $base_foreman/var/lib/pgsql/data/log/*.log -c"
  log "---"
  log_cmd "$GREP -I -i deadlock $base_foreman/var/lib/pgsql/data/log/*.log -c"
  log "---"
  log

  log "// Deadlock"
  log "$GREP -I -i deadlock $base_foreman/var/lib/pgsql/data/log/*.log"
  log "---"
  log_cmd "$GREP -I -i deadlock $base_foreman/var/lib/pgsql/data/log/*.log"
  log "---"
  log

  log "// ERROR count"
  log "$GREP -F ERROR $base_foreman/var/lib/pgsql/data/log/*.log -c"
  log "---"
  log_cmd "$GREP -F ERROR $base_foreman/var/lib/pgsql/data/log/*.log -c"
  log "---"
  log

  log "// ERROR"
  log "$GREP -I ERROR $base_foreman/var/lib/pgsql/data/log/*.log"
  log "---"
  log_cmd "$GREP -I ERROR $base_foreman/var/lib/pgsql/data/log/*.log"
  log "---"
  log

  log "// Current Configuration"
  log "cat $base_foreman/var/lib/pgsql/data/postgresql.conf | $GREP -v ^# | $GREP -v ^$ | $GREP -v ^\"\\t\\t\".*#"
  log "---"
  log_cmd "cat $base_foreman/var/lib/pgsql/data/postgresql.conf | $GREP -v ^# | $GREP -v ^$ | $GREP -v ^\"\\t\\t\".*#"
  log "---"
  log


  log_tee "## PostgreSQL Log - /var/opt/rh/rh-postgresql12/lib/pgsql/data"
  log

  log "// Deadlock count"
  log "$GREP -I -i deadlock $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log -c"
  log "---"
  log_cmd "$GREP -I -i deadlock $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log -c"
  log "---"
  log

  log "// Deadlock"
  log "$GREP -I -i deadlock $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log"
  log "---"
  log_cmd "$GREP -I -i deadlock $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log"
  log "---"
  log

  log "// ERROR count"
  log "$GREP -F ERROR $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log -c"
  log "---"
  log_cmd "$GREP -F ERROR $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log -c"
  log "---"
  log

  log "// ERROR"
  log "$GREP -I ERROR $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log"
  log "---"
  log_cmd "$GREP -I ERROR $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/log/*.log"
  log "---"
  log

  log "// Current Configuration"
  log "cat $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/postgresql.conf | $GREP -v ^# | $GREP -v ^$ | $GREP -v ^\"\\t\\t\".*#"
  log "---"
  log_cmd "cat $base_foreman/var/opt/rh/rh-postgresql12/lib/pgsql/data/postgresql.conf | $GREP -v ^# | $GREP -v ^$ | $GREP -v ^\"\\t\\t\".*#"
  log "---"
  log


  log_tee "## Foreman Tasks"
  log

  log "// dynflow running"
  log "cat $base_dir/ps | $GREP dynflow_executor\$"
  log "---"
  log_cmd "cat $base_dir/ps | $GREP dynflow_executor$"
  log "---"
  log



  log_tee "## Foreman logs (error)"
  log

  # Note: `grep -I` differs from `rg -I` but the difference in behavior is not causing differences in output here. So I'm leaving `$GREP -I`.
  log "// total number of errors found on production.log - TOP 40"
  log "$GREP -I -F \"[E\" $base_foreman/var/log/foreman/production.log* | awk '{print \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13}' | sort | uniq -c | sort -nr | head -n40"
  log "---"
  log_cmd "$GREP -I -F \"[E\" $base_foreman/var/log/foreman/production.log* | awk '{print \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13}' | sort | uniq -c | sort -nr | head -n40"
  log "---"
  log



  log_tee "## Foreman cron"
  log

  log "// last 20 entries from foreman/cron.log"
  log "tail -20 $base_foreman/var/log/foreman/cron.log"
  log "---"
  log_cmd "tail -20 $base_foreman/var/log/foreman/cron.log"
  log "---"
  log


  log_tee "## Httpd"
  log

  log "// queues on error_log means the # of requests crossed the border. Satellite inaccessible"
  log "$GREP -F 'Request queue is full' $base_foreman/var/log/httpd/error_log | wc -l"
  log "---"
  log_cmd "$GREP -F 'Request queue is full' $base_foreman/var/log/httpd/error_log | wc -l"
  log "---"
  log

  log "// when finding something on last step, we will here per date"
  log "$GREP -F queue $base_foreman/var/log/httpd/error_log  | awk '{print \$2, \$3}' | cut -d: -f1,2 | uniq -c"
  log "---"
  log_cmd "$GREP -F queue $base_foreman/var/log/httpd/error_log  | awk '{print \$2, \$3}' | cut -d: -f1,2 | uniq -c"
  log "---"
  log

  log "// TOP 20 of ip address requesting the satellite via https"
  log "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1}' | sort | uniq -c | sort -nr | head -n20"
  log "---"
  log_cmd "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1}' | sort | uniq -c | sort -nr | head -n20"
  log "---"
  log

  log "// TOP 20 of ip address requesting the satellite via https (detailed)"
  log "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1,\$4}' | cut -d: -f1,2,3 | sort | uniq -c | sort -nr | head -n20"
  log "---"
  log_cmd "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1,\$4}' | cut -d: -f1,2,3 | sort | uniq -c | sort -nr | head -n20"
  log "---"
  log

  log "// TOP 50 of uri requesting the satellite via https"
  log "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1, \$6, \$7}' | sort | uniq -c | sort -nr | head -n 50"
  log "---"
  log_cmd "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$1, \$6, \$7}' | sort | uniq -c | sort -nr | head -n 50"
  log "---"
  log

  log "// Possible scanner queries"
  log "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | grep \" 404 \" | grep -E '(\"-\" \"-\")' | head -n10"
  log "---"
  log_cmd "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | grep \" 404 \" | grep -E '(\"-\" \"-\")' | head -n10"
  log "---"
  log



  log "// General 2XX errors on httpd logs"
  log "$GREP '\" 2\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log_cmd "$GREP '\" 2\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log

  log "// General 3XX errors on httpd logs"
  log "$GREP '\" 3\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log_cmd "$GREP '\" 3\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log

  log "// General 4XX errors on httpd logs"
  log "$GREP '\" 4\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log_cmd "$GREP '\" 4\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log

  log "// General 5XX errors on httpd logs"
  log "$GREP '\" 5\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log_cmd "$GREP '\" 5\d\d ' $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log | awk '{print \$9}' | sort | uniq -c | sort -nr"
  log "---"
  log




  log_tee "## RHSM"
  log

  log "// RHSM Proxy"
  log "$GREP -F proxy $base_dir/etc/rhsm/rhsm.conf | $GREP -v ^#"
  log "---"
  log_cmd "$GREP -F proxy $base_dir/etc/rhsm/rhsm.conf | $GREP -v ^#"
  log "---"
  log

  log "// Satellite Proxy"
  log "$EGREP '(^  proxy_url|^  proxy_port|^  proxy_username|^  proxy_password)' $base_dir/etc/foreman-installer/scenarios.d/satellite-answers.yaml"
  log "---"
  log_cmd "$EGREP '(^  proxy_url|^  proxy_port|^  proxy_username|^  proxy_password)' $base_dir/etc/foreman-installer/scenarios.d/satellite-answers.yaml"
  log "---"
  log

  log "// Virt-who Proxy"
  log "$GREP -F -i proxy $base_dir/etc/sysconfig/virt-who"
  log "---"
  log_cmd "$GREP -F -i proxy $base_dir/etc/sysconfig/virt-who"
  log "---"
  log

  log "// RHSM errors"
  log "$GREP -F ERROR $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log_cmd "$GREP -F ERROR $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log

  log "// RHSM Warnings"
  log "$GREP -F WARNING $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log_cmd "$GREP -F WARNING $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log

  log "// duplicated hypervisors #"
  log "$GREP -F \"is assigned to 2 different systems\" $base_dir/var/log/rhsm/rhsm.log | awk '{print \$9}' | sed -e \"s/'//g\" | sort -u | wc -l"
  log "---"
  log_cmd "$GREP -F \"is assigned to 2 different systems\" $base_dir/var/log/rhsm/rhsm.log | awk '{print \$9}' | sed -e \"s/'//g\" | sort -u | wc -l"
  log "---"
  log

  log "// duplicated hypervisors list"
  log "$GREP -F \"is assigned to 2 different systems\" $base_dir/var/log/rhsm/rhsm.log | awk '{print \$9}' | sed -e \"s/'//g\" | sort -u"
  log "---"
  log_cmd "$GREP -F \"is assigned to 2 different systems\" $base_dir/var/log/rhsm/rhsm.log | awk '{print \$9}' | sed -e \"s/'//g\" | sort -u"
  log "---"
  log

  log "// Sending updated Host-to-guest"
  log "$GREP -F \"Sending updated Host-to-guest\" $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log_cmd "$GREP -F \"Sending updated Host-to-guest\" $base_dir/var/log/rhsm/rhsm.log"
  log "---"
  log




  log_tee "## Virt-who"
  log

  log "// virt-who status"
  log "cat $base_dir/sos_commands/systemd/systemctl_list-units | $GREP -F virt-who"
  log "---"
  log_cmd "cat $base_dir/sos_commands/systemd/systemctl_list-units | $GREP -F virt-who"
  log "---"
  log

  log "// virt-who default configuration"
  log "cat $base_dir/etc/sysconfig/virt-who | $GREP -v ^# | $GREP -v ^$"
  log "---"
  log_cmd "cat $base_dir/etc/sysconfig/virt-who | $GREP -v ^# | $GREP -v ^$"
  log "---"
  log

  log "// virt-who configuration"
  log "ls -l $base_dir/etc/virt-who.d"
  log "---"
  log_cmd "ls -l $base_dir/etc/virt-who.d"
  log "---"
  log

  log "// duplicated server entries on virt-who configuration"
  log "$GREP -I ^server $base_dir/etc/virt-who.d/*.conf | sort | uniq -c"
  log "---"
  log_cmd "$GREP -I ^server $base_dir/etc/virt-who.d/*.conf | sort | uniq -c"
  log "---"
  log



  log "// virt-who configuration content files"
  log "for b in \$(ls -1 \$base_dir/etc/virt-who.d/*.conf); do echo; echo \$b; echo \"===\"; cat \$b; echo \"===\"; done"
  log "---"
  log_cmd "for b in \$(ls -1 $base_dir/etc/virt-who.d/*.conf); do echo; echo \$b; echo \"===\"; cat \$b; echo \"===\"; done"
  log "---"
  log

  log "// virt-who configuration content files (hidden characters)"
  log "for b in \$(ls -1 \$base_dir/etc/virt-who.d/*.conf); do echo; echo \$b; echo \"===\"; cat -vet \$b; echo \"===\"; done"
  log "---"
  log_cmd "for b in \$(ls -1 $base_dir/etc/virt-who.d/*.conf); do echo; echo \$b; echo \"===\"; cat -vet \$b; echo \"===\"; done"
  log "---"
  log

  log "// virt-who server(s)"
  log "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log  | $GREP -F \"cmd=virt-who\" | awk '{print \$1}' | sort | uniq -c"
  log "---"
  log_cmd "cat $base_foreman/var/log/httpd/foreman-ssl_access_ssl.log  | $GREP -F \"cmd=virt-who\" | awk '{print \$1}' | sort | uniq -c"
  log "---"
  log



  log_tee "## Hypervisors tasks"
  log

  log "// latest 30 hypervisors tasks"

  if [ "$sos_version" == "old" ];then
    cmd="cat $base_foreman/foreman_tasks_tasks.csv | $EGREP '(^                  id|Hypervisors)' | sed -e 's/,/ /g' | sort -rk6 | head -n 30 | cut -d\| -f3,4,5,6,7"
  else
    cmd="cat $base_dir/sos_commands/foreman/foreman_tasks_tasks | $EGREP '(^                  id|Hypervisors)' | sed -e 's/,/ /g' | sort -rk6 | head -n 30 | cut -d\| -f3,4,5,6,7"
  fi

  log "$cmd"
  log "---"
  log_cmd "$cmd"
  log "---"
  log


  log_tee "## Tomcat"
  log

  log "// Memory (Xms and Xmx)"
  log "$GREP -F tomcat $base_dir/ps"
  log "---"
  log_cmd "$GREP -F tomcat $base_dir/ps"
  log "---"
  log


  log_tee "## Candlepin"
  log

  log "// latest state of candlepin (updating info)"
  log "$GREP -F -B1 Updated $base_foreman/var/log/candlepin/candlepin.log"
  log "---"
  log_cmd "$GREP -F -B1 Updated $base_foreman/var/log/candlepin/candlepin.log"
  log "---"
  log

  log "// ERROR on candlepin log - candlepin.log"
  log "$GREP -F ERROR $base_foreman/var/log/candlepin/candlepin.log | cut -d ' ' -f1,3- | uniq -c"
  log "---"
  log_cmd "$GREP -F ERROR $base_foreman/var/log/candlepin/candlepin.log | cut -d ' ' -f1,3- | uniq -c"
  log "---"
  log

  log "// ERROR on candlepin log - error.log"
  log "$GREP -F ERROR $base_foreman/var/log/candlepin/error.log | cut -d ' ' -f1,3- | uniq -c"
  log "---"
  log_cmd "$GREP -F ERROR $base_foreman/var/log/candlepin/error.log | cut -d ' ' -f1,3- | uniq -c"
  log "---"
  log

  log "// latest entry on error.log"
  log "tail -30 $base_foreman/var/log/candlepin/error.log"
  log "---"
  log_cmd "tail -30 $base_foreman/var/log/candlepin/error.log"
  log "---"
  log

  log "// candlepin storage consumption"
  log "cat $base_dir/sos_commands/candlepin/du_-sh_.var.lib.candlepin"
  log "---"
  log_cmd "cat $base_dir/sos_commands/candlepin/du_-sh_.var.lib.candlepin"
  log "---"
  log

  log "// SCA Information"
  log "$GREP -i \"content access mode\" $base_dir/var/log/candlepin/* | grep -o \"Auto-attach is disabled.*\" | sort -u | grep -v Skipping"
  log "---"
  log_cmd "$GREP -i \"content access mode\" $base_dir/var/log/candlepin/* | grep -o \"Auto-attach is disabled.*\" | sort -u | grep -v Skipping"
  log "---"
  log

  log "// Tasks in Candlepin - Time in miliseconds - TOP 20"
  log "$GREP -o time=.* candlepin.log $base_dir/var/log/candlepin/* | sort -nr | sed -e 's/=/ /g' | sort -k2 -nr | uniq -c | head -n20 | sed -s 's/time /time=/g' | cut -d: -f2"
  log "---"
  log_cmd "$GREP -o time=.* candlepin.log $base_dir/var/log/candlepin/* | sort -nr | sed -e 's/=/ /g' | sort -k2 -nr | uniq -c | head -n20 | sed -s 's/time /time=/g' | cut -d: -f2"
  log "---"
  log





  log_tee "## Cron"
  log

  log "// cron from the base OS"
  log "ls -l $base_dir/var/spool/cron/*"
  log "---"
  log_cmd "ls -l $base_dir/var/spool/cron/*"
  log "---"
  log

  log "// checking the content of base OS cron"
  log "for b in \$(ls -1 $base_dir/var/spool/cron/*); do echo; echo \$b; echo \"===\"; cat \$b; echo \"===\"; done"
  log "---"
  log_cmd "for b in $(ls -1 $base_dir/var/spool/cron/*); do echo; echo \$b; echo \"===\"; cat \$b; echo \"===\"; done"
  log "---"
  log


  log_tee "## Files in etc/cron*"
  log

  log "// all files located on /etc/cron*"
  log "find $base_dir/etc/cron* -type f | awk 'FS=\"/etc/\" {print \$2}'"
  log "---"
  log_cmd "find $base_dir/etc/cron* -type f | awk 'FS=\"/etc/\" {print \$2}'"
  log "---"
  log


  log_tee "## Foreman Settings"
  log

  log "// foreman settings"
  log "cat $base_foreman/etc/foreman/settings.yaml"
  log "---"
  log_cmd "cat $base_foreman/etc/foreman/settings.yaml"
  log "---"
  log

  log "// custom hiera"
  log "cat $base_foreman/etc/foreman-installer/custom-hiera.yaml"
  log "---"
  log_cmd "cat $base_foreman/etc/foreman-installer/custom-hiera.yaml"
  log "---"
  log


  log_tee "## Tuning"
  log

  log "// 05-foreman.conf configuration"
  log "cat $base_dir/etc/httpd/conf.d/05-foreman.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout|PassengerMinInstances'"
  log "---"
  log_cmd "cat $base_dir/etc/httpd/conf.d/05-foreman.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout|PassengerMinInstances'"
  log "---"
  log

  log "// 05-foreman-ssl.conf configuration"
  log "cat $base_dir/etc/httpd/conf.d/05-foreman-ssl.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout|PassengerMinInstances'"
  log "---"
  log_cmd "cat $base_dir/etc/httpd/conf.d/05-foreman-ssl.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout|PassengerMinInstances'"
  log "---"
  log

  log "// katello.conf configuration"
  log "cat $base_dir/etc/httpd/conf.d/05-foreman-ssl.d/katello.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout'"
  log "---"
  log_cmd "cat $base_dir/etc/httpd/conf.d/05-foreman-ssl.d/katello.conf | $EGREP 'KeepAlive\b|MaxKeepAliveRequests|KeepAliveTimeout'"
  log "---"
  log

  log "// pulp_workers configuration"
  log "cat $base_dir/etc/default/pulp_workers | $EGREP '^PULP_MAX_TASKS_PER_CHILD|^PULP_CONCURRENCY'"
  log "---"
  log_cmd "cat $base_dir/etc/default/pulp_workers | $EGREP '^PULP_MAX_TASKS_PER_CHILD|^PULP_CONCURRENCY'"
  log "---"
  log

  log "// postgres configuration"
  log "cat $base_dir/var/lib/pgsql/data/postgresql.conf | $EGREP 'max_connections|shared_buffers|work_mem|checkpoint_segments|checkpoint_completion_target' | $GREP -v '^#'"
  log "---"
  log_cmd "cat $base_dir/var/lib/pgsql/data/postgresql.conf | $EGREP 'max_connections|shared_buffers|work_mem|checkpoint_segments|checkpoint_completion_target' | $GREP -v '^#'"
  log "---"
  log

  log "// tomcat configuration"
  log "cat $base_dir/etc/tomcat/tomcat.conf | $GREP -F 'JAVA_OPTS'"
  log "---"
  log_cmd "cat $base_dir/etc/tomcat/tomcat.conf | $GREP -F 'JAVA_OPTS'"
  log "---"
  log

  log "// httpd|apache limits"
  log "cat $base_dir/etc/systemd/system/httpd.service.d/limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log_cmd "cat $base_dir/etc/systemd/system/httpd.service.d/limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log

  log "// qrouterd limits"
  log "cat $base_dir/etc/systemd/system/qdrouterd.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log_cmd "cat $base_dir/etc/systemd/system/qdrouterd.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log

  log "// qpidd limits"
  log "cat $base_dir/etc/systemd/system/qpidd.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log_cmd "cat $base_dir/etc/systemd/system/qpidd.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log

  log "// smart proxy dynflow core limits"
  log "cat $base_dir/etc/systemd/system/smart_proxy_dynflow_core.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log_cmd "cat $base_dir/etc/systemd/system/smart_proxy_dynflow_core.service.d/90-limits.conf | $GREP -F 'LimitNOFILE'"
  log "---"
  log

  log "// sysctl configuration"
  log "cat $base_dir/etc/sysctl.conf | $GREP -F 'fs.aio-max-nr'"
  log "---"
  log_cmd "cat $base_dir/etc/sysctl.conf | $GREP -F 'fs.aio-max-nr'"
  log "---"
  log

  log "// Used answer file during the satellite-installer run"
  log "cat $base_dir/etc/foreman-installer/scenarios.d/satellite.yaml | grep answer"
  log "---"
  log_cmd "cat $base_dir/etc/foreman-installer/scenarios.d/satellite.yaml | grep answer"
  log "---"
  log

  log "// Current tuning preset"
  log "cat $base_dir/etc/foreman-installer/scenarios.d/satellite.yaml | grep tunin"
  log "---"
  log_cmd "cat $base_dir/etc/foreman-installer/scenarios.d/satellite.yaml | grep tunin"
  log "---"
  log

  log_tee "### Welcome to Report ###"
  log_tee "### CEE/Anaconda ###"
  log
  log

  log_tee "## LEAPP"
  log

  log "// Checking for leapp package"
  log "grep leapp $base_dir/installed-rpms | sort"
  log "---"
  log_cmd "grep leapp $base_dir/installed-rpms | sort"
  log "---"
  log "NOTE. You need version 0.16.0 or later of the leapp package and version 0.19.0 or later of the leapp-repository package, which contains the leapp-upgrade-el7toel8 RPM package."
  log

  log "// Checking for grub package"
  log "grep grub $base_dir/installed-rpms | sort"
  log "---"
  log_cmd "grep grub $base_dir/installed-rpms | sort"
  log "---"
  log

  log "// Checking for grub/grub2 folders"
  log "ls -l $base_dir/boot/"
  log "---"
  log_cmd "ls -l $base_dir/boot/"
  log "---"
  log

  log "// Checking the current default grub content"
  log "cat $base_dir/etc/default/grub"
  log "---"
  log_cmd "cat $base_dir/etc/default/grub"
  log "---"
  log

  log "// Checking the upgrade entry on grub2 menu"
  log "grep upgrade $base_dir/boot/grub2/grub.cfg"
  log "---"
  log_cmd "grep upgrade $base_dir/boot/grub2/grub.cfg"
  log "---"
  log

  log "// Checking for inhibitor"
  log "grep inhibitor -A1 $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log_cmd "grep inhibitor -A1 $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log

  log "// Full inhibitor list"
  log "cat $base_dir/var/log/leapp/leapp-report.txt | awk 'BEGIN {} /.*inhibitor.*/,/^---/ { print } END {}'"
  log "---"
  log_cmd "cat $base_dir/var/log/leapp/leapp-report.txt | awk 'BEGIN {} /.*inhibitor.*/,/^---/ { print } END {}'"
  log "---"
  log

  log "// Checking for error"
  log "grep \"(error)\" -A1 $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log_cmd "grep \"(error)\" -A1 $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log

  log "// Full error list"
  log "cat $base_dir/var/log/leapp/leapp-report.txt | awk 'BEGIN {} /.*\(error\).*/,/^---/ { print } END {}'"
  log "---"
  log_cmd "cat $base_dir/var/log/leapp/leapp-report.txt | awk 'BEGIN {} /.*\(error\).*/,/^---/ { print } END {}'"
  log "---"
  log

  log "// Unsupported LEAPP?"
  log "grep -o LEAPP_UNSUPPORTED.* $base_dir/var/log/leapp/leapp-upgrade.log | awk '{print \$1}' | sort -u | sed \"s/',//g\""
  log "---"
  log_cmd "grep -o LEAPP_UNSUPPORTED.* $base_dir/var/log/leapp/leapp-upgrade.log | awk '{print \$1}' | sort -u | sed \"s/',//g\""
  log "---"
  log

  log "// Target Version - Supported 8.6, 8.8 and 8.9"
  log "grep -o LEAPP_UPGRADE_PATH_TARGET_RELEASE.* $base_dir/var/log/leapp/leapp-upgrade.log | awk '{print \$1}' | sort -u | sed \"s/',//g\""
  log "---"
  log_cmd "grep -o LEAPP_UPGRADE_PATH_TARGET_RELEASE.* $base_dir/var/log/leapp/leapp-upgrade.log | awk '{print \$1}' | sort -u | sed \"s/',//g\""
  log "---"
  log

  log "// Failed with exit"
  log "grep \"failed with exit\" $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log_cmd "grep \"failed with exit\" $base_dir/var/log/leapp/leapp-report.txt"
  log "---"
  log

  log "// overlay filesystem"
  log "grep overlay $base_dir/mount"
  log "---"
  log_cmd "grep overlay $base_dir/mount"
  log "---"
  log

  log "// Error in the leapp-upgrade.log"
  log "grep ERROR $base_dir/var/log/leapp/leapp-upgrade.log"
  log "---"
  log_cmd "grep ERROR $base_dir/var/log/leapp/leapp-upgrade.log"
  log "---"
  log

  log "// Last lines of leapp-upgrade.log"
  log "tail -n 40 $base_dir/var/log/leapp/leapp-upgrade.log"
  log "---"
  log_cmd "tail -n 40 $base_dir/var/log/leapp/leapp-upgrade.log"
  log "---"
  log



  # Insights call, in case the binary is around
  which insights &>/dev/null

  if [ $? -eq 0 ]; then
    log "Calling insights ..."
    $(which insights) run -p shared_rules,telemetry,threescale_rules,ccx_ocp_core,ccx_rules_ocp $sos_path >> $FOREMAN_REPORT
    echo "done."
  fi


  if [ $COPY_TO_CURRENT_DIR ] || [ $OPEN_IN_VIM_RO_LOCAL_DIR ]; then
    echo 
    echo
    echo "## Creating a copy of the report in your current directory - $MYPWD/report_${USER}_$final_name.log"
    cp $FOREMAN_REPORT $MYPWD/report_${USER}_$final_name.log
  fi

  mv $FOREMAN_REPORT /tmp/report_${USER}_$final_name.log
  echo 
  echo
  echo "## Please check out the file /tmp/report_${USER}_$final_name.log"


}




# Main

if [ "$1" == "" ] || [ "$1" == "--help" ]; then
  echo "Please inform the path to the sosrepor dir that you would like to analyze."
  echo "$0 [OPTION] 01234567/sosreport_do_wall"
  echo ""
  echo "OPTION"
  echo "You can add a flags after $0 as informed below"
  echo "   -c copies the output file from the /tmp directory to the current directory"
  echo "   -l opens the output file from the current directory"
  echo "   -t opens the output file from the /tmp directory"
  exit 1
fi

main $1


# the following code will open the requested report
# in the user's editor of choice
# if none is defined, "less" will be chosen.

if [ ! "$EDITOR" ]; then
   EDITOR=`which less`
fi

if [ $OPEN_IN_VIM_RO_LOCAL_DIR ]; then
   $EDITOR -R $MYPWD/report_${USER}_$final_name.log
fi

if [ $OPEN_IN_EDITOR_TMP_DIR ]; then
   #echo placeholder 
   $EDITOR /tmp/report_${USER}_$final_name.log
fi

