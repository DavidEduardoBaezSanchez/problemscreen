#!/usr/bin/env bash
#
# pantalla-displayport.sh - Gestion del congelamiento de la pantalla
# DisplayPort (Mint 22.3 / RX 6700 XT). Script unico: menu interactivo,
# modo directo y modo autostart (login) en un solo archivo.
#
# Causa raiz: DisplayPort-1 a 60Hz y DisplayPort-2 a 74.97Hz. Los refresh
# rates desiguales hacian fallar los page-flips de amdgpu y congelaban la
# pantalla bajo carga. Igualar ambos a 60Hz lo resuelve.
#
# Uso:
#   ./pantalla-displayport.sh            # menu interactivo
#   ./pantalla-displayport.sh 1|2|3|4|5  # ejecuta una opcion directo
#   ./pantalla-displayport.sh --autostart  # modo login: espera y aplica 60Hz (lo usa el .desktop)
#
set -uo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
AUTOSTART_DESKTOP="${HOME}/.config/autostart/pantalla-displayport.desktop"
LOG="${HOME}/.local/share/pantalla-displayport.log"
OUTPUT="DisplayPort-2"
MODE="1920x1080"
RATE="60.00"

# --- Colores ---
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
log()   { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# --- Nucleo: aplicar 60Hz a DP-2 ---
# $1 = "quiet" para modo autostart (solo log, sin salida coloreada).
_set_60hz() {
  local quiet="${1:-}"
  if ! xrandr --query 2>/dev/null | grep -q "^${OUTPUT} connected"; then
    [[ "$quiet" == quiet ]] && { log "SKIP: ${OUTPUT} no conectado."; return 0; }
    warn "${OUTPUT} no esta conectado. No se aplica nada."
    return 1
  fi
  if xrandr --output "$OUTPUT" --mode "$MODE" --rate "$RATE" 2>/dev/null; then
    [[ "$quiet" == quiet ]] && log "OK: ${OUTPUT} -> ${MODE}@${RATE}Hz" \
                            || ok "Listo. ${OUTPUT} ahora a ${RATE}Hz (igualado a DisplayPort-1)."
    return 0
  else
    [[ "$quiet" == quiet ]] && log "ERROR: no se pudo aplicar ${MODE}@${RATE}Hz" \
                            || error "No se pudo aplicar el modo. Revisa que ${OUTPUT} soporte ${MODE}@${RATE}."
    return 1
  fi
}

# --- Modo autostart: lo invoca el .desktop al iniciar sesion ---
run_autostart() {
  sleep 4   # esperar a que el display este inicializado
  _set_60hz quiet
}

# --- Opcion 1: Aplicar 60Hz en caliente ---
aplicar_60hz() {
  info "Aplicando ${MODE}@${RATE}Hz a ${OUTPUT}..."
  _set_60hz
}

# --- Opcion 2: Descongelar la pantalla sin reiniciar ---
# `cinnamon --replace` reinicia el compositor: mata al Cinnamon actual (el que
# sostiene esta terminal). Por eso hay que desprenderlo del todo (nohup +
# setsid + redireccion) y SALIR del script enseguida, o el menu queda colgado
# esperando un read sobre una terminal que se esta muriendo.
descongelar() {
  info "Reiniciando Cinnamon (no cierra tus ventanas)..."
  info "El escritorio va a parpadear; es normal. Volves en unos segundos."
  setsid nohup cinnamon --replace -d :0 >/dev/null 2>&1 &
  disown
  ok "Cinnamon relanzado. Cerrando el script (el menu no puede sobrevivir al reinicio del escritorio)."
  # Salida inmediata: no tiene sentido volver al menu tras reiniciar Cinnamon.
  exit 0
}

# --- Opcion 3: Ver las frecuencias actuales de los monitores ---
ver_frecuencias() {
  info "Frecuencias activas (el * marca la que esta en uso):"
  echo
  xrandr --query | grep -E "^DisplayPort-[0-9] connected|\*"
}

# --- Opcion 4: Revertir el fix (quitar el autostart de 60Hz) ---
revertir_fix() {
  if [[ -f "$AUTOSTART_DESKTOP" ]]; then
    rm -f "$AUTOSTART_DESKTOP"
    ok "Autostart eliminado: ${AUTOSTART_DESKTOP}"
    info "En el proximo login DisplayPort-2 volvera a su refresh por defecto (74.97Hz)."
    warn "Ojo: si quitas esto, el congelamiento puede volver."
  else
    warn "No existe el autostart (${AUTOSTART_DESKTOP}). Nada que revertir."
  fi
}

# --- Opcion 5: Instalar/reparar el autostart (apunta a este mismo script) ---
instalar_autostart() {
  mkdir -p "$(dirname "$AUTOSTART_DESKTOP")"
  cat >"$AUTOSTART_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Fix Refresh 60Hz (DisplayPort-2)
Comment=Iguala DisplayPort-2 a 60Hz al iniciar sesion para evitar congelamientos de amdgpu
Exec=${SCRIPT_PATH} --autostart
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF
  ok "Autostart instalado: ${AUTOSTART_DESKTOP}"
  info "Apunta a: ${SCRIPT_PATH} --autostart"
  info "Se aplicara automaticamente en cada login."
}

# --- Menu ---
mostrar_menu() {
  echo
  echo "==============================================="
  echo "  Gestion pantalla DisplayPort - RX 6700 XT"
  echo "==============================================="
  echo "  1) Aplicar 60Hz ahora (fix en caliente)"
  echo "  2) Descongelar la pantalla (cinnamon --replace)"
  echo "  3) Ver frecuencias de los monitores"
  echo "  4) Revertir el fix de 60Hz (quitar autostart)"
  echo "  5) Instalar/reparar autostart (aplica 60Hz al login)"
  echo "  0) Salir"
  echo "-----------------------------------------------"
}

ejecutar() {
  case "$1" in
    1) aplicar_60hz ;;
    2) descongelar ;;
    3) ver_frecuencias ;;
    4) revertir_fix ;;
    5) instalar_autostart ;;
    0) info "Chau."; exit 0 ;;
    *) error "Opcion invalida: $1" ; return 1 ;;
  esac
}

# --- Modo autostart (login): ./pantalla-displayport.sh --autostart ---
if [[ "${1:-}" == "--autostart" ]]; then
  run_autostart
  exit $?
fi

# --- Modo directo: ./pantalla-displayport.sh 2 ---
if [[ $# -ge 1 ]]; then
  ejecutar "$1"
  exit $?
fi

# --- Modo interactivo ---
while true; do
  mostrar_menu
  read -rp "Elegi una opcion: " opcion
  ejecutar "$opcion" || true
  echo
  read -rp "Enter para volver al menu (o Ctrl+C para salir)..." _
done
