# Agrarix VPS - TODO & Openstaande Migraties

Overzicht van openstaande taken, geplande migraties en uitfaseringsacties voor de externe VPS-servers.

---

## ⏳ Openstaande Acties

### 1. Definitieve Productiemigratie e-bladmuziek (VPS1 ➔ VPS2)
De test- en acceptatieomgeving (`https://new.e-bladmuziek.nl/`) draait reeds 100% operationeel op VPS2 (`212.227.209.36:2223`, zie [README.md - Actie 8](README.md#migratie---actielogboek) en [agrarix/e-bladmuziek](https://github.com/agrarix/e-bladmuziek)). De definitieve overzetting van de productiedomeinen staat nog gepland:

- [x] **Apache2 VHosts inrichten op VPS2 (Voltooid)**:
  - `vijos.e-bladmuziek.nl` & `vijos-plus.e-bladmuziek.nl` actief op VPS2
  - `e-bladmuziek.nl` & `www.e-bladmuziek.nl` actief op VPS2 (301 redirect)
  - Symlinks en VHost configs getest (`apache2ctl configtest` -> `Syntax OK`)
- [x] **Data Delta Synchronisatie (Voltooid)**:
  - Delta-sync uitgevoerd vanaf VPS1 naar VPS2 via `scripts/vps2-migrate-ebladmuziek.sh`
  - Rechten gecontroleerd (`automation:automation`, `htpwd` op `0770` voor `automation:www-data`)
- [x] **Let's Encrypt SSL-certificaten (Voltooid)**:
  - Certificaten voor `vijos.e-bladmuziek.nl` en `www.e-bladmuziek.nl` overgezet naar VPS2 en actief
  - HTTPS gevalideerd via curl `--resolve` (HTTP 200 / 301)
- [x] **DNS Cutover (Voltooid)**:
  - DNS A-records bij domeinregistrar omgezet naar `212.227.209.36` (VPS2):
    - `vijos.e-bladmuziek.nl` ➔ `212.227.209.36`
    - `e-bladmuziek.nl` ➔ `212.227.209.36`
    - `www.e-bladmuziek.nl` ➔ `212.227.209.36`
    - `vijos-plus.e-bladmuziek.nl` ➔ `212.227.209.36`
  - DNS A-record `old.e-bladmuziek.nl` wijst naar `85.214.248.88` (VPS1)
- [x] **Behoud Originele Interface op vijos.e-bladmuziek.nl (Voltooid)**:
  - `vijos.e-bladmuziek.nl` losgekoppeld van `new.e-bladmuziek.nl` [eigen webroot met identieke VPS1 bestanden]
  - Originele CGI-scripts (`preset-pin_htaccess.sh` v0.6b en `set-own-pin_htaccess.sh` v0.7) hersteld in `/var/www/cgi-bin/`
  - Nieuwe v2 responsive interface geïsoleerd op `new.e-bladmuziek.nl` met `/var/www/cgi-bin-new/`
  - `old.e-bladmuziek.nl` geactiveerd op VPS1 (en voorbereid op VPS2) als direct archief van de oude omgeving
- [x] **Mail & OpenDKIM Configuratie e-bladmuziek.nl (Voltooid)**:
  - Postfix `sender_canonical_maps` en `smtp_generic_maps` geconfigureerd op VPS2 (`www-data` ➔ `webmaster@e-bladmuziek.nl`)
  - OpenDKIM op VPS2 ondertekent alle uitgaande mails lokaal met RSA-2048 sleutel (`key._domainkey.e-bladmuziek.nl`)
  - DNS MX `e-bladmuziek.nl` omgezet naar `mail.agrarix.it` (`nuntix` / `178.239.16.116`)
  - Virtuele aliassen en catch-all `@e-bladmuziek.nl` op `nuntix` geconfigureerd naar `e-bladmuziek@agrarix.nl`
- [ ] **VPS1 VHosts & Certificaten uitschakelen (Na validatie)**:
  - Apache vhosts op VPS1 disablen (`a2dissite`) voor gemigreerde sites
  - Oude certificaten op VPS1 opschonen (`certbot delete --cert-name ...`)

---

### 2. Migratiescripts & Ansible Playbook overzetten naar repo `vps` (Voltooid)
Migratiescripts en Ansible configuratie zijn overgezet naar de repository (`scripts/` en `ansible/`):

- [x] `scripts/vps2-migrate-carmen.sh` overzetten naar `agrarix/vps`
- [x] `scripts/vps2-migrate-bianca.sh` overzetten naar `agrarix/vps`
- [x] `scripts/vps2-migrate-wennink.sh` overzetten naar `agrarix/vps`
- [x] `scripts/vps2-deploy-condoleance.sh` overzetten naar `agrarix/vps`
- [x] `scripts/vps2-setup-new-bianca.sh`, `scripts/vps2-test-moderation.sh`, `scripts/test-condoleance.py`
- [x] `scripts/scan-vps2-vhosts.py` en `scripts/active-domain-check.sh`
- [x] `ansible/playbook_vps2.yml` en `ansible/inventory.ini` overzetten naar `agrarix/vps`

---

### 3. Definitieve Uitfasering VPS1 (`agrarix.it` - `85.214.248.88`)
Na afronding van de productiemigratie van e-bladmuziek:

- [ ] **Resterende 301 redirects**:
  - `begrijpbaar-met-beeld.nl` & `begrijpbaarmetbeeld.nl` verhuizen naar registrar DNS redirects of `presentix`
- [x] **Postfix Virtual Aliases (Voltooid)**:
  - DNS A-record `mail.agrarix.it` omgezet naar `178.239.16.116` (thuis IP / `nuntix`)
  - Alle mail-aliassen (`vijos-*@agrarix.it`, `netapp.link`, `e-bladmuziek.nl`, etc.) overgezet naar `/etc/postfix/virtual` op `nuntix` (`192.168.178.25`)
  - `virtual_alias_domains` en `virtual_alias_maps` op `nuntix` geactiveerd en getest (SMTP RCPT TO geeft `250 2.1.5 Ok`)
  - Ansible playbooks `playbook_mailgw.yml` en `playbook_mailgw_postfix.yml` bijgewerkt met `AGRARIX_IT` blok
- [ ] **Syslog WAN mTLS forwarding**:
  - Forwarding op `registrix` uitschakelen zodra VPS1 uit productie gaat
- [ ] **Opzegging**:
  - Strato servercontract definitief beëindigen
