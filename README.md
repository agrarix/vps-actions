# Agrarix VPS Infrastructure & Management

## Intro

Centraal documentatie- en beheerhandboek voor de externe Virtual Private Servers (VPS) binnen de **Agrarix** netwerkarchitectuur.

De externe VPS-omgeving bestaat uit twee systemen:
1. **VPS1 (`agrarix.it` - `85.214.248.88:2223`)**: Oorspronkelijke Strato bare-metal / Ubuntu VPS server. Momenteel in een fase van gefaseerde ontmanteling waarbij actieve domeinen, cronjobs en services migreren naar het lokale Proxmox VE cluster (`presentix` / NAS / `fabrix`) of naar VPS2.
2. **VPS2 (`vps2.agrarix.net` - `212.227.209.36:2223`)**: Moderne Debian 13 (Trixie) VPS, ingericht via Ansible direct vanaf automation node `fabrix`. Fungeert als schone externe web- en mailnode voor publieke websites zoals `new.e-bladmuziek.nl`, `carmenkalbermatten.ch`, `biancawennink.nl`, `new.biancawennink.nl` en `wennink.eu`.

### VPS Vergelijking & Status Matrix

| Eigenschap | VPS1 (`agrarix.it`) | VPS2 (`vps2.agrarix.net`) | Toelichting |
| :--- | :--- | :--- | :--- |
| **Status** | *Gefaseerde ontmanteling* | **Productie (Actief)** | VPS1 wordt uitgefaseerd; VPS2 is modern en schoon ingericht. |
| **IP-adres (IPv4)** | `85.214.248.88` | `212.227.209.36` | Externe statische WAN IP-adressen. |
| **SSH-poort** | `2223` | `2223` | Poort 22 is op beide hosts gesloten; 2223 actief tegen botscans. |
| **Besturingssysteem** | Ubuntu 16.04 LTS (Strato) | Debian 13 Trixie | Moderne glibc en Linux kernel op VPS2. |
| **Webserver Engine** | Apache 2.4.18 | Apache 2.4.71 | Met HTTP/2, mod_ssl, mod_rewrite en Certbot ACME support. |
| **MTA (Postfix)** | `inet_interfaces = all` (poort 25) | `inet_interfaces = loopback-only` | VPS2 verstuurt alleen lokaal (geen spam-relay risico). |
| **OpenDKIM / Milter** | `inet:127.0.0.1:8891` | *Nog niet actief* | VPS1 ondertekent uitgaande mail; VPS2 volgt zodra nodig. |
| **Beheer & Ansible** | Handmatig / deels Ansible | **100% Declaratief via Ansible** | Beheerd vanaf `fabrix` via `playbook_vps2.yml`. |
| **Syslog / Analytics** | Rsyslog WAN mTLS ➔ `registrix:6514` | Rsyslog direct / Presentix integratie | Centrale logbewaking in Grafana Loki. |
| **Brute-Force Protectie** | Fail2ban jail op 2223 | Passwordless SSH / Geen poort 22 | Veilige whitelists voor beheer. |

---

## VPS1 (agrarix.it)

### Serverprofiel & Netwerk
- **Hostnaam**: `agrarix.it` / `h2828555.stratoserver.net`
- **Publiek IP**: `85.214.248.88`
- **SSH-poort**: `2223` (poort 22 geblokkeerd/uitgeschakeld)
- **Verbinding via fabrix**:
  ```bash
  ssh -p 2223 root@85.214.248.88
  ```
- **Brute-Force Protectie (Fail2ban)**:
  - Actief op SSH-poort `2223` (`/etc/fail2ban/jail.local`).
  - Blokkeert bots na 3 mislukte pogingen binnen 10 minuten voor 24 uur (`bantime = 86400`).
  - Whitelist (`ignoreip`) voor thuis-IP (`178.239.16.116`), localhost en server-IP.

### Actieve Rollen & Resterende Services
1. **Mail Relay & MX Node (Postfix + OpenDKIM)**:
   - Publieke MX server op poort 25 voor `mail.agrarix.it` (`85.214.248.88`).
   - `/etc/mailname`: Ingesteld op `agrarix.it`.
   - `/etc/aliases`: Lokale cron- en root-mails routeren naar `it-mbx@deboer-wennink.nl`.
   - `/etc/postfix/virtual`: Actieve virtuele mail-forwarding:
     - ViJoS mailings (`vijos-bestuur@agrarix.it`, `vijos-webwinkel@`, `vijos-webmaster@`, etc.).
     - Aliasing voor `e-bladmuziek.nl`, `begrijpbaar-met-beeld.nl`, `martijndeboer.nl`, `leoniewennink.nl`, `ernadevries.nl`.
   - OpenDKIM milter op `127.0.0.1:8891` (cryptografische signing voor `agrarix.it`, `pa4mdb.nl`, `agrarix.nl`).
