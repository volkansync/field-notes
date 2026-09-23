#!/usr/bin/env bash
# bt-dropout-test.sh — 2x2 A/B test: Wi-Fi band x power saving, measured against
# PipeWire xrun counters on the Bluetooth sink.
#
# Hypothesis under test:
#   Bluetooth audio dropouts are caused by Wi-Fi power saving on the 2.4 GHz band
#   (shared radio / shared band), not by the Bluetooth stack itself.
#
# Metric: cumulative xruns (ERR) on the bluez_output node, sampled per arm.
#         An xrun is a buffer underrun — the audible "cut out".
#
# Usage:  ./bt-dropout-test.sh [seconds-per-arm]      (default 900 = 15 min)
#         ./bt-dropout-test.sh 120                     quick sanity run

set -uo pipefail

ARM=${1:-900}
OUT="bt-test-$(date +%Y%m%d-%H%M).csv"
SAMPLE=10                     # seconds between signal samples

# ── configure these for your network ──────────────────────────────────────────
CONN=""                             # empty = auto-detect active connection
BSSID_24="04:DA:D2:CF:A1:E0"        # 2.4 GHz radio
BSSID_50="04:DA:D2:CF:A1:EF"        # 5 GHz radio (same AP)
# ──────────────────────────────────────────────────────────────────────────────

