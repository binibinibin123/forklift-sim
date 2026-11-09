"""App Store Connect listing and submission for 지게차·견인 실기 3D (ko), through the ASC API.

Runs in GitHub Actions (.github/workflows/asc.yml) with the repository secrets
ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Every step checks what already exists,
so it is safe to run again.

  python tools/asc/asc.py setup    # listing, screenshots, categories, age rating,
                                   # price, availability, in-app purchase, review info
  python tools/asc/asc.py submit   # attach the newest processed build and submit

The app record itself (and App Privacy answers) can only be made on the website.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.yubinapps.forkliftsim"
IAP_ID = "com.yubinapps.forkliftsim.unlock"
IAP_KRW = "5500"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = {"ko": [os.path.join(ROOT, "store", "screenshots_v2", "ko", f"{i}.png") for i in range(1, 6)]}
EXCLUDE_TERRITORIES = {"CHN"}
# apps whose review contact and copyright we reuse
CONTACT_FROM = ["com.yubinapps.forkliftsim", "com.yubinapps.pockettemple", "com.yubinapps.preflight3d"]

def _md():
    return open(os.path.join(ROOT, "store", "listing.md"), encoding="utf-8").read().replace("\r\n", "\n")


def _part(loc):
    head = {"ko": "## ko (primary)", "en-US": "## en-US"}[loc]
    return _md().split("\n" + head + "\n", 1)[1].split("\n---", 1)[0]


def _inline(text, label):
    m = re.search(r"^\*\*" + re.escape(label) + r"\*\*:[ \t]*(.+)$", text, re.M)
    return m.group(1).strip()


def _para(text, label):
    return text.split("\n**" + label + "**:\n", 1)[1].split("\n\n**", 1)[0].strip()


def listing(loc):
    t = _part(loc)
    return {
        "name": _inline(t, "Name (30)"),
        "subtitle": _inline(t, "Subtitle (30)"),
        "privacyPolicyUrl": "https://binibinibin123.github.io/gentive-app-support/forklift-sim/privacy.html",
        "supportUrl": "https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html",
        "keywords": _inline(t, "Keywords (100)"),
        "promotionalText": _para(t, "Promotional text"),
        "description": _para(t, "Description"),
    }


REVIEW_NOTES = _md().split("\n## Review notes (English)\n", 1)[1].split("\n## ", 1)[0].split("\n---", 1)[0].strip()
IAP_TEXT = {"ko": ("전체 해제", "지게차 모의시험과 견인 3종 시험 전부")}
LOCALES = ("ko", "en-US")


# ------------------------------------------------------------------ http

_tok = {"t": None, "exp": 0}


def token():
    if time.time() > _tok["exp"] - 60:
        now = int(time.time())
        _tok["t"] = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100,
                                "aud": "appstoreconnect-v1"},
                               os.environ["ASC_KEY_P8"], algorithm="ES256",
                               headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
        _tok["exp"] = now + 1100
    return _tok["t"]


def call(method, path, body=None, ok_missing=False):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")
        if ok_missing and e.code == 404:
            return None
        raise RuntimeError(f"{method} {path} -> {e.code}: {msg[:1500]}") from None


def get_all(path):
    out = []
    while path:
        r = call("GET", path)
        out += r.get("data", [])
        path = r.get("links", {}).get("next")
    return out


def step(name, fn, *a):
    print(f"\n== {name}", flush=True)
    try:
        return fn(*a)
    except Exception as e:  # keep going so one run shows every problem
        print(f"!! {name} failed: {e}", flush=True)
        FAILED.append(name)
        return None


FAILED = []


def upload(ops, path):
    blob = open(path, "rb").read()
    for op in ops:
        part = blob[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=300).read()
    return hashlib.md5(blob).hexdigest()


# ------------------------------------------------------------------ lookups

def app_for(bundle):
    d = call("GET", f"/v1/apps?filter[bundleId]={bundle}")["data"]
    return d[0] if d else None


def version(app_id):
    vs = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    editable = [v for v in vs if v["attributes"]["appStoreState"] in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if editable:
        return editable[0]
    if vs:
        return vs[0]
    return call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": "1.0"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]


def app_info(app_id):
    infos = call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    for i in infos:
        if i["attributes"].get("appStoreState") != "READY_FOR_SALE":
            return i
    return infos[0]


# ------------------------------------------------------------------ setup steps

def set_app_info(app_id):
    info = app_info(app_id)
    seen = set()
    for loc in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
        lc = loc["attributes"]["locale"]
        if lc in LOCALES:
            seen.add(lc)
            L = listing(lc)
            call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {
                "type": "appInfoLocalizations", "id": loc["id"], "attributes": {
                    "name": L["name"], "subtitle": L["subtitle"], "privacyPolicyUrl": L["privacyPolicyUrl"]}}})
            print("app info set:", lc)
    for lc in LOCALES:
        if lc not in seen:   # the English listing is new in this version
            L = listing(lc)
            call("POST", "/v1/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations", "attributes": {
                    "locale": lc, "name": L["name"], "subtitle": L["subtitle"],
                    "privacyPolicyUrl": L["privacyPolicyUrl"]},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
            print("app info added:", lc)
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {
        "type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": "EDUCATION"}}}}})
    print("category Education")


def set_age_rating(app_id):
    info = app_info(app_id)
    decl = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    attrs = {}
    for k, v in decl["attributes"].items():
        if isinstance(v, bool) or k in ("gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat",
                                       "parentalControls", "ageAssurance", "userGeneratedContent",
                                       "advertising", "healthOrWellnessTopics"):
            attrs[k] = False
        elif k in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride"):
            continue
        else:
            attrs[k] = "NONE"
    for _ in range(12):
        try:
            call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {
                "type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
            print("age rating answered:", ", ".join(f"{k}={v}" for k, v in sorted(attrs.items())))
            return
        except RuntimeError as e:
            # Apple adds new required questions over time (e.g. socialMedia): answer them "no"
            missing = re.findall(r"value for the attribute '(\w+)'", str(e))
            if missing:
                for k in missing:
                    attrs[k] = False
                continue
            bad = [k for k in attrs if f"/{k}" in str(e) or f"'{k}'" in str(e) or f'"{k}"' in str(e)]
            if not bad:
                raise
            for k in bad:
                attrs.pop(k)


def set_version(app_id, v):
    attrs = {"releaseType": "AFTER_APPROVAL"}
    src = contact_source()
    if src and src.get("copyright"):
        attrs["copyright"] = src["copyright"]
    call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {
        "type": "appStoreVersions", "id": v["id"], "attributes": attrs}})
    have = {l["attributes"]["locale"]: l for l in
            call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]}
    for lc in LOCALES:
        L = listing(lc)
        a = {"description": L["description"], "keywords": L["keywords"],
             "promotionalText": L["promotionalText"], "supportUrl": L["supportUrl"]}
        if lc in have:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{have[lc]['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": have[lc]["id"], "attributes": a}})
        else:
            call("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": dict(a, locale=lc),
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
        print("version text set:", lc)


def set_screenshots(v):
    for lc in LOCALES:
        _shots(v, lc)


def _shots(v, lc):
    print("screenshots", lc)
    loc = [l for l in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
           if l["attributes"]["locale"] == lc][0]
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
    for x in sets:   # older forklift-only sets for smaller iPhones; 6.9" scales down to them
        t = x["attributes"]["screenshotDisplayType"]
        if t.startswith("APP_IPHONE_") and t != "APP_IPHONE_67":
            call("DELETE", f"/v1/appScreenshotSets/{x['id']}")
            print("removed old screenshot set:", t)
    if s is None:
        s = call("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
            "relationships": {"appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
    have = call("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]
    want = {os.path.basename(p): hashlib.md5(open(p, "rb").read()).hexdigest() for p in SHOTS[lc]}
    names = set()
    for h in have:
        a = h["attributes"]
        failed = (a.get("assetDeliveryState") or {}).get("state") == "FAILED"
        if not failed and want.get(a["fileName"]) == a.get("sourceFileChecksum"):
            names.add(a["fileName"])
        else:  # an older picture, a failed upload or one we no longer ship
            call("DELETE", f"/v1/appScreenshots/{h['id']}")
            print("removed old screenshot:", a["fileName"])
    for path in SHOTS[lc]:
        fn = os.path.basename(path)
        if fn in names:
            print("screenshot already there:", fn)
            continue
        r = call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": fn, "fileSize": os.path.getsize(path)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})["data"]
        md5 = upload(r["attributes"]["uploadOperations"], path)
        call("PATCH", f"/v1/appScreenshots/{r['id']}", {"data": {
            "type": "appScreenshots", "id": r["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
        print("uploaded", fn)


def territories():
    return [t["id"] for t in get_all("/v1/territories?limit=200")]


def set_price_free(app_id):
    pts = call("GET", f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200")["data"]
    free = next(p for p in pts if float(p["attributes"]["customerPrice"]) == 0.0)
    call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
        "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    print("app price: Free")


def set_availability(app_id):
    terrs = [t for t in territories() if t not in EXCLUDE_TERRITORIES]
    inc = [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in terrs]
    try:
        call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                       "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": i["id"]} for i in inc]}}},
            "included": inc})
        print(f"available in {len(terrs)} territories (not mainland China)")
    except RuntimeError as e:
        if "409" in str(e):
            print("availability already set; leaving it (check China is excluded):", str(e)[:200])
        else:
            raise


def contact_source():
    if hasattr(contact_source, "c"):
        return contact_source.c
    out = None
    for b in CONTACT_FROM:
        a = app_for(b)
        if not a:
            continue
        for v in call("GET", f"/v1/apps/{a['id']}/appStoreVersions?limit=5")["data"]:
            d = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail", ok_missing=True)
            if d and d.get("data") and d["data"]["attributes"].get("contactEmail"):
                out = dict(d["data"]["attributes"])
                out["copyright"] = v["attributes"].get("copyright")
                break
        if out:
            break
    contact_source.c = out
    return out


def set_review(v):
    src = contact_source()
    if not src:
        raise RuntimeError("no review contact found on the other apps")
    attrs = {k: src[k] for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if src.get(k)}
    attrs.update({"demoAccountRequired": False, "notes": REVIEW_NOTES})
    cur = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail", ok_missing=True)
    if cur and cur.get("data"):
        call("PATCH", f"/v1/appStoreReviewDetails/{cur['data']['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": cur["data"]["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    print("review contact and notes set (contact copied from an existing app)")


def iap(app_id):
    for i in get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200"):
        if i["attributes"]["productId"] == IAP_ID:
            return i
    return None


def set_iap(app_id):
    i = iap(app_id)
    if i is None:
        i = call("POST", "/v2/inAppPurchases", {"data": {
            "type": "inAppPurchases", "attributes": {
                "name": "Full Horse", "productId": IAP_ID, "inAppPurchaseType": "NON_CONSUMABLE",
                "reviewNote": "Unlocks the Muscles, Tendons and Hoof layers and all quiz questions. "
                              "Tap any chip marked PRO to open the purchase screen."},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("created IAP", IAP_ID)
    else:
        print("IAP exists:", i["attributes"].get("state"))
    iid = i["id"]
    locs = {l["attributes"]["locale"] for l in call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")["data"]}
    for locale, name, desc in (("en-US", "Full Horse", "Unlock muscles, tendons, hoof and all quizzes"),
                               ("ko", "전체 해제", "근육, 힘줄, 발굽과 모든 퀴즈 열기")):
        if locale not in IAP_TEXT:
            continue
        locale, name, desc = locale, *IAP_TEXT[locale]
        if locale in locs:
            for l in call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")["data"]:
                if l["attributes"]["locale"] == locale and l["attributes"].get("description") != desc:
                    call("PATCH", f"/v1/inAppPurchaseLocalizations/{l['id']}", {"data": {
                        "type": "inAppPurchaseLocalizations", "id": l["id"],
                        "attributes": {"name": name, "description": desc}}})
                    print("IAP localization updated", locale)
        if locale not in locs:
            call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": locale, "name": name, "description": desc},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
            print("IAP localization", locale)
    # price: Korea base ₩5,500, Apple equalizes the rest
    sched = call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule", ok_missing=True)
    if not (sched and sched.get("data")):
        pts = get_all(f"/v2/inAppPurchases/{iid}/pricePoints?filter[territory]=KOR&limit=8000")
        pp = next(p for p in pts if float(p["attributes"]["customerPrice"]) == float(IAP_KRW))
        call("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                "baseTerritory": {"data": {"type": "territories", "id": "KOR"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p0}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${p0}", "attributes": {"startDate": None},
                          "relationships": {
                              "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}},
                              "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp["id"]}}}}]})
        print("IAP price ₩5,500 (Korea base)")
    av = call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability", ok_missing=True)
    if not (av and av.get("data")):
        terrs = [t for t in territories() if t not in EXCLUDE_TERRITORIES]
        call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                              "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terrs]}}}})
        print("IAP availability set")
    shot = call("GET", f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot", ok_missing=True)
    if not (shot and shot.get("data")):
        path = os.path.join(ROOT, "store", "iap_review.png")
        r = call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": "iap_review.png", "fileSize": os.path.getsize(path)},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})["data"]
        md5 = upload(r["attributes"]["uploadOperations"], path)
        call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{r['id']}", {"data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots", "id": r["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
        print("IAP review screenshot uploaded")


# ------------------------------------------------------------------ submit

def attach_build(app_id, v):
    for _ in range(40):
        bs = call("GET", f"/v1/builds?filter[app]={app_id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1")["data"]
        min_build = int(os.environ.get("MIN_BUILD") or 0)
        if bs and int(bs[0]["attributes"]["version"]) < min_build:
            print(f"newest processed build is {bs[0]['attributes']['version']}, waiting for {min_build}...", flush=True)
            bs = []
        if bs:
            b = bs[0]
            call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build",
                 {"data": {"type": "builds", "id": b["id"]}})
            print("attached build", b["attributes"]["version"])
            return b
        print("no processed build yet, waiting...", flush=True)
        time.sleep(60)
    raise RuntimeError("no processed build after 40 minutes")


def submit(app_id, v):
    open_subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS"
                            f"&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES")["data"]
    if any(s["attributes"]["state"] in ("WAITING_FOR_REVIEW", "IN_REVIEW") for s in open_subs):
        print("already submitted:", [s["attributes"]["state"] for s in open_subs])
        return
    # a rejected submission (UNRESOLVED_ISSUES) is resubmitted as it is, with the new build
    sub = next((s for s in open_subs if s["attributes"]["state"] in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW")), None)
    if sub is None:
        sub = call("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    try:
        call("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
        print("version added to the review submission")
    except RuntimeError as e:
        if "409" not in str(e):
            raise
        print("version already in the submission:", str(e)[:300])
    # the first in-app purchase has to go in with the version; without it the
    # reviewer cannot test the unlock, so stop rather than submit without it
    i = iap(app_id)
    state = i["attributes"].get("state") if i else None
    print("IAP state:", state)
    if state == "READY_TO_SUBMIT":
        try:
            call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
                "type": "inAppPurchaseSubmissions",
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": i["id"]}}}}})
            print("IAP added for review with this version")
        except RuntimeError as e:
            if "409" not in str(e):
                raise
            print("IAP already with this submission:", str(e)[:300])
    elif state not in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"):
        raise RuntimeError(f"IAP is {state}, not ready; not submitting. Submission {sub['id']} left as a draft.")
    call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {
        "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("SUBMITTED FOR REVIEW")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "setup"
    app = app_for(BUNDLE)
    if not app:
        sys.exit(f"No App Store Connect app with bundle ID {BUNDLE}. Create it on the website first.")
    app_id = app["id"]
    print("app", app_id, app["attributes"]["name"])
    v = version(app_id)
    print("version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    if mode == "status":
        b = call("GET", f"/v1/appStoreVersions/{v['id']}/build", ok_missing=True)
        print("attached build:", (b or {}).get("data") and b["data"]["attributes"]["version"])
        for x in call("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5")["data"]:
            print("build", x["attributes"]["version"], x["attributes"]["processingState"], x["attributes"]["uploadedDate"])
        for x in call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=5")["data"]:
            print("submission", x["id"], x["attributes"]["state"])
        i = iap(app_id)
        print("IAP:", i and i["attributes"].get("state"))
        print("version attrs:", json.dumps(v["attributes"])[:800])
        if b and b.get("data"):
            print("attached build attrs:", json.dumps(b["data"]["attributes"])[:800])
        for loc in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
            a = loc["attributes"]
            print("loc", a["locale"], {k: (len(a[k]) if isinstance(a.get(k), str) else a.get(k)) for k in a})
            for st in call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
                shots = call("GET", f"/v1/appScreenshotSets/{st['id']}/appScreenshots")["data"]
                print("  set", st["attributes"]["screenshotDisplayType"],
                      [(x["attributes"]["fileName"], (x["attributes"].get("assetDeliveryState") or {}).get("state")) for x in shots])
        rd = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail", ok_missing=True)
        print("review detail:", rd and rd.get("data") and {k: bool(x) for k, x in rd["data"]["attributes"].items()})
        info = app_info(app_id)
        print("appInfo:", json.dumps(info["attributes"])[:600])
        return
    if mode in ("setup", "all"):
        step("app info, categories", set_app_info, app_id)
        step("age rating", set_age_rating, app_id)
        step("version text", set_version, app_id, v)
        step("screenshots", set_screenshots, v)
        step("review details", set_review, v)
        step("in-app purchase", set_iap, app_id)
    if mode in ("submit", "all"):
        if FAILED:
            sys.exit("Setup steps failed, not submitting: " + ", ".join(FAILED))
        b = step("attach build", attach_build, app_id, v)
        if b:
            step("submit", submit, app_id, v)
    if FAILED:
        sys.exit("Failed: " + ", ".join(FAILED))


if __name__ == "__main__":
    main()
