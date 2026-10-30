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

## Woche 5 – SSH härten und Firewall ✅

### Ergebnis

| | Debian (test-debian) | Rocky (test-rocky) |
|---|---|---|
| SSH | nur Key-Login, kein root, nur Benutzer `sven` | gleich |
| Firewall | nftables, eigene Regeln | firewalld, Zone `public` |
| Eingehend erlaubt | SSH, Ping, DHCP | SSH, DHCPv6-Client (Ping erlaubt firewalld standardmäßig) |

Dateien im Repo:
- [`ansible/roles/ssh_hardening/files/10-hardening.conf`](../ansible/roles/ssh_hardening/files/10-hardening.conf) – SSH-Härtung für beide Systeme
- [`ansible/roles/firewall/files/nftables.conf`](../ansible/roles/firewall/files/nftables.conf) – Firewall-Regeln Debian

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

## Woche 6 – systemd und journalctl ✅

### Ergebnis

Eigener Dienst `homelab-health`: prüft alle 15 Minuten Plattenbelegung, Arbeitsspeicher und fehlgeschlagene Dienste und schreibt das Ergebnis mit Priorität ins Journal. Läuft auf Debian und Rocky.

| Teil | Datei im Repo | Ziel auf dem Server |
|---|---|---|
| Skript | [`ansible/roles/homelab_health/files/homelab-health.sh`](../ansible/roles/homelab_health/files/homelab-health.sh) | `/usr/local/bin/homelab-health` |
| Service | [`ansible/roles/homelab_health/files/homelab-health.service`](../ansible/roles/homelab_health/files/homelab-health.service) | `/etc/systemd/system/` |
| Timer | [`ansible/roles/homelab_health/files/homelab-health.timer`](../ansible/roles/homelab_health/files/homelab-health.timer) | `/etc/systemd/system/` |

### Aufbau

- **Service** (`Type=oneshot`): *wie* das Skript läuft – eigener Systembenutzer, nur Lesezugriff (`ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`).
- **Timer** (`OnCalendar=*:0/15`, `Persistent=true`): *wann* es läuft – moderner Ersatz für cron, verpasste Läufe werden nachgeholt.
- **Prioritäten:** Zeilen mit `<4>` werden im Journal zur Warnung, `<6>` zur Info. Dadurch filtert `journalctl -p warning` nur die Probleme heraus.

### Installation (Rocky, aus dem Repo)

```bash
git clone https://github.com/singermann/homelab.git && cd homelab
sudo useradd --system --no-create-home --shell /usr/sbin/nologin homelab-health
sudo install -m 755 ansible/roles/homelab_health/files/homelab-health.sh /usr/local/bin/homelab-health
sudo install -m 644 ansible/roles/homelab_health/files/homelab-health.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-health.timer
```

`install` statt `mv`: legt eine neue Datei an, die das richtige SELinux-Label des Zielordners erhält (`bin_t`, `systemd_unit_file_t`). Geprüft mit `ls -Z`, `ausearch -m avc` ohne Treffer.

### Nachweis

| Test | Debian | Rocky |
|---|---|---|
| Manueller Start, `status=0/SUCCESS` | ✅ | ✅ |
| Timer aktiv (`systemctl list-timers`) | ✅ | ✅ |
| Warnung provoziert (`THRESHOLD=1`), `journalctl -p warning` zeigt nur Warnzeilen | ✅ | – |
| Keine SELinux-Blockaden | – | ✅ |

### Probleme und Lösungen

| Problem | Ursache | Lösung |
|---|---|---|
| Dienst brach nach der RAM-Zeile ab, `status=1/FAILURE`, keine Fehlermeldung | `systemctl --failed` scheiterte unter `DynamicUser=yes`: *Transport endpoint is not connected*; `set -euo pipefail` brach still ab | Systematisch isoliert (siehe unten), fester Systembenutzer `homelab-health` statt `DynamicUser` |
| Hypothese „`libnss-systemd` fehlt“ | Paket installiert, Fehler blieb → **widerlegt** | Isolations-Test mit drei Varianten |
| Check meldete sich selbst als fehlgeschlagen | Alter Fehlerstatus von `homelab-health.service` | `systemctl reset-failed homelab-health.service` |
| Warnungstest zeigte zuerst nichts | `systemd-run` ohne `--wait` kehrt sofort zurück, `journalctl` prüfte zu früh | Erneut abgefragt bzw. `--wait` |
| Zeile für `/` fehlte auf Rocky | `journalctl -n 6` zeigt nur die letzten 6 Zeilen, Rocky hat eine Partition mehr | `-n 10` |
| `/boot` auf Rocky zu 69 % belegt | Kleine eigene Partition (936 MB), dnf behält bis zu 3 Kernel | `installonly_limit=2` in `/etc/dnf/dnf.conf` – **erster echter Fund des Checks** |

Isolations-Test (`systemctl --failed` unter verschiedenen Bedingungen):

| Variante | Exit-Code |
|---|---|
| A: `User=nobody`, ohne Härtung | 0 |
| B: `DynamicUser=yes` | 1 – *Transport endpoint is not connected* |
| C: `User=homelab-health` mit voller Härtung | 0 |

→ Nur der temporäre Benutzer wird von D-Bus abgewiesen, die Härtungsoptionen sind unproblematisch.

### Gelernt

