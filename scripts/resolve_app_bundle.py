import os
import sys
import time

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
APP_ID = os.environ["APP_ID"]
P8_PATH = os.environ.get("ASC_P8_PATH", "/tmp/asc_key.p8")


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


def main():
    response = requests.get(
        f"https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}",
        headers={"Authorization": f"Bearer {make_token()}"},
        timeout=120,
    )
    if response.status_code != 200:
        raise RuntimeError(f"App lookup failed {response.status_code}: {response.text[:500]}")
    attrs = response.json()["data"]["attributes"]
    bundle_id = attrs.get("bundleId")
    if not bundle_id:
        raise RuntimeError("App Store Connect did not return a bundleId for this app.")
    print(f"APP_BUNDLE_ID={bundle_id}")
    print(f"Resolved Bundle ID: {bundle_id}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
