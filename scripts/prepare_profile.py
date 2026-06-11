"""Create provisioning profiles for manual signing (main app + widget)."""
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

PROFILES_DIR = Path.home() / "Library/MobileDevice/Provisioning Profiles"

TARGETS = [
    {
        "bundle_id": "com.tokyonasu.matomeyomikiri",
        "profile_name": "MatomeYomikiri AppStore",
        "filename": "MatomeYomikiri_AppStore.mobileprovision",
    },
    {
        "bundle_id": "com.tokyonasu.matomeyomikiri.widget",
        "profile_name": "MatomeWidget AppStore",
        "filename": "MatomeWidget_AppStore.mobileprovision",
    },
]


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


def find_bundle_id(identifier):
    """Find bundle ID with exact match."""
    resp = api("GET", f"/bundleIds?filter[identifier]={identifier}&limit=10")
    if resp.status_code != 200:
        return None
    for item in resp.json().get("data", []):
        if item.get("attributes", {}).get("identifier") == identifier:
            return item
    return None


def register_bundle_id(identifier, name):
    resp = api("POST", "/bundleIds", json={
        "data": {
            "type": "bundleIds",
            "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
        }
    })
    if resp.status_code in (200, 201):
        return resp.json()["data"]
    if resp.status_code == 409:
        print(f"  Already registered")
        return find_bundle_id(identifier)
    raise RuntimeError(f"Register failed {resp.status_code}: {resp.text[:500]}")


def enable_app_groups(bundle_resource_id):
    resp = api("POST", "/bundleIdCapabilities", json={
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "APP_GROUPS"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}
            },
        }
    })
    if resp.status_code in (200, 201):
        print("  App Groups: enabled")
    elif resp.status_code == 409:
        print("  App Groups: already enabled")
    else:
        print(f"  App Groups: {resp.status_code} (warning)")


def find_distribution_certificate():
    """Find a valid Apple Distribution certificate."""
    for cert_type in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        resp = api("GET", f"/certificates?filter[certificateType]={cert_type}&limit=20")
        if resp.status_code != 200:
            continue
        for cert in resp.json().get("data", []):
            name = cert.get("attributes", {}).get("name", "")
            # Prefer "Apple Distribution" over legacy "iPhone Distribution"
            if "Apple Distribution" in name:
                return cert
        # Fall back to any cert of this type
        certs = resp.json().get("data", [])
        if certs:
            return certs[0]
    raise RuntimeError("No distribution certificate found")


def delete_profiles_by_name(name):
    resp = api("GET", f"/profiles?filter[name]={name}&limit=20")
    if resp.status_code != 200:
        return
    for profile in resp.json().get("data", []):
        api("DELETE", f"/profiles/{profile['id']}")
        print(f"  Deleted old profile: {profile['id']}")


def create_profile(name, bundle_resource_id, cert_id):
    resp = api("POST", "/profiles", json={
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    })
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Profile create failed {resp.status_code}: {resp.text[:500]}")
    return resp.json()["data"]


def install_profile(profile, filename):
    content = profile.get("attributes", {}).get("profileContent")
    if not content:
        resp = api("GET", f"/profiles/{profile['id']}")
        if resp.status_code == 200:
            content = resp.json().get("data", {}).get("attributes", {}).get("profileContent")
    if not content:
        raise RuntimeError(f"No profile content for {filename}")
    path = PROFILES_DIR / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64decode(content))
    print(f"  Installed: {path}")


def main():
    # Step 1: Find certificate
    cert = find_distribution_certificate()
    cert_name = cert.get("attributes", {}).get("name", "?")
    print(f"Certificate: {cert['id']} ({cert_name})")

    # Step 2: Register bundle IDs and enable App Groups
    bundles = {}
    for target in TARGETS:
        bid = target["bundle_id"]
        print(f"\n--- {bid} ---")
        bundle = find_bundle_id(bid)
        if not bundle:
            bundle = register_bundle_id(bid, target["profile_name"].replace(" AppStore", ""))
        if not bundle:
            raise RuntimeError(f"Cannot find/create bundle ID: {bid}")
        print(f"  Resource ID: {bundle['id']}")
        enable_app_groups(bundle["id"])
        bundles[bid] = bundle

    # Step 3: Delete old profiles and create fresh ones
    # Also delete any profiles with old naming (with "App Store" space)
    for target in TARGETS:
        bid = target["bundle_id"]
        name = target["profile_name"]
        print(f"\n--- Profile: {name} ---")
        delete_profiles_by_name(name)
        # Also clean up old-style names
        old_name = name.replace("AppStore", "App Store")
        if old_name != name:
            delete_profiles_by_name(old_name)
        profile = create_profile(name, bundles[bid]["id"], cert["id"])
        install_profile(profile, target["filename"])

    print("\nAll profiles ready.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
