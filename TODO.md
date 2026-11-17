# Agrarix VPS - TODO & Openstaande Migraties

Overzicht van openstaande taken, geplande migraties en uitfaseringsacties voor de externe VPS-servers.

---

## ⏳ Openstaande Acties

### 1. Definitieve Productiemigratie e-bladmuziek (VPS1 ➔ VPS2)
De test- en acceptatieomgeving (`https://new.e-bladmuziek.nl/`) draait reeds 100% operationeel op VPS2 (`212.227.209.36:2223`, zie [README.md - Actie 8](README.md#migratie---actielogboek) en [agrarix/e-bladmuziek](https://github.com/agrarix/e-bladmuziek)). De definitieve overzetting van de productiedomeinen staat nog gepland:

- [ ] **Apache2 VHosts inrichten op VPS2**:
  - `e-bladmuziek.nl` & `www.e-bladmuziek.nl`
  - `vijos.e-bladmuziek.nl` & `vijos-plus.e-bladmuziek.nl`
  - Subdomeinen (`dev.`, `demo.`, `q-a.`, `sites.`) evalueren / archiveren
- [ ] **Data Delta Synchronisatie**:
  - Laatste delta-rsync uitvoeren vanaf VPS1 voor eventuele recent gewijzigde partituren of CSV-ledenbestanden
  - Permissies controleren (`automation:automation`, `htpwd` voor `automation:www-data`)
- [ ] **Let's Encrypt SSL-certificaten**:
  - Certbot certificaat aanvragen / uitbreiden op VPS2 voor alle domeinnamen
- [ ] **DNS Cutover**:
  - DNS A-records bij domeinregistrar omzetten van `85.214.248.88` (VPS1) naar `212.227.209.36` (VPS2)
- [ ] **VPS1 VHosts & Certificaten uitschakelen**:
  - Apache vhosts op VPS1 disablen (`a2dissite`)
  - Oude certificaten op VPS1 opschonen (`certbot delete --cert-name ...`)

---

### 2. Migratiescripts & Ansible Playbook overzetten naar repo `vps`
Momenteel staan de migratiescripts fysiek nog in `Proxmox-env/scripts/` en `Proxmox-env/ansible/`:

- [ ] `scripts/vps2-migrate-carmen.sh` overzetten naar `agrarix/vps`
- [ ] `scripts/vps2-migrate-bianca.sh` overzetten naar `agrarix/vps`
- [ ] `scripts/vps2-migrate-wennink.sh` overzetten naar `agrarix/vps`
- [ ] `scripts/vps2-deploy-condoleance.sh` overzetten naar `agrarix/vps`
- [ ] `ansible/playbook_vps2.yml` overzetten naar `agrarix/vps`

---

### 3. Definitieve Uitfasering VPS1 (`agrarix.it` - `85.214.248.88`)
Na afronding van de productiemigratie van e-bladmuziek:

- [ ] **Resterende 301 redirects**:
  - `begrijpbaar-met-beeld.nl` & `begrijpbaarmetbeeld.nl` verhuizen naar registrar DNS redirects of `presentix`
- [ ] **Postfix Virtual Aliases**:
  - Mail-aliassen (`vijos-*@agrarix.it`, etc.) overzetten naar `nuntix` (`192.168.178.25`) of VPS2
- [ ] **Syslog WAN mTLS forwarding**:
  - Forwarding op `registrix` uitschakelen zodra VPS1 uit productie gaat
- [ ] **Opzegging**:
  - Strato servercontract definitief beëindigen
