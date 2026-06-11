"""Register bundle IDs and enable App Groups capability.

With automatic signing, Xcode manages provisioning profiles.
This script just ensures bundle IDs exist and have App Groups enabled.
"""
import os
import sys
import time

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
P8_PATH = os.environ.get("ASC_P8_PATH", "/tmp/asc_key.p8")

BUNDLE_IDS = [
    ("com.tokyonasu.matomeyomikiri", "MatomeYomikiri"),
    ("com.tokyonasu.matomeyomikiri.widget", "MatomeWidget"),
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
        response = requests.request(
            method,
            f"https://api.appstoreconnect.apple.com/v1{path}",
            headers=headers(),
            timeout=120,
            **kwargs,
        )
        if response.status_code not in (401, 429, 500, 502, 503, 504):
            return response
        time.sleep(20)
    return response


def find_bundle_id(identifier):
    response = api("GET", f"/bundleIds?filter[identifier]={identifier}&limit=5")
    if response.status_code != 200:
        return None
    for item in response.json().get("data", []):
        if item.get("attributes", {}).get("identifier") == identifier:
            return item
    return None


def register_bundle_id(identifier, name):
    response = api("POST", "/bundleIds", json={
        "data": {
            "type": "bundleIds",
            "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
        }
    })
    if response.status_code not in (200, 201):
        if response.status_code == 409:
            print(f"  Bundle ID already exists")
            return find_bundle_id(identifier)
        raise RuntimeError(f"Register bundle ID failed {response.status_code}: {response.text[:500]}")
    return response.json()["data"]


def enable_app_groups(bundle_id_resource_id):
    response = api("POST", "/bundleIdCapabilities", json={
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "APP_GROUPS"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource_id}}
            },
        }
    })
    if response.status_code in (200, 201):
        print("  App Groups enabled")
    elif response.status_code == 409:
        print("  App Groups already enabled")
    else:
        print(f"  App Groups: {response.status_code} {response.text[:200]}")


def main():
    for identifier, name in BUNDLE_IDS:
        print(f"\n--- {identifier} ---")
        bundle = find_bundle_id(identifier)
        if not bundle:
            print(f"  Registering...")
            bundle = register_bundle_id(identifier, name)
        if not bundle:
            raise RuntimeError(f"Could not find or create bundle ID: {identifier}")
        print(f"  Bundle ID: {bundle['id']}")
        enable_app_groups(bundle["id"])
    print("\nDone. Automatic signing will handle provisioning profiles.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
