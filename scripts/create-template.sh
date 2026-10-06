#!/usr/bin/env bash
#
# create-template.sh
# Baut auf einem Proxmox-Host ein Cloud-Template (Debian oder Rocky Linux).
# Klone davon starten mit Benutzer, SSH-Key, DHCP und qemu-guest-agent.
#
# Aufruf (als root auf dem Proxmox-Host):
#   bash create-template.sh debian      # Debian 13, VMID 9000
#   bash create-template.sh rocky       # Rocky Linux 10, VMID 9001
# Werte anpassen per Umgebungsvariable, z. B.:
#   VMID=9010 STORAGE=local-zfs bash create-template.sh rocky

set -euo pipefail   # bei jedem Fehler sofort abbrechen

# --- Betriebssystem wählen --------------------------------------------------
OS="${1:-}"
case "$OS" in
  debian)
    DEFAULT_VMID=9000
    DEFAULT_NAME="debian13-template"
    IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    SELINUX=0
    ;;
  rocky)
    DEFAULT_VMID=9001
    DEFAULT_NAME="rocky10-template"
    IMAGE_URL="https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
    SELINUX=1   # Rocky nutzt SELinux -> nach Änderungen Dateien neu labeln
    ;;
  *)
    echo "Aufruf: bash $0 debian|rocky"
    exit 1
    ;;
esac

# --- Einstellungen ----------------------------------------------------------
VMID="${VMID:-$DEFAULT_VMID}"
NAME="${NAME:-$DEFAULT_NAME}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
CIUSER="${CIUSER:-sven}"
SSHKEY="${SSHKEY:-/root/sven.pub}"
IMAGE="/root/$(basename "$IMAGE_URL")"

# --- Vorprüfungen -----------------------------------------------------------
[[ $EUID -eq 0 ]]   || { echo "FEHLER: Bitte als root ausführen."; exit 1; }
[[ -s "$SSHKEY" ]]  || { echo "FEHLER: SSH-Key $SSHKEY fehlt oder ist leer."; exit 1; }
grep -q '^ssh-' "$SSHKEY" || { echo "FEHLER: $SSHKEY ist kein öffentlicher SSH-Key."; exit 1; }
if qm status "$VMID" &>/dev/null; then
  echo "FEHLER: VMID $VMID existiert bereits. Erst löschen: qm destroy $VMID"
  exit 1
fi
pvesm status | awk 'NR>1 {print $1}' | grep -qx "$STORAGE" \
  || { echo "FEHLER: Speicher $STORAGE nicht gefunden (pvesm status)."; exit 1; }

# --- Image laden und prüfen -------------------------------------------------
echo "==> Lade Cloud Image: $IMAGE_URL"
wget --timeout=20 --tries=3 -O "$IMAGE" "$IMAGE_URL"
qemu-img info "$IMAGE" | grep -q 'file format: qcow2' \
  || { echo "FEHLER: Image ist kein gültiges qcow2."; exit 1; }

# --- qemu-guest-agent direkt ins Image einbauen -----------------------------
echo "==> Installiere qemu-guest-agent ins Image"
command -v virt-customize >/dev/null || apt-get install -y libguestfs-tools
CUSTOMIZE_ARGS=(--install qemu-guest-agent --truncate /etc/machine-id)
[[ $SELINUX -eq 1 ]] && CUSTOMIZE_ARGS+=(--selinux-relabel)
virt-customize -a "$IMAGE" "${CUSTOMIZE_ARGS[@]}"

# --- VM anlegen -------------------------------------------------------------
# --cpu host: Rocky/RHEL 10 braucht x86-64-v3 und bootet mit dem
# Proxmox-Standard-CPU-Typ nicht. Für einen einzelnen Host unproblematisch.
echo "==> Lege VM $VMID an"
qm create "$VMID" --name "$NAME" --memory 2048 --cores 2 --cpu host \
  --net0 "virtio,bridge=$BRIDGE" --ostype l26 --agent enabled=1 \
  --scsihw virtio-scsi-single --serial0 socket --vga serial0

qm set "$VMID" --scsi0 "$STORAGE:0,import-from=$IMAGE,discard=on,ssd=1"
qm set "$VMID" --ide2 "$STORAGE:cloudinit"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --ciuser "$CIUSER" --sshkeys "$SSHKEY" --ipconfig0 ip=dhcp

# --- Kontrolle und Template -------------------------------------------------
echo "==> Prüfe Konfiguration"
for key in scsi0 ide2 boot ciuser sshkeys ipconfig0; do
  qm config "$VMID" | grep -q "^$key:" \
    || { echo "FEHLER: '$key' fehlt in der Konfiguration."; exit 1; }
done

qm template "$VMID"
echo "==> Fertig: Template $VMID ($NAME)"
echo "    Klonen:  qm clone $VMID <NEUE-ID> --name <NAME> --full"
echo "    Platte:  qm resize <NEUE-ID> scsi0 +18G"
