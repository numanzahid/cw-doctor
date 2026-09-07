#!/usr/bin/env bash

_cw_traffic_crawler_file() {
  [[ -f "$CW_CRAWLERS_FILE" ]] && printf '%s' "$CW_CRAWLERS_FILE"
}

cw_traffic_cmd() {
  local app="$1"
  app="$(cw_apps_require_app "$app")"
  local base logs_dir access
  base="$(cw_apps_resolve "$app")"
  logs_dir="$(cw_apps_logs_dir "$base")"
  access="$(cw_logs_find_access "$logs_dir")" || _cw_die "no readable access log for $app"

  local fp sample lines
  fp="$(cw_logs_fingerprint_combined "$access")"
  [[ "$fp" == combined ]] || _cw_die "unsupported access log format: $fp"

  sample="$(cw_logs_sample_file "$access" "$CW_TRAFFIC_SAMPLE_LINES")"
  lines="$(echo "$sample" | wc -l)"

  _cw_section "Traffic: $app"
  _cw_observed "Analyzed $(cw_logs_sample_meta)"

  local crawler_file
  crawler_file="$(_cw_traffic_crawler_file)"

  echo "$sample" | awk -v crawler_file="$crawler_file" '
  BEGIN {
    FS = ""
    # Load crawler patterns from JSON (simple substring match on "pattern" fields)
    if (crawler_file != "") {
      while ((getline line < crawler_file) > 0) {
        if (match(line, /"pattern"[[:space:]]*:[[:space:]]*"([^"]+)"/, pm)) {
          gsub(/\\\\/, "\\", pm[1])
          crawlers[++nc] = pm[1]
        }
      }
      close(crawler_file)
    }
  }
  function is_crawler(ua,    i, p) {
    for (i = 1; i <= nc; i++) {
      p = crawlers[i]
      if (index(ua, p) > 0) return 1
    }
    return 0
  }
  function parse_line(line) {
    if (!match(line, /^([^ ]+) [^ ]+ [^ ]+ \[[^]]+\] "([A-Z]+) ([^ ]+) [^"]+" ([0-9]{3}) [0-9]+ "([^"]*)" "([^"]*)"/, parts))
      return 0
    client_ip = parts[1]; req_method = parts[2]; req_path = parts[3]; req_status = parts[4]+0
    req_ua = parts[6]
    return 1
  }
  {
    if (!parse_line($0)) next
    n++
    methods[req_method]++
    scodes[req_status]++
    clients[client_ip]++
    ip_paths[client_ip SUBSEP req_path] = 1
    uagents[req_ua]++
    paths[req_path]++
    if (req_status >= 400) ip_err[client_ip]++
    if (req_status == 404) err404[req_path]++
    if (req_status >= 500) err5xx[req_path]++
    if (req_path ~ /[?&]/) dynamic++
    if (req_path ~ /wp-cron\.php/) wp_cron++
    if (req_path ~ /admin-ajax\.php/) {
      wp_ajax++
      if (match(req_path, /action=([^&]+)/, ajax_parts)) ajax_act[ajax_parts[1]]++
    }
    if (req_path ~ /wp-login\.php/) wp_login++
    if (req_path ~ /xmlrpc\.php/) xmlrpc++
    if (req_path ~ /wp-json/) wp_json++
    if (req_path ~ /wc\/store\//) wc_store++
    if (req_path ~ /[?&]s=/) search_q++
    if (is_crawler(req_ua)) crawler_ua[req_ua]++
    ip_dyn[client_ip]++
  }
  END {
    print ""
    print "== Request summary =="
    printf "Total requests (sample): %d\n", n
    if (n > 0) {
      for (mk in methods) printf "  %s: %d\n", mk, methods[mk]
      print "Status codes:"
      for (code in scodes) printf "  %d: %d\n", code, scodes[code]
    }

    print ""
    print "== Top IPs (max 15) =="
    num = asorti(clients, sorted_ip, "@val_num_desc")
    shown = 0
    for (i = 1; i <= num && shown < 15; i++) {
      k = sorted_ip[i]
      uniq = 0
      for (p in ip_paths) if (index(p, k SUBSEP) == 1) uniq++
      err = ip_err[k]+0
      printf "  %s  reqs=%d unique_paths~=%d 4xx5xx=%d\n", k, clients[k], uniq, err
      shown++
    }

    print ""
    print "== Top user agents (max 10) =="
    num = asorti(uagents, sorted_ua, "@val_num_desc")
    for (i = 1; i <= num && i <= 10; i++)
      printf "  %d  %s\n", uagents[sorted_ua[i]], sorted_ua[i]

    print ""
    print "== Top paths (max 15) =="
    num = asorti(paths, sorted_p, "@val_num_desc")
    for (i = 1; i <= num && i <= 15; i++)
      printf "  %d  %s\n", paths[sorted_p[i]], sorted_p[i]

    print ""
    print "== WordPress routes =="
    printf "  wp-cron.php: %d\n", wp_cron+0
    printf "  admin-ajax.php: %d\n", wp_ajax+0
    if (length(ajax_act) > 0) {
      print "  top admin-ajax actions:"
      num = asorti(ajax_act, sa, "@val_num_desc")
      for (i = 1; i <= num && i <= 10; i++)
        printf "    %d  action=%s\n", ajax_act[sa[i]], sa[i]
    }
    printf "  wp-login.php: %d\n", wp_login+0
    printf "  xmlrpc.php: %d\n", xmlrpc+0
    printf "  wp-json: %d\n", wp_json+0
    printf "  wc/store API: %d\n", wc_store+0
    printf "  search queries: %d\n", search_q+0
    printf "  URLs with query string: %d (%.1f%%)\n", dynamic+0, (dynamic+0)*100/n

    if (length(err404) > 0) {
      print ""
      print "== Top 404 paths (max 10) =="
      num = asorti(err404, s4, "@val_num_desc")
      for (i = 1; i <= num && i <= 10; i++)
        printf "  %d  %s\n", err404[s4[i]], s4[i]
    }
    if (length(err5xx) > 0) {
      print ""
      print "== Top 5xx paths (max 10) =="
      num = asorti(err5xx, s5, "@val_num_desc")
      for (i = 1; i <= num && i <= 10; i++)
        printf "  %d  %s\n", err5xx[s5[i]], s5[i]
    }

    if (length(crawler_ua) > 0) {
      print ""
      print "== Known crawler user agents (pattern list) =="
      num = asorti(crawler_ua, sc, "@val_num_desc")
      for (i = 1; i <= num && i <= 15; i++)
        printf "  %d  %s\n", crawler_ua[sc[i]], sc[i]
    }

    print ""
    print "== Possible automated traffic (behavioral, NOT ESTABLISHED as bots) =="
    high_div = 0
    for (k in clients) {
      uniq = 0
      for (p in ip_paths) if (index(p, k SUBSEP) == 1) uniq++
      if (clients[k] >= 20 && uniq >= 15) {
        printf "  IP %s: %d reqs, ~%d unique paths\n", k, clients[k], uniq
        high_div++
      }
    }
    if (high_div == 0) print "  No strong distributed pattern in sample"
    print ""
    print "NOT ESTABLISHED: labeling bots from IP or UA alone is intentionally avoided"
  }
  '

  echo ""
  _cw_likely "Suspicious traffic load: review Top IPs and behavioral section"
}

cw_traffic_help() {
  echo "Usage: cw traffic APP"
  echo "Bounded access-log traffic analysis."
}
