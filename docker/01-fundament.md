# Modul 1 – Fundament und Git

**Zeitraum:** Woche 1–3 · **Status:** ✅ abgeschlossen

## Ziel

- Proxmox VE als Host auf dem MiniPC betriebsbereit machen
- NAS per NFS als Speicher für ISOs, Templates und Backups einbinden
- GitHub-Repo anlegen, Git-Grundlagen üben: commit, branch, merge, Pull Request

## Umgebung

| Komponente | Details |
|---|---|
| Host | MiniPC, Proxmox VE `[Version aus pveversion]` |
| Speicher lokal | SSD im MiniPC – für VM-Festplatten |
| Speicher NAS | UGREEN NASync DXP4800 Pro, NFS-Freigabe `proxmox` |
| Arbeitsplatz | Windows-PC, Git, SSH (ed25519) |

## Umsetzung

### 1. Proxmox aktualisieren

- Enterprise-Repositories deaktiviert, No-Subscription-Repository hinzugefügt
  (Knoten → Updates → Repositories)
- System aktualisiert:

```bash
apt update && apt full-upgrade -y
pveversion
```

### 2. NFS-Freigabe auf dem NAS

- Feste IP-Adressen für NAS und Proxmox per DHCP-Reservierung im Router
- NFS-Dienst in UGOS aktiviert, Freigabe `proxmox` angelegt
- NFS-Regel: Zugriff nur für den Proxmox-Host, Lesen/Schreiben, kein Root-Squash

### 3. NFS in Proxmox einbinden

```bash
showmount -e <NAS-IP>      # Freigabe sichtbar?
```

Datacenter → Storage → Add → NFS:

| Feld | Wert |
|---|---|
| ID | `nas-nfs` |
| Content | Backup, ISO image, Container template |

```bash
pvesm status               # nas-nfs: active
```

Aufteilung: VM-Festplatten auf der lokalen SSD (Geschwindigkeit), ISOs und Backups auf dem NAS.

### 4. GitHub-Repo

- Repo `homelab` angelegt, Zugriff per SSH-Key
- Ordnerstruktur, `.gitignore` gegen Geheimnisse, README mit Netzplan (Mermaid)
- Änderungen über Branch und Pull Request eingereicht

## Probleme und Lösungen

| Problem | Ursache | Lösung |
|---|---|---|
| Option „VZDump backup file“ nicht vorhanden | heißt in neueren Proxmox-Versionen nur „Backup“ | „Backup“ gewählt |


## Gelernt

- Proxmox ohne Subscription richtig mit Updates versorgen
- NFS-Rechte: Proxmox schreibt als root – ohne passendes Squash-Setting scheitern Backups
- Ein Linux-Passwort lässt sich mit physischem Zugriff zurücksetzen – darum zählt auch die physische Sicherheit
- Git: lokaler und entfernter Stand sind getrennt; vor dem Pushen erst vergleichen, dann entscheiden

## Nächster Schritt

Modul 2 – Linux-Fundament: VM-Templates mit cloud-init (Debian 12, Rocky Linux 9).
