#!/bin/bash

# Auto-select best PIA region based on latency
# Returns the region ID with lowest latency

select_best_region() {
  local max_latency="${1:-0.05}"
  local require_pf="${2:-0}"
  local serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v6'
  
  echo "Fetching PIA server list..." >&2
  
  local all_region_data
  all_region_data=$(curl -s "$serverlist_url" | head -1)
  
  if [[ ${#all_region_data} -lt 1000 ]]; then
    echo "ERROR: Could not fetch server list" >&2
    return 1
  fi
  
  # Build jq filter based on port forwarding requirement
  local jq_filter='.regions[]'
  if [[ "$require_pf" == "1" ]]; then
    echo "Filtering for port-forwarding capable regions..." >&2
    jq_filter="$jq_filter | select(.port_forward==true)"
  fi
  
  # Extract server list (IP, region_id, region_name)
  local regions
  regions=$(echo "$all_region_data" | jq -r "$jq_filter | .servers.meta[0].ip + \" \" + .id + \" \" + .name")
  
  if [[ -z "$regions" ]]; then
    echo "ERROR: No regions found" >&2
    return 1
  fi
  
  local best_time=999
  local best_region=""
  local best_name=""
  local test_count=0
  local success_count=0
  
  echo "Testing regions (max latency: ${max_latency}s)..." >&2
  
  # Create temp file for results (to avoid subshell variable issues)
  local tmpfile="/tmp/region_latency_$$.txt"
  
  while IFS=' ' read -r ip region_id region_name; do
    ((test_count++))
    
    local time
    local curl_output
    # Use a reasonable minimum timeout (curl can't reliably timeout faster than ~10ms)
    local effective_timeout="$max_latency"
    if (( $(echo "$max_latency < 0.01" | bc -l) )); then
      effective_timeout="0.01"
    fi
    
    curl_output=$(LC_NUMERIC=en_US.utf8 curl -o /dev/null -s \
      --connect-timeout "$effective_timeout" \
      --write-out "%{time_connect}:%{exitcode}" \
      "http://$ip:443" 2>/dev/null) || true
    
    time=$(echo "$curl_output" | cut -d: -f1)
    local exit_code=$(echo "$curl_output" | cut -d: -f2)
    
    # Only count as success if curl succeeded (exit 0) AND time is under max_latency
    if [[ "$exit_code" == "0" ]] && [[ -n "$time" ]] && (( $(echo "$time < $max_latency" | bc -l 2>/dev/null || echo 0) )); then
      echo "  ✓ $region_name ($region_id): ${time}s" >&2
      echo "$time $region_id $region_name" >> "$tmpfile"
      ((success_count++))
    fi
  done <<< "$regions"
  
  if [[ !  -f "$tmpfile" ]] || [[ !  -s "$tmpfile" ]]; then
    echo "ERROR: No regions responded within ${max_latency}s (tested $test_count regions)" >&2
    rm -f "$tmpfile"
    return 1
  fi
  
  # Sort by latency and get best
  local best_line
  best_line=$(sort -n "$tmpfile" | head -1)
  best_time=$(echo "$best_line" | awk '{print $1}')
  best_region=$(echo "$best_line" | awk '{print $2}')
  best_name=$(echo "$best_line" | cut -d' ' -f3-)
  
  rm -f "$tmpfile"
  
  echo "" >&2
  echo "✓ Selected:  $best_name ($best_region) - ${best_time}s latency ($success_count/$test_count regions responded)" >&2
  echo "" >&2
  
  # Output only the region ID to stdout
  echo "$best_region"
  return 0
}

# If called directly, run the selection
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  select_best_region "$@"
fi