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

## Woche 9 – Erste Playbooks

_folgt_

## Woche 10 – Rollen

_folgt_

## Woche 11 – Ansible Vault und Gesamttest

_folgt_
