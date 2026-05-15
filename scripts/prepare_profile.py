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
BUNDLE_ID = os.environ.get("APP_BUNDLE_ID", "com.tokyonasu.matomeyomikiri")
PROFILE_NAME = os.environ.get("PROFILE_NAME", "MatomeYomikiri App Store")
PROFILE_PATH = Path.home() / "Library/MobileDevice/Provisioning Profiles/MatomeYomikiri_App_Store.mobileprovision"


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


def api_json(method, path, **kwargs):
    response = api(method, path, **kwargs)
    try:
        body = response.json()
    except Exception:
        body = {}
    if response.status_code not in (200, 201, 204):
        raise RuntimeError(f"{method} {path} failed {response.status_code}: {response.text[:500]}")
    return body


def first(path, label):
    data = api_json("GET", path).get("data", [])
    if not data:
        raise RuntimeError(f"No {label} found for {path}")
    return data[0]


def find_distribution_certificate():
    for cert_type in ("IOS_DISTRIBUTION", "DISTRIBUTION"):
        data = api_json("GET", f"/certificates?filter[certificateType]={cert_type}&limit=20").get("data", [])
        if data:
            return data[0]
    return first("/certificates?limit=20", "distribution certificate")


def find_or_create_profile(bundle_id, certificate_id):
    existing = api_json("GET", f"/profiles?filter[name]={PROFILE_NAME}&limit=20").get("data", [])
    for profile in existing:
        attrs = profile.get("attributes", {})
        if attrs.get("profileState") == "ACTIVE" and attrs.get("profileContent"):
            return profile

    payload = {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    }
    return api_json("POST", "/profiles", json=payload)["data"]


def main():
    bundle = first(f"/bundleIds?filter[identifier]={BUNDLE_ID}&limit=1", "bundle id")
    certificate = find_distribution_certificate()
    profile = find_or_create_profile(bundle["id"], certificate["id"])
    content = profile.get("attributes", {}).get("profileContent")
    if not content:
        profile = api_json("GET", f"/profiles/{profile['id']}")["data"]
        content = profile.get("attributes", {}).get("profileContent")
    if not content:
        raise RuntimeError("Provisioning profile was created, but profileContent was empty.")

    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    PROFILE_PATH.write_bytes(base64.b64decode(content))
    print(PROFILE_PATH)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
