import os
import time

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
P8_PATH = os.environ.get("ASC_P8_PATH", "/tmp/asc_key.p8")
BUNDLE_ID = os.environ.get("APP_BUNDLE_ID", "com.tokyonasu.matomeyomikiri")
BUNDLE_NAME = os.environ.get("APP_BUNDLE_NAME", "Matome Yomikiri")
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

with open(P8_PATH, encoding="utf-8") as file:
    p8 = file.read()


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        p8,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def headers():
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def api_json(method, path, **kwargs):
    response = requests.request(
        method,
        f"{BASE_URL}{path}",
        headers=headers(),
        timeout=120,
        **kwargs,
    )
    try:
        body = response.json()
    except Exception:
        body = {}
    return response, body


def main():
    response, body = api_json("GET", f"/bundleIds?filter[identifier]={BUNDLE_ID}&limit=1")
    if response.status_code != 200:
        raise RuntimeError(f"Bundle ID lookup failed {response.status_code}: {response.text[:500]}")

    data = body.get("data", [])
    if data:
        bundle = data[0]
        print(f"Bundle ID already exists: {BUNDLE_ID} ({bundle['id']})")
        return

    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": BUNDLE_ID,
                "name": BUNDLE_NAME,
                "platform": "IOS",
            },
        }
    }
    response, body = api_json("POST", "/bundleIds", json=payload)
    if response.status_code not in (200, 201):
        raise RuntimeError(f"Bundle ID create failed {response.status_code}: {response.text[:500]}")

    print(f"Bundle ID created: {BUNDLE_ID} ({body['data']['id']})")


if __name__ == "__main__":
    main()
