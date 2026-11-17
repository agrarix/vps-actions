#!/usr/bin/env python3
"""
Test script to verify condolence register with moderation on new.biancawennink.nl
"""
import urllib.request
import urllib.parse
import http.cookiejar
import re
import time
import sys
import subprocess

def main():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

    url = 'https://new.biancawennink.nl/condoleanceregister/'
    print(f"Fetching {url}...")
    resp = opener.open(url).read().decode('utf-8')

    m_csrf = re.search(r'name="csrf_token" value="([^"]+)"', resp)
    m_time = re.search(r'name="form_time" value="([^"]+)"', resp)

    if not m_csrf or not m_time:
        print("ERROR: could not find CSRF token or form_time in page")
        sys.exit(1)

    csrf = m_csrf.group(1)
    form_time = m_time.group(1)

    print("Waiting 3 seconds (anti-bot cooldown)...")
    time.sleep(3)

    test_naam = 'Afkeur Testbericht'
    data = urllib.parse.urlencode({
        'csrf_token': csrf,
        'form_time': form_time,
        'website': '',
        'naam': test_naam,
        'relatie': 'Test Afkeur',
        'email': 'afkeur@agrarix.nl',
        'bericht': 'Dit bericht moet straks afgekeurd worden en in data/afgekeurd belanden.'
    }).encode('utf-8')

    req = urllib.request.Request(url, data=data, headers={'User-Agent': 'Mozilla/5.0'})
    res2 = opener.open(req)
    body = res2.read().decode('utf-8')

    if 'wordt na controle geplaatst' in body:
        print("SUCCESS: Post 1 accepted for moderation.")
    else:
        print("WARNING: Moderation message not found.")

if __name__ == '__main__':
    main()
