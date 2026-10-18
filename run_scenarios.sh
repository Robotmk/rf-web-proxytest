#!/usr/bin/env bash
# Spielt die Proxy-Szenarien durch und protokolliert, über welchen Proxy der Traffic geht.
#
#   Proxy A = localhost:3128 (per RCC-Profil bzw. Proxy-Env-Variablen)
#   Proxy B = localhost:3129 (nur explizit im Test gesetzt: New Browser proxy= und RequestsLibrary proxies=)
#
# Aufruf: ./run_scenarios.sh [--proxy-from profile|env] [--auth] [--fail] [Nr ...]
#
# rcc baut und aktiviert immer das Environment, robot läuft immer über "rcc task script".
# Unterschied der Modi ist nur, woher die Proxy-Variablen für Proxy A kommen:
#
#   --proxy-from profile  (Default) RCC-Proxyprofil erzeugen und aktivieren
#   --proxy-from env      kein RCC-Profil; das Skript setzt HTTP(S)_PROXY/NO_PROXY selbst und
#                         "rcc task script" vererbt sie an robot (Gegenprobe zum Profil)
#   --auth   Proxies verlangen Benutzer/Passwort (Env-Variablen/RCC-Profil bzw. New Browser proxy= und RequestsLibrary proxies=)
#   --fail   zusätzlich Szenario 5: NO_PROXY fehlt (vor Browser Library 20.4.0 scheiterte daran die
#            interne gRPC-Verbindung; hier wird nur 20.6.0 getestet)
#   Nr ...   nur diese Szenarien, z. B. "./run_scenarios.sh --fail 5"
#
# Ergebnisse: results/<profile|env>[-auth]/scenarioN/ und .../summary.txt
set -uo pipefail
cd "$(dirname "$0")"

MODE=profile; AUTH=0; FAIL=0; SELECTED=()
while (($#)); do
  case $1 in
    --proxy-from) MODE=${2:-}; shift ;;
    --proxy-from=*) MODE=${1#*=} ;;
    --auth) AUTH=1 ;;
    --fail) FAIL=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    [0-9]*) SELECTED+=("$1") ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ $MODE == profile || $MODE == env ]] || { echo "--proxy-from erwartet profile oder env" >&2; exit 2; }

# Nur die Variablen dieses Skripts bzw. des RCC-Profils sollen wirken, nicht die der aufrufenden Shell
# (rcc task script vererbt die Umgebung des aufrufenden Prozesses).
unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy

IMAGE=mitmproxy/mitmproxy
PROXY_USER=proxyuser
PROXY_PASS=s3cr3t
NO_PROXY_LIST=localhost,127.0.0.1
TIMEOUT=${TIMEOUT:-120}   # Sekunden pro robot-Lauf; ein hängender Test blockiert so nicht den ganzen Lauf
ROBOT_YAML=robot.yaml     # Browser Library 20.6.0 (conda.yaml)
SPACE=proxytest
RUN=$MODE$( ((AUTH)) && echo -auth)
RESULTS=results/$RUN

PROXY_A=http://localhost:3128
((AUTH)) && PROXY_A=http://$PROXY_USER:$PROXY_PASS@localhost:3128

#  Nr Proxy A  NO_PROXY  Browser-Resource                    Erwartung
SCENARIOS=(
  "1 A    ja   resources/noproxy.resource  PASS"
  "2 A    ja   resources/proxyB.resource   PASS"
  "3 -    -    resources/noproxy.resource  PASS"
  "4 -    -    resources/proxyB.resource   PASS"
)
((FAIL)) && SCENARIOS+=(
  "5 A    nein resources/noproxy.resource  PASS"
)

# --- Hilfsfunktionen -------------------------------------------------------------------------

start_proxy() {  # name hostport
  local auth=() curl_auth=()
  if ((AUTH)); then auth=(--proxyauth "$PROXY_USER:$PROXY_PASS"); curl_auth=(-U "$PROXY_USER:$PROXY_PASS"); fi
  docker rm -f "$1" >/dev/null 2>&1
  # mitmdump bricht TLS auf und loggt so auch jeden HTTPS-Request (Browser: ignoreHTTPSErrors=True).
  # Im Container zeigt 127.0.0.1 auf den Container selbst, wie bei einem echten Proxy auf seinen eigenen Host.
  docker run -d --name "$1" -p "$2":8080 "$IMAGE" mitmdump ${auth[@]+"${auth[@]}"} >/dev/null
  until curl -s -o /dev/null ${curl_auth[@]+"${curl_auth[@]}"} -x "http://localhost:$2" http://mitm.it 2>/dev/null; do
    sleep 0.5
  done
}

