#!/usr/bin/env python3
"""
scripts/scan-vps2-vhosts.py
Scans all active Apache virtual hosts on VPS2 (vps2.agrarix.net: 212.227.209.36)
and outputs JSON format for integration into the Presentix domains dashboard,
plus syncs active Apache access logs to /mnt/nas/WWW/domains/vps_logs/
"""
import subprocess
import json
import sys
import os

SSH_CMD = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "automation@vps2.agrarix.net"]

REMOTE_SCRIPT = """
import glob
import os
import json
import re

vhosts = {}
conf_files = sorted(glob.glob('/etc/apache2/sites-enabled/*.conf'))

for conf in conf_files:
    try:
        with open(conf, 'r', errors='ignore') as f:
            content = f.read()
    except Exception:
        continue

    blocks = re.findall(r'<VirtualHost\\b[^>]*>(.*?)</VirtualHost>', content, re.I | re.S)
    if not blocks:
        blocks = [content]

    for block in blocks:
        lines = block.splitlines()
        is_ssl = ('-le-ssl' in conf) or (':443' in block) or any('sslengine on' in l.lower() for l in lines)
        server_names = []
        server_aliases = []
        doc_roots = []
        redir_target = None
        log_file = None

        for l in lines:
            l = l.strip()
            if not l or l.startswith('#'):
                continue
            parts = l.split()
            if not parts:
                continue
            key = parts[0].lower()
            if key == 'servername' and len(parts) > 1:
                server_names.append(parts[1])
            elif key == 'serveralias' and len(parts) > 1:
                for a in parts[1:]:
                    server_aliases.append(a)
            elif key == 'documentroot' and len(parts) > 1:
                doc_roots.append(parts[1].strip('"\\''))
            elif key == 'customlog' and len(parts) > 1:
                raw_log = parts[1].strip('"\\'')
                log_base = os.path.basename(raw_log)
                if log_base and not log_base.startswith(('access.log', 'other_vhosts')):
                    log_file = log_base

            if not redir_target:
                m_rw = re.search(r'RewriteRule\\s+.*?\\s+(https?://[^\\s$]+)', l, re.I)
                if m_rw:
                    t = m_rw.group(1).rstrip('/')
                    if not any(k in t.lower() for k in ['%{server_name}', '%{http_host}']):
                        redir_target = t
                else:
                    m_rd = re.search(r'Redirect(?:Match)?\\s+(?:301|302|permanent)?\\s+.*?\\s+(https?://[^\\s]+)', l, re.I)
                    if m_rd:
                        t = m_rd.group(1).rstrip('/')
                        if not any(k in t.lower() for k in ['%{server_name}', '%{http_host}']):
                            redir_target = t

        doc_root = doc_roots[0] if doc_roots else '/var/www/html'

        all_names = list(server_names)
        for a in server_aliases:
            a = a.strip()
            if a and not a.startswith('*') and a not in all_names:
                all_names.append(a)

        for dom in all_names:
            dom = dom.lower()
            if dom in ('default', 'localhost', 'default-ssl'):
                continue
            if dom not in vhosts:
                title = ''
                for idx in ['index.html', 'index.htm', 'index.php']:
                    p = os.path.join(doc_root, idx)
                    if os.path.isfile(p):
                        try:
                            with open(p, 'r', errors='ignore') as f_idx:
                                raw = f_idx.read(4096)
                                m = re.search(r'<title[^>]*>(.*?)</title>', raw, re.I | re.S)
                                if m:
                                    title = ' '.join(m.group(1).strip().split())
                        except Exception:
                            pass
                        break

                zone = 'agrarix.net' if dom.endswith('agrarix.net') else ('agrarix.nl' if dom.endswith('agrarix.nl') else ('maartendeboer.nl' if dom.endswith('maartendeboer.nl') else 'overig'))

                if redir_target:
                    category = 'VPS Redirect'
                    desc = 'Omleiding naar ' + redir_target
                else:
                    category = 'VPS Apache'
                    desc = title if title else 'Apache VHost op vps2.agrarix.net'

                vhosts[dom] = {
                    'domain': dom,
                    'host': 'vps2',
                    'root': doc_root,
                    'rel_root': 'vps2:' + doc_root,
                    'has_index': bool(title),
                    'title': title,
                    'desc': desc,
                    'category': category,
                    'has_own_cert': is_ssl,
                    'ssl_badge': 'Eigen SSL' if is_ssl else 'HTTP',
                    'is_special': False,
                    'is_custom': True,
                    'zone': zone,
                    'log_file': log_file or ''
                }
            else:
                if is_ssl:
                    vhosts[dom]['has_own_cert'] = True
                    vhosts[dom]['ssl_badge'] = 'Eigen SSL'
                if log_file and not vhosts[dom].get('log_file'):
                    vhosts[dom]['log_file'] = log_file
                if title and not vhosts[dom].get('title'):
                    vhosts[dom]['has_index'] = True
                    vhosts[dom]['title'] = title
                    if vhosts[dom]['category'] == 'VPS Apache':
                        vhosts[dom]['desc'] = title
                if redir_target and vhosts[dom]['category'] == 'VPS Apache':
                    vhosts[dom]['category'] = 'VPS Redirect'
                    vhosts[dom]['desc'] = 'Omleiding naar ' + redir_target

print(json.dumps(list(vhosts.values())))
"""

def main():
    print("==> Verbinden met vps2.agrarix.net (212.227.209.36) en scannen van Apache vhosts...")
    cmd = SSH_CMD + ["python3", "-"]
    p = subprocess.run(cmd, input=REMOTE_SCRIPT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        print(f"ERROR: Scannen van vps2 mislukt:\n{p.stderr}", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(p.stdout)
    except Exception as e:
        print(f"ERROR: JSON parse fout: {e}\nUitvoer:\n{p.stdout}", file=sys.stderr)
        sys.exit(1)

    print(f"Gevonden: {len(data)} vhosts op vps2.agrarix.net")
    out_file = "/mnt/nas/WWW/domains/vps2_vhosts.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"Opgeslagen naar {out_file}")

    # Synchroniseer alle actieve VPS2 weblogs naar NAS voor bezoekersstatistieken
    vps_log_dir = "/mnt/nas/WWW/domains/vps_logs"
    os.makedirs(vps_log_dir, exist_ok=True)
    print("==> Synchroniseren van VPS2 access logs naar NAS...")
    sync_cmd = [
        "rsync", "-avz",
        "--include=*access*.log*",
        "--exclude=access.log*", "--exclude=other_vhosts*", "--exclude=*",
        "-e", "ssh -o StrictHostKeyChecking=no -o BatchMode=yes",
        "automation@vps2.agrarix.net:/var/log/apache2/", vps_log_dir + "/"
    ]
    res = subprocess.run(sync_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode == 0:
        subprocess.run(["chmod", "-R", "a+rX", vps_log_dir])
        print("VPS2 access logs succesvol gesynchroniseerd.")
    else:
        print(f"Waarschuwing bij synchroniseren VPS2 logs: {res.stderr}", file=sys.stderr)

if __name__ == "__main__":
    main()
