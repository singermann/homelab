# Modul 2 – Linux-Fundament

**Zeitraum:** Woche 4–7 · **Status:** 🟡 in Arbeit

## Ziel

- VM-Templates mit cloud-init für Debian und Rocky Linux (RHEL-kompatibel)
- SSH härten, Firewall einrichten (nftables bzw. firewalld)
- Eigenen systemd-Dienst schreiben, Logs mit journalctl auswerten
- SELinux-Grundlagen auf Rocky Linux

## Woche 4 – VM-Templates mit cloud-init ✅

### Ergebnis

Zwei Templates, gebaut per Skript [`scripts/create-template.sh`](../scripts/create-template.sh):

| Template | VMID | Image |
|---|---|---|
| `debian13-template` | 9000 | Debian 13 Generic Cloud |
| `rocky10-template` | 9001 | Rocky Linux 10 GenericCloud Base |

Jeder Klon startet mit Benutzer, SSH-Key, DHCP und qemu-guest-agent – ohne Installation, in ca. 2 Minuten.

```bash
bash scripts/create-template.sh debian     # oder: rocky
qm clone 9000 101 --name test-debian --full
qm resize 101 scsi0 +18G
qm start 101
```

### So funktioniert es

1. Offizielles Cloud Image laden und als qcow2 prüfen
2. `virt-customize` baut den qemu-guest-agent direkt ins Image ein
3. VM anlegen, Image als Festplatte importieren, cloud-init-Laufwerk anhängen
4. cloud-init-Werte setzen: Benutzer, öffentlicher SSH-Key, `ip=dhcp`
5. Konfiguration prüfen, dann `qm template`

Beim ersten Start eines Klons liest cloud-init diese Werte und richtet das System ein.

### Probleme und Lösungen

| Problem | Ursache | Lösung |
|---|---|---|
| `scp` fand den SSH-Key nicht | Key heißt `homelab.pub`, nicht `id_ed25519.pub` | Vorhandene Keys mit `dir $HOME\.ssh` geprüft, richtigen Key verwendet |
| `scp` zum Proxmox: *Permission denied (publickey)* | Server bietet nur Key-Login an, Key dort nicht hinterlegt | Key per Copy & Paste über die Proxmox-Shell nach `/root/sven.pub` übertragen |
| `wget` blieb bei *Connecting…* hängen | Verbindung zum Download-Server kam nicht zustande | Abgebrochen, mit `--timeout=20 --tries=3` erneut geladen |
| Klon bekam keine IP, kein Login möglich | `qm set --sshkeys` brach ab, weil die Key-Datei fehlte – dadurch fehlten auch `ciuser` und `ipconfig0`. Fehler fiel erst zwei Schritte später auf | Mit `qm config` nachgewiesen, Template neu gebaut. Seitdem Skript mit `set -euo pipefail` und Prüfung der Konfiguration vor `qm template` |
| `arp-scan -l`: *no IPv4 address on nic0* | Proxmox-IP liegt auf der Bridge `vmbr0`, nicht auf der Netzwerkkarte | `arp-scan -I vmbr0 -l` |
| Proxmox zeigte keine VM-IP an | qemu-guest-agent fehlte im Cloud Image | Agent per `virt-customize` ins Template eingebaut |
| `git mv` schlug fehl: *destination exists* | Neue Datei lag schon im Zielpfad | Alte Datei mit `git rm` entfernt, neue mit `git add` hinzugefügt – Git erkennt die Umbenennung selbst |

### Vorbeugend berücksichtigt

- **Rocky/RHEL 10 benötigt x86-64-v3** – mit dem Proxmox-Standard-CPU-Typ bootet es nicht. Lösung: `--cpu host`.
- **SELinux:** Nach Änderungen am Rocky-Image per `virt-customize` werden Dateien mit `--selinux-relabel` neu gekennzeichnet.
- **Zeilenenden:** `.gitattributes` mit `*.sh text eol=lf`, damit unter Windows bearbeitete Skripte auf Linux laufen.
- **`/etc/machine-id` geleert**, damit jeder Klon eine eigene ID und damit eine eigene DHCP-Adresse bekommt.

### Gelernt

- Ein still fehlgeschlagener Befehl ist gefährlicher als ein lauter Fehler – Skripte müssen bei Fehlern sofort abbrechen.
- Erst prüfen (`qm config`, `qemu-img info`, `cat`), dann weitermachen.
- Ein Template ist ein Bauplan, keine VM – gestartet werden nur Klone.

## Woche 5 – SSH härten und Firewall

_folgt_

## Woche 6 – systemd und journalctl

_folgt_

## Woche 7 – SELinux-Grundlagen

_folgt_

## Befehlsübersicht

| Befehl | Zweck |
|---|---|
| `qm config <ID>` | Konfiguration einer VM anzeigen |
| `qm clone <SRC> <ID> --name <N> --full` | VM aus Template klonen |
| `qm resize <ID> scsi0 +18G` | Festplatte vergrößern |
| `qm terminal <ID>` | Serielle Konsole öffnen (verlassen mit Strg + O) |
| `qemu-img info <Datei>` | Image prüfen |
| `pvesm status` | Speicher in Proxmox anzeigen |
| `arp-scan -I vmbr0 -l` | Geräte im Netz finden |
| `getenforce` | SELinux-Modus anzeigen (Rocky) |