restart_proxies() {
  start_proxy proxyA 3128
  start_proxy proxyB 3129
}

save_proxy_logs() {  # dir
  docker logs proxyA >"$1/proxyA.log" 2>&1
  docker logs proxyB >"$1/proxyB.log" 2>&1
}

hosts_in() {  # logfile -> Ziele (ohne Readiness-Check mitm.it)
  grep -oE ': (GET|POST|CONNECT) [^ ]+' "$1" | grep -v 'mitm.it' |
    sed -E 's/^: [A-Z]+ //' | sort -u | tr '\n' ' '
}

count_407() {  # logfile -> Anzahl abgewiesener Requests ohne gültige Proxy-Auth
  grep -c '<< 407' "$1"
}

kill_tree() {  # pid: Prozess samt Kindern (rcc -> robot -> node -> chromium) beenden
  # SIGKILL: Auf SIGTERM beendet sich robot "sauber" und ruft dabei hängende Listener erneut auf.
  local child
  kill -STOP "$1" 2>/dev/null
  for child in $(pgrep -P "$1"); do kill_tree "$child"; done
  kill -KILL "$1" 2>/dev/null
}

run_limited() {  # logfile cmd... -> rc des Kommandos, 124 bei Timeout
  local log=$1 waited=0; shift
  "$@" >"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ((waited >= TIMEOUT)); then
      kill_tree "$pid"; wait "$pid" 2>/dev/null
      echo "### Abgebrochen nach ${TIMEOUT}s (run_scenarios.sh)" >>"$log"
      return 124
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid"
}

rcc_profile_for() {  # noproxy(ja|nein) -> Profilname; schreibt profiles/<name>.yaml und importiert es
  local name=proxytest-a
  ((AUTH)) && name+=-auth
  [[ $1 == nein ]] && name+=-nonoproxy
  local file=profiles/$name.yaml
  {
    echo "name: $name"
    echo "description: RCC-Proxyprofil -> mitmproxy A (localhost:3128)"
    echo "settings:"
    echo "  certificates:"
    echo "    verify-ssl: false"
    echo "  network:"
    [[ $1 == ja ]] && echo "    no-proxy: '$NO_PROXY_LIST'"
    echo "    https-proxy: '$PROXY_A'"
    echo "    http-proxy: '$PROXY_A'"
    echo "  meta:"
    echo "    name: $name"
    echo "    description: RCC-Proxyprofil -> mitmproxy A (localhost:3128)"
    echo "    source: Robotmk"
  } >"$file"
  rcc config import -f "$file" >/dev/null 2>&1
  echo "$name"
}

# --- Vorbereitung ----------------------------------------------------------------------------

BROWSER_VERSION=$(grep -oE 'robotframework-browser==[0-9.]+' conda.yaml | cut -d= -f3)

mkdir -p "$RESULTS" profiles
SUMMARY=$RESULTS/summary.txt
: >"$SUMMARY"

ORIG_PROFILE=$(rcc config switch 2>/dev/null | sed -n 's/^Currently active profile is: //p')

