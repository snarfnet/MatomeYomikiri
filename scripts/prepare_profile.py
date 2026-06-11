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

TARGETS = [
    {
        "bundle_id": "com.tokyonasu.matomeyomikiri",
        "profile_name": "MatomeYomikiri App Store",
        "profile_path": Path.home() / "Library/MobileDevice/Provisioning Profiles/MatomeYomikiri_App_Store.mobileprovision",
    },
    {
        "bundle_id": "com.tokyonasu.matomeyomikiri.widget",
        "profile_name": "MatomeWidget App Store",
        "profile_path": Path.home() / "Library/MobileDevice/Provisioning Profiles/MatomeWidget_App_Store.mobileprovision",
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


def find_distribution_certificate():
    for cert_type in ("IOS_DISTRIBUTION", "DISTRIBUTION"):
        data = api_json("GET", f"/certificates?filter[certificateType]={cert_type}&limit=20").get("data", [])
        if data:
            return data[0]
    data = api_json("GET", "/certificates?limit=20").get("data", [])
    if not data:
        raise RuntimeError("No distribution certificate found")
    return data[0]


def find_bundle_id(identifier):
    data = api_json("GET", f"/bundleIds?filter[identifier]={identifier}&limit=1").get("data", [])
    if data:
        return data[0]
    return None


def register_bundle_id(identifier, name):
    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        }
    }
    return api_json("POST", "/bundleIds", json=payload)["data"]


def enable_app_groups(bundle_id_resource_id):
    payload = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "APP_GROUPS",
                "settings": [
                    {
                        "key": "APP_GROUP_IDENTIFIERS",
                        "options": [
                            {
                                "key": "group.com.tokyonasu.matomeyomikiri",
                            }
                        ],
                    }
                ],
            },
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle_id_resource_id}
                }
            },
        }
    }
    try:
        api_json("POST", "/bundleIdCapabilities", json=payload)
    except RuntimeError as e:
        if "ENTITY_ERROR.ATTRIBUTE.INVALID" in str(e) or "already exists" in str(e).lower():
            print(f"  App Groups capability already enabled")
        else:
            raise


def find_or_create_profile(profile_name, bundle_id_resource_id, certificate_id):
    existing = api_json("GET", f"/profiles?filter[name]={profile_name}&limit=20").get("data", [])
    for profile in existing:
        attrs = profile.get("attributes", {})
        if attrs.get("profileState") == "ACTIVE" and attrs.get("profileContent"):
            return profile

    # Delete invalid profiles with same name
    for profile in existing:
        try:
            api("DELETE", f"/profiles/{profile['id']}")
        except Exception:
            pass

    payload = {
        "data": {
            "type": "profiles",
            "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    }
    return api_json("POST", "/profiles", json=payload)["data"]


def download_profile(profile, output_path):
    content = profile.get("attributes", {}).get("profileContent")
    if not content:
        profile = api_json("GET", f"/profiles/{profile['id']}")["data"]
        content = profile.get("attributes", {}).get("profileContent")
    if not content:
        raise RuntimeError(f"Profile content empty for {profile['attributes'].get('name', '?')}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(base64.b64decode(content))
    print(f"  Saved: {output_path}")


def main():
    certificate = find_distribution_certificate()
    print(f"Certificate: {certificate['id']}")

    for target in TARGETS:
        print(f"\n--- {target['bundle_id']} ---")

        bundle = find_bundle_id(target["bundle_id"])
        if not bundle:
            print(f"  Registering bundle ID...")
            bundle = register_bundle_id(target["bundle_id"], target["profile_name"].replace(" App Store", ""))

        print(f"  Bundle ID: {bundle['id']}")
        enable_app_groups(bundle["id"])

        profile = find_or_create_profile(target["profile_name"], bundle["id"], certificate["id"])
        download_profile(profile, target["profile_path"])


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
