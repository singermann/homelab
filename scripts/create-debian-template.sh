#!/usr/bin/env bash
#
# create-debian-template.sh
# Baut auf einem Proxmox-Host ein Debian-13-Template mit cloud-init.
# Klone davon starten mit Benutzer, SSH-Key, DHCP und qemu-guest-agent.
#
# Aufruf (als root auf dem Proxmox-Host):
#   bash create-debian-template.sh
# Werte anpassen per Umgebungsvariable, z. B.:
#   VMID=9001 STORAGE=local-zfs bash create-debian-template.sh

set -euo pipefail   # bei jedem Fehler sofort abbrechen

# --- Einstellungen ----------------------------------------------------------
VMID="${VMID:-9000}"
NAME="${NAME:-debian13-template}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
CIUSER="${CIUSER:-sven}"
SSHKEY="${SSHKEY:-/root/sven.pub}"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
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
echo "==> Lade Cloud Image"
wget --timeout=20 --tries=3 -O "$IMAGE" "$IMAGE_URL"
qemu-img info "$IMAGE" | grep -q 'file format: qcow2' \
  || { echo "FEHLER: Image ist kein gültiges qcow2."; exit 1; }

# --- qemu-guest-agent direkt ins Image einbauen -----------------------------
echo "==> Installiere qemu-guest-agent ins Image"
command -v virt-customize >/dev/null || apt-get install -y libguestfs-tools
virt-customize -a "$IMAGE" \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

# --- VM anlegen -------------------------------------------------------------
echo "==> Lege VM $VMID an"
qm create "$VMID" --name "$NAME" --memory 2048 --cores 2 \
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