2. **Syslog Forwarding over WAN (mTLS RFC 5425)**:
   - Rsyslog forwardt realtime systeemlogs (`*.*`) over WAN naar `registrix` (`mail.agrarix.net:6514`).
   - Encryptie en authenticatie via x509 certificaten in `/etc/rsyslog-tls/`.
   - Lokale disk queue `q_registrix` buffert logs bij internetonderbrekingen.
3. **Resterende Actieve Websites op VPS1 (Apache 2.4.18)**:
   - `e-bladmuziek.nl` cluster (`e-bladmuziek.nl`, `www.e-bladmuziek.nl`, `vijos.e-bladmuziek.nl`, `dev.e-bladmuziek.nl`, `demo.e-bladmuziek.nl`, `q-a.e-bladmuziek.nl`, `sites.e-bladmuziek.nl`).
   - `begrijpbaar-met-beeld.nl` & `begrijpbaarmetbeeld.nl` (301 redirects naar externe URL).
4. **Database Status**:
   - `mysql.service` is uitgeschakeld en gestopt. Poort 3306 is gesloten.
   - De verouderde test-database `wordpress_db` (PI4RCG) is gearchiveerd en verwijderd (zie Incident 8).

### Domeinverificatie Tool (`active-domain-check.sh`)
Geïnstalleerd op `agrarix.it` onder `/usr/local/bin/active-domain-check` (en `/home/maarten/scripts/active-domain-check.sh`):
- Controleert in realtime alle Apache vhosts, DNS A-records, HTTP/HTTPS statuscodes en SSL-certificaten.
- Filter-opties:
  - `active-domain-check`: Volledig overzicht van alle vhosts.
  - `active-domain-check -l`: Alleen domeinen die daadwerkelijk live naar `agrarix.it` (`85.214.248.88`) routeren.
  - `active-domain-check -m`: Alleen domeinen gemigreerd naar Proxmox Home (`178.239.16.x`).
  - `active-domain-check -a`: Inclusief historische weesmappen in `/var/www/vhosts/`.
  - `active-domain-check <domein1> <domein2>`: Specifieke domeinen inspecteren.

---

## VPS2 (vps2.agrarix.net)

### Serverprofiel & Toegang
- **Hostnaam**: `vps2.agrarix.net`
- **Publiek IP**: `212.227.209.36`
- **SSH-poort**: `2223`
- **Ansible Automation Controller**: Volledig beheerd vanaf Proxmox automation node `fabrix` (`192.168.178.40`) via `ansible/playbook_vps2.yml` en `ansible/inventory.ini`.
- **SSH Verbindingsconfiguratie (`~/.ssh/config` op `fabrix`)**:
  ```ssh-config
  Host vps2 vps2.agrarix.net 212.227.209.36
      Hostname 212.227.209.36
      Port 2223
      User automation
  ```
- **Gebruikers & Rechten**:
  - `automation` (UID/GID 1001, groep `sudo`): Volledige passwordless sudo (`/etc/sudoers.d/automation`), ED25519 SSH-sleutels van `fabrix`, `antigravity@agrarix.net` en `maarten@techlab-automation`.
  - `maarten` (UID 1002, groep `sudo`): Passwordless sudo, bootstrap beheerder.
  - `pjheise` (UID 1012, groep `wennink` GID 1013, secundair `www-data`): Webbeheerder voor `www.wennink.eu`, home directory `/var/www/vhosts/www.wennink.eu/html`, login via SFTP/SSH op poort 2223.
  - `root`: SSH-sleutels geïnjecteerd.

### Webserver (Apache2) & Gehoste Domeinen

