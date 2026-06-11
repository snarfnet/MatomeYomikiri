"""Create provisioning profile for manual signing."""
import base64
import os
import sys
import time
from pathlib import Path

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
P8_PATH = os.environ.get("ASC_P8_PATH", "/tmp/asc_key.p8")
BUNDLE_ID = "com.tokyonasu.matomeyomikiri"
PROFILE_NAME = "MatomeYomikiri AppStore"
PROFILE_PATH = Path.home() / "Library/MobileDevice/Provisioning Profiles/MatomeYomikiri_AppStore.mobileprovision"


def make_token():
    now = int(time.time())
    with open(P8_PATH, encoding="utf-8") as file:
        private_key = file.read()
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def headers():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}


def api(method, path, **kwargs):
    for _ in range(6):
        resp = requests.request(
            method,
            f"https://api.appstoreconnect.apple.com/v1{path}",
            headers=headers(),
            timeout=120,
            **kwargs,
        )
        if resp.status_code not in (401, 429, 500, 502, 503, 504):
            return resp
        time.sleep(20)
    return resp


def find_bundle_id():
    resp = api("GET", f"/bundleIds?filter[identifier]={BUNDLE_ID}&limit=5")
    if resp.status_code != 200:
        raise RuntimeError(f"Bundle ID lookup failed: {resp.status_code}")
    for item in resp.json().get("data", []):
        if item.get("attributes", {}).get("identifier") == BUNDLE_ID:
            return item
    raise RuntimeError(f"Bundle ID {BUNDLE_ID} not found")


def find_distribution_certificate():
    """Find the distribution cert that matches what's in the keychain."""
    for cert_type in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        resp = api("GET", f"/certificates?filter[certificateType]={cert_type}&limit=20")
        if resp.status_code != 200:
            continue
        certs = resp.json().get("data", [])
        # Sort by expiration (newest first) to get the most recent cert
        certs.sort(key=lambda c: c.get("attributes", {}).get("expirationDate", ""), reverse=True)
        if certs:
            return certs[0]
    raise RuntimeError("No distribution certificate found")


def main():
    bundle = find_bundle_id()
    print(f"Bundle ID: {bundle['id']} ({BUNDLE_ID})")

    cert = find_distribution_certificate()
    print(f"Certificate: {cert['id']} ({cert['attributes'].get('name')})")

    # Delete old profiles with this name
    resp = api("GET", f"/profiles?filter[name]={PROFILE_NAME}&limit=20")
    if resp.status_code == 200:
        for profile in resp.json().get("data", []):
            api("DELETE", f"/profiles/{profile['id']}")
            print(f"Deleted old profile: {profile['id']}")

    # Also clean up old-style name
    for old_name in ("MatomeYomikiri App Store",):
        resp = api("GET", f"/profiles?filter[name]={old_name}&limit=20")
        if resp.status_code == 200:
            for profile in resp.json().get("data", []):
                api("DELETE", f"/profiles/{profile['id']}")

    # Create fresh profile
    resp = api("POST", "/profiles", json={
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
            },
        }
    })
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Profile create failed {resp.status_code}: {resp.text[:500]}")

    profile = resp.json()["data"]
    content = profile.get("attributes", {}).get("profileContent")
    if not content:
        resp2 = api("GET", f"/profiles/{profile['id']}")
        content = resp2.json().get("data", {}).get("attributes", {}).get("profileContent")

    if not content:
        raise RuntimeError("Profile content is empty")

    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    PROFILE_PATH.write_bytes(base64.b64decode(content))
    print(f"Installed: {PROFILE_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