cleanup() {
  docker rm -f proxyA proxyB >/dev/null 2>&1
  if [[ -n ${ORIG_PROFILE:-} && $ORIG_PROFILE != default ]]; then
    rcc config switch -p "$ORIG_PROFILE" >/dev/null 2>&1
  else
    rcc config switch -n >/dev/null 2>&1
  fi
  echo "RCC-Profil zurückgesetzt auf: ${ORIG_PROFILE:-<keins>}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Environment ohne Profil bauen bzw. prüfen, damit der erste Testlauf nicht in den Timeout läuft
echo "Environment vorbereiten (rcc ht vars, beim ersten Mal dauert das) ..."
rcc config switch -n >/dev/null 2>&1
rcc ht vars -r "$ROBOT_YAML" --space "$SPACE" >/dev/null 2>&1 || { echo "rcc ht vars fehlgeschlagen" >&2; exit 1; }

{
  echo "Lauf: $RUN | Proxy A: $PROXY_A | Proxy B: http://localhost:3129$( ((AUTH)) && echo " (Auth $PROXY_USER:$PROXY_PASS)")"
  echo
} | tee -a "$SUMMARY"

# --- Szenarien -------------------------------------------------------------------------------

for entry in "${SCENARIOS[@]}"; do
  read -r nr proxy noproxy resource expect <<<"$entry"
  if [[ ${#SELECTED[@]} -gt 0 && ! " ${SELECTED[*]} " =~ " $nr " ]]; then continue; fi
  dir=$RESULTS/scenario$nr
  rm -rf "$dir"; mkdir -p "$dir"
  echo "=== Szenario $nr: Proxy A=$proxy, NO_PROXY=$noproxy, Browser $BROWSER_VERSION, $(basename "$resource") ==="

  robot_args=(-v "SCENARIO_RESOURCE:$resource" -d "$dir" --console verbose)
  ((AUTH)) && robot_args+=(-v "PROXY_USER:$PROXY_USER" -v "PROXY_PASS:$PROXY_PASS")
  robot_args+=(proxy.robot)

  restart_proxies

  # profile: Proxy A kommt aus dem RCC-Profil. env: kein Profil, dieselben Variablen, die rcc mit dem
  # Profil setzen würde, stehen in der Umgebung des rcc-Prozesses und werden an robot vererbt.
  proxy_env=()
  if [[ $MODE == profile && $proxy == A ]]; then
    profile=$(rcc_profile_for "$noproxy")
    rcc config switch -p "$profile" >/dev/null 2>&1
  else
    rcc config switch -n >/dev/null 2>&1
    if [[ $proxy == A ]]; then
      proxy_env=(HTTP_PROXY=$PROXY_A HTTPS_PROXY=$PROXY_A http_proxy=$PROXY_A https_proxy=$PROXY_A)
      [[ $noproxy == ja ]] && proxy_env+=(NO_PROXY=$NO_PROXY_LIST no_proxy=$NO_PROXY_LIST)
    fi
  fi
  printf '%s\n' ${proxy_env[@]+"${proxy_env[@]}"} >"$dir/caller_env.txt"
  rcc config switch >"$dir/rcc_profile.txt" 2>&1
  # rcc ht vars mit derselben Umgebung wie der Testlauf: zeigt nur, was rcc selbst setzt
  env ${proxy_env[@]+"${proxy_env[@]}"} rcc ht vars -r "$ROBOT_YAML" --space "$SPACE" >"$dir/htvars.txt" 2>&1
  run_limited "$dir/robot_console.txt" \
    env ${proxy_env[@]+"${proxy_env[@]}"} \
    rcc task script -r "$ROBOT_YAML" --space "$SPACE" --silent -- robot "${robot_args[@]}"
  rc=$?

  save_proxy_logs "$dir"

  result=PASS; ((rc != 0)) && result=FAIL
  verdict="wie erwartet"; [[ $result != "$expect" ]] && verdict="UNERWARTET (erwartet $expect)"
  ((rc == 124)) && result="FAIL (Timeout ${TIMEOUT}s)"
  {
    echo "Szenario $nr | Proxy A: $proxy | NO_PROXY: $noproxy | Browser $BROWSER_VERSION | $(basename "$resource")"
    echo "  Ergebnis:         $result, $verdict"
    echo "  Env im Test:      $(grep -oE '(HTTPS?_PROXY|NO_PROXY)=(<nicht gesetzt>|[^ ]*)' "$dir/robot_console.txt" | tr '\n' ' ')"
    echo "  Test -> Proxy A:  $(hosts_in "$dir/proxyA.log")"
    echo "  Test -> Proxy B:  $(hosts_in "$dir/proxyB.log")"
    ((AUTH)) && echo "  407 (ohne Auth):  Proxy A $(count_407 "$dir/proxyA.log")x, Proxy B $(count_407 "$dir/proxyB.log")x"
    grpc=$(grep -m1 -oE 'Could not connect to the playwright process at [0-9.:]*[0-9]' "$dir/robot_console.txt")
    [[ -n $grpc ]] && echo "  gRPC-Fehler:      $grpc"
    echo
  } | tee -a "$SUMMARY"
done
