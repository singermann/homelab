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

### Ergebnis

| | Debian (test-debian) | Rocky (test-rocky) |
|---|---|---|
| SSH | nur Key-Login, kein root, nur Benutzer `sven` | gleich |
| Firewall | nftables, eigene Regeln | firewalld, Zone `public` |
| Eingehend erlaubt | SSH, Ping, DHCP | SSH, DHCPv6-Client (Ping erlaubt firewalld standardmäßig) |

Dateien im Repo:
- [`ansible/files/ssh/10-hardening.conf`](../ansible/files/ssh/10-hardening.conf) – SSH-Härtung für beide Systeme
- [`ansible/files/nftables/nftables.conf`](../ansible/files/nftables/nftables.conf) – Firewall-Regeln Debian

In Modul 3 verteilt Ansible diese Dateien automatisch auf jede neue VM.

### SSH-Härtung

Eigene Datei in `/etc/ssh/sshd_config.d/` statt Änderung der Hauptdatei – Updates überschreiben sie nicht. Die Nummer `10-` ist wichtig: sshd übernimmt den **ersten** gefundenen Wert, Dateien werden alphabetisch gelesen.

```bash
sudo sshd -t                                   # Syntax prüfen
sudo sshd -T | grep -E "permitrootlogin|allowusers"   # effektive Werte
sudo systemctl reload ssh                      # Debian (Rocky: sshd)
```

### Firewall

**Debian – nftables:** Standardregel `policy drop`, freigegeben wird nur, was nötig ist.

```bash
sudo nft -c -f /etc/nftables.conf      # prüfen
sudo systemctl enable --now nftables   # aktivieren, auch nach Neustart
```

**Rocky – firewalld:** Zonen und Dienste statt eigener Regeln. Cockpit-Port geschlossen.

```bash
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --remove-service=cockpit
sudo firewall-cmd --reload
```

`--permanent` speichert, wirkt aber erst nach `--reload`. Ohne `--permanent` gilt eine Änderung nur bis zum Neustart.

### Nachweis

| Test | Debian | Rocky |
|---|---|---|
| Login als `sven` mit Key | ✅ | ✅ |
| Passwort-Login | ❌ `Permission denied (publickey)` | ❌ |
| Login als `root` | ❌ `Permission denied (publickey)` | ❌ |
| Port 8080 mit Firewall / ohne / wieder mit | False → True → False | False → True → False |
| Regeln nach Neustart vorhanden | ✅ | ✅ |

Testablauf Port 8080 (komplett aus PowerShell):

```powershell
ssh -i $HOME\.ssh\homelab sven@<VM> "sudo systemd-run --unit=testweb python3 -m http.server 8080"
Test-NetConnection <VM> -Port 8080 -InformationLevel Quiet          # False
ssh -i $HOME\.ssh\homelab sven@<VM> "sudo systemctl stop nftables"  # Rocky: firewalld
Test-NetConnection <VM> -Port 8080 -InformationLevel Quiet          # True
ssh -i $HOME\.ssh\homelab sven@<VM> "sudo systemctl start nftables; sudo systemctl stop testweb"
Test-NetConnection <VM> -Port 8080 -InformationLevel Quiet          # False
```

### Probleme und Lösungen

| Problem | Ursache | Lösung |
|---|---|---|
| root kam trotz `PermitRootLogin no` noch rein (Meldung von cloud-init statt *Permission denied*) | Datei angelegt, aber sshd nicht neu geladen. `sshd -T` zeigt nur, was beim nächsten Laden gilt | `systemctl reload ssh`; im Journal belegt: `Accepted publickey for root` vor, `Received SIGHUP` nach dem Reload |
| Passwort-Test war schon vor der Härtung „bestanden“ | Cloud Image hat Passwort-Login bereits deaktiviert | Test zählt nur zusammen mit `sshd -T` als Nachweis |
| Port-Test zeigte *False*, bewies aber nichts | Webserver lief zum Testzeitpunkt nicht – ein Port ohne Dienst ist immer zu | Webserver per `systemd-run` als Dienst gestartet, Gegenprobe mit abgeschalteter Firewall |
| Tests zuerst in der VM statt am PC ausgeführt | VM hat sich mit sich selbst verbunden | Eingabezeile prüfen: `PS C:\>` = PC, `sven@test-debian` = VM |
| Rocky bot zusätzlich `gssapi-keyex,gssapi-with-mic` an | Kerberos-Anmeldung bei RHEL standardmäßig aktiv | `GSSAPIAuthentication no` ergänzt |

### Gelernt

- Ein Test kann aus dem falschen Grund grün sein – immer die Gegenprobe machen (mit/ohne Firewall).
- Konfiguration schreiben ≠ Konfiguration aktiv. Erst `reload`, dann testen.
- Beim Ändern von SSH oder Firewall immer einen Rettungsweg offen halten (zweite Sitzung, Proxmox-Konsole).

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