#### A. `new.e-bladmuziek.nl`
- **DNS**: A-record ➔ `212.227.209.36`
- **Doel**: Test- en acceptatieomgeving voor migratie van `vijos.e-bladmuziek.nl` vanaf VPS1 (`85.214.248.88:2223`).
- **Webroot**: `/var/www/vhosts/new.e-bladmuziek.nl/html` (3.7 GB bladmuziek, eigenaar `automation:automation`).
- **SSL**: Let's Encrypt Certbot via Apache installer.
- **Documentatie**: Repository [`e-bladmuziek`](https://github.com/agrarix/e-bladmuziek) onder hoofdstuk *VPS2 Hosting & Migratie*.

#### B. `carmenkalbermatten.ch` (+ `www.carmenkalbermatten.ch`)
- **DNS**: Mijndomein A-record ➔ `212.227.209.36`
- **Webroot**: `/var/www/vhosts/carmenkalbermatten.ch/html` (In Gedenken Carmen Kalbermatten).
- **SSL**: Let's Encrypt Certbot automatisch verlengd.
- **Dagelijkse fotowisseling**: `/home/automation/bin/upd_carmenkalbermatten.sh` om `01:11` in crontab op VPS2, generator tag `<$HOSTNAME>:<$PGM> v<$VER>` (`vps2:upd_carmenkalbermatten v0.6`).
- **Migratiescript**: `scripts/vps2-migrate-carmen.sh`.

#### C. `biancawennink.nl` (+ `www.biancawennink.nl`)
- **DNS**: Mijndomein A-record ➔ `212.227.209.36`
- **Webroot**: `/var/www/vhosts/biancawennink.nl/html` (In herinnering Bianca Wennink, 168 MB).
- **SSL**: Let's Encrypt Certbot automatisch verlengd.
- **Dagelijkse fotowisseling**: `/home/automation/bin/upd_biancawennink.sh` om `01:01` in crontab op VPS2 met datumfilter `/home/automation/etc/upd_biancawennink.dates`, generator tag `<$HOSTNAME>:<$PGM> v<$VER>` (`vps2:upd_biancawennink v0.25`).
- **Migratiescript**: `scripts/vps2-migrate-bianca.sh`.

#### D. `new.biancawennink.nl` & Condoleanceregister
- **DNS**: Mijndomein A-record ➔ `212.227.209.36`
- **Doel**: Acceptatiekopie van `biancawennink.nl` met interactief PHP 8.4 condoleanceregister.
- **Webroot**: `/var/www/vhosts/new.biancawennink.nl/html`
- **Condoleanceregister Architectuur**:
  - URL: `https://new.biancawennink.nl/condoleanceregister/`
  - Runtime: PHP 8.4 (`libapache2-mod-php`, `php-mbstring`) op Apache 2.4.71.
  - Berichtenopslag: Platte tekstbestanden (`*.txt`), 1 bestand per condoleance in `/home/automation/biancawennink-nl/data/condoleances/` (chmod `2775`).
  - Pre-moderatie: Nieuwe berichten starten als `in_behandeling`. E-mailnotificatie naar beheerder met 1-klik goedkeur/afkeurlinks (`[Goedkeuren & Publiceren]` zet `STATUS: zichtbaar`, `[Afkeuren]` verplaatst via `rename()` naar `/home/automation/biancawennink-nl/data/afgekeurd/`).
  - Beveiliging: CSRF tokens, honeypot veld, cooldown timers.
  - E-mail alert: Directe Postfix `mail()` verzending naar `maarten@agrarix.nl`.
- **Deployment Script**: `scripts/vps2-deploy-condoleance.sh`.

#### E. `www.wennink.eu` (+ `wennink.eu`)
- **DNS**: Mijndomein A-record ➔ `212.227.209.36`
- **Webroot**: `/var/www/vhosts/www.wennink.eu/html` (208 MB inclusief `DEV260626` stamboomdatabase, eigenaar `pjheise:wennink`, chmod `2775`).
- **Symlink**: `/var/www/vhosts/wennink.eu` ➔ `/var/www/vhosts/www.wennink.eu`.
- **Beheerder**: User `pjheise` (inloggen via SFTP / SSH op poort `2223`).
- **SSL**: Let's Encrypt multi-domein certificaat (dekt zowel apex `wennink.eu` als `www.wennink.eu`).
- **Migratiescript**: `scripts/vps2-migrate-wennink.sh`.

### Mail Functionaliteit (Postfix op VPS2)
- **Rol**: Lokale Mail Transport Agent (MTA) voor veilige uitgaande mailverzending (notificaties, contactformulieren).
- **MTA Type**: `Internet Site` met directe bezorging over poort 25 (geen externe relayhost nodig).
- **Netwerk Binding**: `inet_interfaces = loopback-only` (luistert uitsluitend op `127.0.0.1`, geen extern spam-/open-relay risico).
- **Protocol**: `inet_protocols = ipv4` (voorkomt afkeuring door ontbrekende IPv6 PTR records op remote MX servers).
- **Mailname**: `/etc/mailname` = `vps2.agrarix.net`.
- **TLS Encryptie**: Opportunistic TLS (`smtp_tls_security_level = may`) met CA-validatie via `/etc/ssl/certs/ca-certificates.crt`.

---

## Incidenten & Migratielogboek

### Incident 1: Postfix Relay Access Denied (454 4.7.1) Loop
- **Datum**: 16 oktober 2026
- **Oorzaak**: `/etc/mailname` op `agrarix.it` stond historisch op `mail.agrarix.nl` waardoor lokale cron- en root-mails via extern DNS naar `nuntix` werden verzonden en daar als open-relay reject stuitten (`454 Relay access denied`).
- **Oplossing**: `/etc/mailname` gecorrigeerd naar `agrarix.it`, queue geleegd met `postsuper -d ALL`, OpenDKIM signing hersteld.

### Incident 2: Certbot Renewal Failures & Systemd Crashes
- **Datum**: 16 oktober 2026
- **Oorzaak**: Verlopen renewal-configs (`atostechlab.nl`, `wiki.atostechlab.nl`, `deboer-oostzaan.nl`, `www.agrarix.nl`, `bakkerij-vanbreemen.nl`, `completelynuts.nl`) en een lege 0-byte renewal file `zwerfvuil.agrarix.it.conf` veroorzaakten parse-crashes in `certbot.service`.
- **Oplossing**: Oude domeinen verwijderd met `certbot delete --cert-name <naam> --non-interactive`, 0-byte configs opgeruimd, service gereset (`systemctl reset-failed certbot.service`).

### Incident 3: maartendeboer.nl & www Redirects naar DokuWiki
- **Datum**: 18 oktober 2026
- **Oorzaak**: Apache vhosts op `agrarix.it` gebruikten `VirtualDocumentRoot /var/www/vhosts/%0/html` zonder map voor `maartendeboer.nl` (404) en ontbrekend SSL-certificaat.
- **Oplossing**: Let's Encrypt certificaat uitgebreid met `maartendeboer.nl`, vhosts opgesplitst naar schone 301 redirects richting `https://wiki.maartendeboer.nl/`, vastgelegd in Ansible playbook `playbook_agrarix_maartendeboer.yml`.

### Incident 4: Migratie 6 Subdomeinen van agrarix.it naar Proxmox NAS
- **Datum**: 23 oktober 2026
- **Aanleiding**: Consolidatie van statische websites naar de centrale Proxmox NAS (`/mnt/nas/WWW/domains/`) en `presentix` edge reverse proxy.
- **Gemigreerde domeinen**: `asw85.agrarix.it`, `deboer-oostzaan.agrarix.it`, `lcsn.agrarix.it`, `logo.agrarix.it`, `monavail.agrarix.it`, `techlab.agrarix.it` (301 redirects op `agrarix.it` naar `*.agrarix.net`).

### Incident 5: Migratie kakr.net & Consolidatie paulrobertblom naar .agrarix.net
- **Datum**: 27 oktober 2026
- **Gemigreerde domeinen**:
  - `kakr.net` + `www.kakr.net`: Webroot naar NAS `/mnt/nas/WWW/domains/kakr.net/pages/`, DNS A-record naar `178.239.16.116`, vhost op `presentix`.
  - `paulrobertblom.nl` ➔ `paulrobertblom.agrarix.net`: Nieuw Let's Encrypt ECDSA certificaat, permanente 301 redirect.

### Incident 6: Migratie netapp.link Cluster (netapp.link, anf, edu, tr)
- **Datum**: 27 oktober 2026
- **Aanleiding**: Overzetten van de zwaarst bezochte linkcollectie en PDF-archief (24.000+ hits/dag) naar Proxmox cluster (`presentix` + QNAP NFS).
- **Gemigreerde domeinen**: `netapp.link`, `www.netapp.link`, `anf.netapp.link`, `edu.netapp.link`, `tr.netapp.link`.
- **Configuratie**: Docroots naar NAS met symlink `html ➔ pages`, HTTP/2 Let's Encrypt SSL en asset caching (7d) op `presentix`.

### Incident 7: Migratie www.wennink.eu (+ wennink.eu) en User pjheise naar VPS2
- **Datum**: 16 november 2026
- **Aanleiding**: Verhuizing van `wennink.eu` en beheerder `pjheise` van `agrarix.it` naar `vps2.agrarix.net` (`212.227.209.36:2223`).
- **Configuratie**:
  1. Groep `wennink` (1013) en user `pjheise` (1012, homedir `/var/www/vhosts/www.wennink.eu/html`, shadow passwordhash overgezet) aangemaakt op VPS2.
  2. 208 MB aan webbestanden (inclusief `DEV260626` stamboomdatabase) overgezet en gechown'd naar `pjheise:wennink`.
  3. Let's Encrypt SSL-certificaten overgezet en uitgebreid via Certbot op VPS2 (`www.wennink.eu` + `wennink.eu`).
  4. Apache2 vhosts geactiveerd (`wennink.eu.conf` en `wennink.eu-le-ssl.conf`).
  5. DNS A-records bij Mijndomein omgezet naar `212.227.209.36`.
  6. Oude Apache vhosts en certificaten op `agrarix.it` verwijderd.
  7. SSH-daemon op VPS2 geconfigureerd op poort `2223` (identiek aan `agrarix.it`), zodat `pjheise` naadloos via SFTP/SSH kan inloggen.

### Incident 8: Opruiming wordpress_db & Deactivatie MySQL Daemon op VPS1
- **Datum**: 16 november 2026
- **Aanleiding**: Opruiming van inactieve databases op `agrarix.it`.
- **Bevinding**: `wordpress_db` was een inactieve testinstallatie uit juni 2022 voor `wp.agrarix.it` (PI4RCG) met 0 uploads en 3 dummy records. Geen enkele actieve service gebruikte MySQL.
- **Actie**: Veiligheidsdump gemaakt naar `/root/wordpress_db_backup_20261116.sql.gz`, database gedropt, `mysql.service` gestopt en uitgeschakeld. 140 MB fysiek RAM direct vrijgespeeld op VPS1.

---

## Domein Overzicht & Routing Status

### Actief op VPS2 (`vps2.agrarix.net` - `212.227.209.36`)
- `www.wennink.eu` & `wennink.eu` (inclusief user `pjheise`)
- `carmenkalbermatten.ch` & `www.carmenkalbermatten.ch`
- `biancawennink.nl` & `www.biancawennink.nl`
- `new.biancawennink.nl` (Condoleanceregister)
- `new.e-bladmuziek.nl`

### Resterend Actief op VPS1 (`agrarix.it` - `85.214.248.88`)
- `e-bladmuziek.nl` & `www.e-bladmuziek.nl`
- `vijos.e-bladmuziek.nl` & `vijos-plus.e-bladmuziek.nl`
- `dev.e-bladmuziek.nl`
- `demo.e-bladmuziek.nl`
- `q-a.e-bladmuziek.nl`
- `sites.e-bladmuziek.nl`
- `begrijpbaar-met-beeld.nl` & `www.begrijpbaar-met-beeld.nl` (301 redirect)
- `begrijpbaarmetbeeld.nl` & `www.begrijpbaarmetbeeld.nl` (301 redirect)
- Postfix Virtual Mail Aliases (`vijos-*@agrarix.it`, `martijndeboer.nl`, etc.)

### Gemigreerd naar Proxmox VE Home Cluster (`presentix` / NAS / `178.239.16.116`)
- `netapp.link`, `www.netapp.link`, `anf.netapp.link`, `edu.netapp.link`, `tr.netapp.link`
- `kakr.net`, `www.kakr.net`
- `paulrobertblom.agrarix.net` (`paulrobertblom.nl` 301 redirect)
- `klaasdeboer.agrarix.net` (`klaasdeboer.eu` 301 redirect)
- `asw85.agrarix.net`, `deboer-oostzaan.agrarix.net`, `lcsn.agrarix.net`, `logo.agrarix.net`, `monavail.agrarix.net`, `techlab.agrarix.net`
- `agrarix.net`, `www.agrarix.net`
- `maartendeboer.nl`, `www.maartendeboer.nl`, `wiki.maartendeboer.nl`
- `mariskawennink.nl`, `www.mariskawennink.nl`
- `plus.vijos.nl`
- `zwerfvuil.agrarix.it`
- `default.agrarix.it`

---

## Onderhoud & Certificaatbeheer

### Certificaten vernieuwen (Dry-run test)
- **Op VPS2**:
  ```bash
  ssh -p 2223 automation@vps2.agrarix.net "sudo certbot renew --dry-run"
  ```
- **Op VPS1**:
  ```bash
  ssh -p 2223 root@85.214.248.88 "certbot renew --dry-run"
  ```

### Oude certificaten opruimen na domeinmigratie
Verwijder nooit handmatig bestanden uit `/etc/letsencrypt/live/`, maar gebruik altijd het officiële Certbot commando:
```bash
certbot delete --cert-name <domeinnaam> --non-interactive
```
Controleer op achtergebleven 0-byte renewal bestanden:
```bash
find /etc/letsencrypt/renewal/ -type f -empty -delete
```