- Fehler eingrenzen statt raten: Hypothese aufstellen, testen, bei Widerlegung systematisch isolieren.
- `set -e` bricht still ab – Prüfungen, die scheitern dürfen, gezielt abfangen und als Warnung melden.
- Nach jeder Änderung an Unit-Dateien `systemctl daemon-reload`.
- Ein Test muss *nach* dem Ereignis prüfen (Timing bei Hintergrundprozessen).

### journalctl-Spickzettel

| Befehl | Zeigt |
|---|---|
| `journalctl -u <dienst>` | Meldungen eines Dienstes |
| `journalctl -p warning` | nur Warnungen und Schlimmeres |
| `journalctl --since "1 hour ago"` | Zeitraum |
| `journalctl -b` | seit dem letzten Start |
| `journalctl -f` | live mitlesen |
| `journalctl -o cat` | nur der Text |
| `journalctl -u ssh --since today -o cat \| grep -E "Accepted\|not allowed"` | erfolgreiche und abgewiesene SSH-Logins |

## Woche 7 – SELinux-Grundlagen ✅

### Wie SELinux denkt

Dateirechte (`rwx`) fragen: *Wer* darf zugreifen? SELinux fragt zusätzlich: *Welcher Prozess* darf *welche Art von Datei oder Port* wie nutzen? Dafür trägt alles ein Label (Typ):

| Objekt | Beispiel-Typ |
|---|---|
| Prozess systemd | `init_t` |
| Prozess sshd | `sshd_t` |
| Programmdatei in `/usr/local/bin` | `bin_t` |
| Datei aus einem Home-Verzeichnis | `user_home_t` |
| SSH-Port | `ssh_port_t` |

Fehlt eine erlaubende Regel, wird blockiert – auch für root.

```bash
getenforce                  # Enforcing / Permissive / Disabled
ls -Z <datei>               # Label einer Datei
ps -eZ | grep sshd          # Label eines Prozesses
sudo ausearch -m avc -ts recent          # Blockaden der letzten Minuten
sudo ausearch -m avc -ts recent | audit2why   # Erklärung
```

### Übung 1 – Falsches Datei-Label durch `mv`

**Provoziert:** Skript ins Home-Verzeichnis kopiert und per `mv` zurück nach `/usr/local/bin` verschoben.

**Symptom:** `homelab-health.service` scheitert mit `status=203/EXEC` – obwohl die Dateirechte `rwxr-xr-x` korrekt sind.

**Ursache (Audit-Log):**

```
avc: denied { execute } … comm="(b-health)"
scontext=system_u:system_r:init_t:s0
tcontext=unconfined_u:object_r:user_home_t:s0 tclass=file permissive=0
uid=0
```

systemd (`init_t`) darf keine Datei mit Label `user_home_t` ausführen. `mv` behält Label **und Besitzer** (`sven`) der Quelle bei.

**Lösung:**

```bash
sudo restorecon -v /usr/local/bin/homelab-health   # user_home_t -> bin_t
sudo chown root:root /usr/local/bin/homelab-health
```

`chown` ist zusätzlich nötig: Sonst könnte `sven` ein Skript ändern, das systemd regelmäßig ausführt.

### Übung 2 – Dienst auf nicht vorgesehenem Port

**Provoziert:** sshd zusätzlich auf Port 2222 (`/etc/ssh/sshd_config.d/20-port.conf` mit `Port 22` und `Port 2222`).

**Symptom:** `sshd -t` meldet keinen Fehler (prüft kein SELinux), `ss -tlnp` zeigt aber nur Port 22. Journal: `Bind to port 2222 on 0.0.0.0 failed: Permission denied.`

**Ursache:**

```
avc: denied { name_bind } … src=2222
scontext=system_u:system_r:sshd_t:s0-s0:c0.c1023
tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket
```

**Lösung:** Port mit dem passenden Typ kennzeichnen, danach zusätzlich die Firewall öffnen – zwei unabhängige Schutzschichten.

```bash
sudo semanage port -a -t ssh_port_t -p tcp 2222   # SELinux
sudo systemctl reload sshd
sudo firewall-cmd --permanent --add-port=2222/tcp  # firewalld
sudo firewall-cmd --reload
```

Danach lauschte sshd auf 22 und 2222. Anschließend alles zurückgebaut (`semanage port -d`, `--remove-port`, Konfigurationsdatei gelöscht).

### Welche Lösung wann?

| Situation | Richtige Lösung |
|---|---|
| Datei hat falsches Label | `restorecon` |
| Datei liegt an ungewöhnlichem Ort | `semanage fcontext -a` + `restorecon` |
| Dienst nutzt ungewöhnlichen Port | `semanage port -a` |
| Vorgesehene Option abgeschaltet | `setsebool -P` |
| Nichts davon passt | erst dann `audit2allow` – nach genauer Prüfung |

`audit2why` schlug in Übung 1 `audit2allow` vor. Das wäre falsch gewesen: Eine neue Regel „systemd darf Home-Dateien ausführen“ hätte eine Sicherheitslücke geöffnet. Die Frage ist immer: **Ist die Regel falsch – oder das Label?**

`setenforce 0` dient nur als Gegenprobe, nie als Lösung.

### Gelernt

- 203/EXEC bei korrekten Dateirechten → an SELinux denken, `ausearch -m avc` prüfen.
- `install` oder `cp` statt `mv`, wenn Dateien in Systemverzeichnisse kommen.
- Eine erfolgreiche Syntaxprüfung (`sshd -t`) heißt nicht, dass der Dienst tut, was er soll – Ergebnis prüfen (`ss -tlnp`).
- SELinux und Firewall sind getrennte Schichten; beide müssen passen.

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