c()  { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
hdr(){ echo; c '1;35' "── $* ─────────────────────────────────────────"; }
die(){ c '1;31' "HATA: $*"; exit 1; }

# ── preflight ────────────────────────────────────────────────────────────────
WIFI=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
[[ -n $WIFI ]] || die "Wi-Fi arayüzü bulunamadı."

[[ -n $CONN ]] || CONN=$(nmcli -t -f NAME,TYPE connection show --active |
                         awk -F: '$2 ~ /wireless/{print $1; exit}')
[[ -n $CONN ]] || die "Aktif Wi-Fi bağlantısı yok."

command -v pw-top >/dev/null || die "pw-top yok (pipewire kurulu mu?)."

# Bluetooth sink must be active — that means music has to be playing already.
bt_node() { pw-top -b -n 1 2>/dev/null | awk '/bluez_output/{print $NF; exit}'; }
[[ -n $(bt_node) ]] || die "Bluetooth ses çıkışı aktif değil.
       Kulaklığı bağla, müziği BAŞLAT, sonra scripti çalıştır."

if [[ -z $BSSID_24 || -z $BSSID_50 ]]; then
  c '1;33' "BSSID_24 / BSSID_50 boş — sadece mevcut bantta test edilecek."
  c '0;37'  "Dört hücre için scriptin başındaki iki değişkeni doldur:"
  nmcli -f SSID,FREQ,BSSID device wifi list | grep -i "$(nmcli -t -f 802-11-wireless.ssid \
        connection show "$CONN" | cut -d: -f2)" || true
fi

sudo -v || die "sudo gerekli (power_save ayarı için)."
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
KEEPALIVE=$!

# ── state restore on any exit ────────────────────────────────────────────────
restore() {
  echo
  c '1;33' "Eski duruma dönülüyor…"
  sudo iw dev "$WIFI" set power_save off 2>/dev/null
  nmcli connection modify "$CONN" 802-11-wireless.bssid "" 2>/dev/null
  nmcli connection up "$CONN" >/dev/null 2>&1
  kill $KEEPALIVE 2>/dev/null
  c '0;32' "power_save=off, BSSID sabitlemesi kaldırıldı."
}
trap restore EXIT INT TERM

# ── helpers ──────────────────────────────────────────────────────────────────
errs()   { pw-top -b -n 1 2>/dev/null | awk '/bluez_output/{print $9; exit}'; }
freq()   { iw dev "$WIFI" link 2>/dev/null | awk '/freq/{print int($2); exit}'; }
signal() { iw dev "$WIFI" link 2>/dev/null | awk '/signal/{print $2; exit}'; }

pin_band() {                                     # $1 = 24 | 50
  local b; [[ $1 == 24 ]] && b=$BSSID_24 || b=$BSSID_50
  [[ -n $b ]] || return 1
  nmcli connection modify "$CONN" 802-11-wireless.bssid "$b" || return 1
  nmcli connection up "$CONN" >/dev/null 2>&1
  sleep 6
  local f; f=$(freq)
  [[ $1 == 24 && $f -lt 3000 ]] || [[ $1 == 50 && $f -gt 4000 ]] || {
    c '1;31' "Bant değişmedi (freq=$f). Bu kol atlanıyor."; return 1; }
  return 0
}

run_arm() {                                      # $1=band-label  $2=on|off
  local band=$1 ps=$2
  sudo iw dev "$WIFI" set power_save "$ps"
  sleep 3
  local actual_ps; actual_ps=$(iw dev "$WIFI" get power_save | awk '{print $3}')
  [[ $actual_ps == "$ps" ]] || c '1;31' "UYARI: power_save=$actual_ps (istenen $ps)"

  hdr "$band GHz · power_save=$ps · ${ARM}s"
  local e0 f0 sigsum=0 n=0
  e0=$(errs); f0=$(freq)
  c '0;37' "başlangıç xrun=$e0  freq=${f0}MHz"

  local t=0
  while (( t < ARM )); do
    sleep "$SAMPLE"; t=$((t+SAMPLE))
    local s; s=$(signal); [[ -n $s ]] && { sigsum=$(echo "$sigsum + $s" | bc); n=$((n+1)); }
    printf '\r  %3ds/%ds   xrun=%s   sinyal=%s dBm   ' "$t" "$ARM" "$(errs)" "$s"
  done
  echo

  local e1 d avg
  e1=$(errs); d=$(( e1 - e0 ))
  avg=$( [[ $n -gt 0 ]] && echo "scale=1; $sigsum/$n" | bc || echo "n/a" )
  c '1;32' "→ ${band}GHz  ps=$ps   XRUN: $d   ortalama sinyal: ${avg} dBm"
  echo "$band,$ps,$ARM,$d,$avg" >> "$OUT"
}

# ── run ──────────────────────────────────────────────────────────────────────
echo "band,power_save,seconds,xruns,avg_signal_dbm" > "$OUT"
c '1;35' "2x2 testi başlıyor — toplam ~$(( ARM*4/60 )) dakika"
c '0;37' "Müzik çalmaya devam etsin. Laptopu hareket ettirme. Arada normal gezin"
c '0;37' "(power save ancak Wi-Fi boştayken devreye girer)."

if pin_band 50; then run_arm 5.0 off; run_arm 5.0 on
else c '1;33' "5 GHz atlandı."; fi

if pin_band 24; then run_arm 2.4 on;  run_arm 2.4 off
else c '1;33' "2.4 GHz atlandı."; fi

# ── result table ─────────────────────────────────────────────────────────────
hdr "SONUÇ"
awk -F, 'NR>1{v[$1"-"$2]=$4}
END{
  printf "\n%-10s %12s %12s\n","","power_save off","power_save on"
  printf "%-10s %12s %12s\n","5.0 GHz", (("5.0-off" in v)?v["5.0-off"]:"-"), (("5.0-on" in v)?v["5.0-on"]:"-")
  printf "%-10s %12s %12s\n","2.4 GHz", (("2.4-off" in v)?v["2.4-off"]:"-"), (("2.4-on" in v)?v["2.4-on"]:"-")
  print ""
  print "Beklenen: yalnızca (2.4 GHz, on) hücresi anlamlı sayıda xrun göstermeli."
  print "Dördü de sıfırsa: ya sorun tekrarlanmadı ya da mekanizma farklı."
}' "$OUT"

c '0;36' "Ham veri: $OUT"
