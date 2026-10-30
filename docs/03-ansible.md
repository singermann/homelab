# Modul 3 – Automatisierung mit Ansible

**Zeitraum:** Woche 8–11 · **Status:** 🟡 in Arbeit

## Ziel

Alles, was in Modul 2 von Hand eingerichtet wurde – SSH-Härtung, Firewall, homelab-health –, per Ansible auf jede VM verteilen. Neue VM in unter 10 Minuten fertig konfiguriert, per Befehl statt per Hand.

## Woche 8 – Steuerknoten, Inventory, erste Befehle ✅

### Aufbau

| Komponente | Details |
|---|---|
| Steuerknoten | LXC-Container `ansible` (CT 200), Debian 13, unprivileged, 1 Kern, 1 GB RAM |
| Zugriff | Benutzer `sven` mit eigenem Schlüssel `ansible@homelab` (ed25519) |
| Ziele | `test-debian`, `test-rocky` – Benutzer `sven`, Key-Login, sudo |
| Konfiguration | [`ansible/ansible.cfg`](../ansible/ansible.cfg), [`ansible/inventory.ini`](../ansible/inventory.ini) |

Ansible braucht auf den Zielen nur SSH und Python – beides bringen die Cloud Images mit.

### Container anlegen (Proxmox)

```bash
pveam update
pveam available --section system | grep debian-13
pveam download local <vorlage>
pct create 200 local:vztmpl/<vorlage> \
  --hostname ansible --cores 1 --memory 1024 --swap 512 \
  --rootfs local-lvm:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/sven.pub --onboot 1 --start 1
```

`--unprivileged 1`: root im Container ist nicht root auf dem Host.

### Inventory

Hostnamen statt IP-Adressen: Die FritzBox löst `<name>.fritz.box` auf – so stehen keine internen IPs im öffentlichen Repo. Gruppen `debian` und `rocky`, zusammengefasst in `homelab`.

### Nachweis

```bash
ansible homelab -m ping                                   # beide: pong
ansible homelab -m setup -a 'filter=ansible_distribution*'   # Debian 13.7, Rocky 10.2
ansible rocky -b -m command -a 'getenforce'               # Enforcing
ansible homelab -b -m command -a 'systemctl is-active homelab-health.timer'  # active
```

### Gelernt

- Ad-hoc-Befehle (`ansible <gruppe> -m <modul>`) sprechen alle Server gleichzeitig an.
- `command` meldet immer `CHANGED`, weil Ansible nicht weiß, ob ein beliebiger Befehl etwas verändert. Module wie `apt`, `dnf`, `copy` oder `service` prüfen dagegen den Ist-Zustand und ändern nur, wenn nötig (Idempotenz) – darum geht es ab Woche 9.
- Ein eigener Schlüssel für Ansible trennt Automatisierung von persönlichem Zugang.


## Woche 9 – Erste Playbooks ✅

### Ergebnis

| Playbook | Aufgabe |
|---|---|
| [`playbooks/update.yml`](../ansible/playbooks/update.yml) | Updates auf allen VMs (apt bzw. dnf, per `when` nach Betriebssystem) |
| [`playbooks/base.yml`](../ansible/playbooks/base.yml) | Grundausstattung: Basispakete, Editor, Zeitzone, Login-Hinweis |

Variablen je Gruppe in [`ansible/group_vars/`](../ansible/group_vars/): `all.yml` für alle, `debian.yml` und `rocky.yml` für Unterschiede – z. B. heißt der Editor auf Debian `vim`, auf Rocky `vim-enhanced`.

### Arbeitsweise

```bash
ansible-playbook playbooks/base.yml --syntax-check   # Schreibweise prüfen
ansible-playbook playbooks/base.yml --check --diff   # Probelauf, zeigt Änderungen
ansible-playbook playbooks/base.yml                  # ausführen
```

Entwickelt wird direkt im Ansible-Container. Push nach GitHub über einen Deploy Key mit Schreibrecht, der nur für dieses Repo gilt.

### Nachweis Idempotenz

| Lauf | test-debian | test-rocky |
|---|---|---|
| 1. Lauf | changed=3 | changed=3 |
| 2. Lauf | changed=0 | changed=0 |
| nach Handänderung an `/etc/motd` (nur test-debian) | changed=1 | changed=0 |
| erneuter Lauf | changed=0 | changed=0 |

### Gelernt

- Ein Playbook beschreibt einen Zielzustand, keine Befehlsfolge. Ist der Zustand erreicht, tut Ansible nichts.
- Abweichungen von Hand werden erkannt und zurückgesetzt – der Stand im Repo gewinnt.
- `changed=0` beim ersten Lauf beweist keine Idempotenz. Der Nachweis braucht einen Lauf mit Änderung und einen ohne.
- `ansible.builtin.package` wählt apt oder dnf automatisch, Unterschiede zwischen Systemen gehören in `group_vars`.

## Woche 10 – Rollen ✅

### Ergebnis

Die Handarbeit aus Modul 2 ist jetzt in drei Rollen verpackt, zusammengeführt in [`playbooks/site.yml`](../ansible/playbooks/site.yml):

| Rolle | Aufgabe | Besonderheit |
|---|---|---|
| [`ssh_hardening`](../ansible/roles/ssh_hardening/) | SSH-Härtung verteilen | `validate: sshd -t` prüft vor dem Einspielen; Handler lädt `ssh` (Debian) bzw. `sshd` (Rocky) neu |
| [`firewall`](../ansible/roles/firewall/) | nftables (Debian), firewalld (Rocky) | `include_tasks` je Betriebssystem; erlaubte Dienste über `defaults`, überschreibbar per `group_vars` |
| [`homelab_health`](../ansible/roles/homelab_health/) | Benutzer, Skript, Service, Timer | `flush_handlers`, damit systemd die Units vor dem Timer-Start kennt |

```bash
ansible-playbook playbooks/site.yml   # Grundausstattung + alle Rollen
```

### Nachweis

| Rolle | 1. Lauf | 2. Lauf |
|---|---|---|
| ssh_hardening | changed=2 je VM (Datei + Handler) | changed=0, Handler läuft nicht |
| firewall | Debian changed=2, Rocky changed=0 | changed=0 |
| homelab_health | Debian changed=2, Rocky changed=0 | changed=0 |

Gegenproben: `sshd -T` zeigt `permitrootlogin no` / `gssapiauthentication no`, Firewall-Regeln aktiv, Timer `active`, SELinux-Label des Skripts auf Rocky `bin_t`.

Die erste Ausführung hat Abweichungen aus der Handarbeit sichtbar gemacht – z. B. stand `GSSAPIAuthentication no` durch `tee -a` am Dateiende statt an der vorgesehenen Stelle.

### Gelernt

- Handler reagieren nur auf echte Änderungen – das vergessene `reload` aus Woche 5 kann nicht mehr passieren.
- `validate` verhindert, dass eine fehlerhafte Konfiguration einen Dienst lahmlegt oder aussperrt.
- Eine Rolle kann mehrere Betriebssysteme bedienen; Unterschiede stecken in getrennten Task-Dateien.
- Ansible setzt beim Kopieren das passende SELinux-Label – das `mv`-Problem aus Woche 7 tritt nicht auf.

## Woche 11 – Ansible Vault und Gesamttest

_folgt_
