# App Store Connect API from the shell, no fastlane: TestFlight invites, groups,
# beta review. The .p8 key lives at ~/.appstoreconnect/private_keys/AuthKey_<KID>.p8,
# never in this repo. HANDOFF.md has the recipes.
#
#   python3 tools/asc.py GET "/v1/apps/6765705839/betaGroups"
#   python3 tools/asc.py POST /v1/betaTesters '{"data":{...}}'
import base64, json, os, sys, time, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
KID=os.environ.get("ASC_KEY_ID","BUU5Z6J9GL"); ISS=os.environ.get("ASC_ISSUER_ID","0532bf3e-7644-40b9-a9c4-eeb3e92a8b9e")
b = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode()
def token():
    now=int(time.time())
    h=b(json.dumps({"alg":"ES256","kid":KID,"typ":"JWT"}).encode())
    p=b(json.dumps({"iss":ISS,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}).encode())
    k=serialization.load_pem_private_key(open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KID}.p8"),"rb").read(),None)
    r,s=decode_dss_signature(k.sign(f"{h}.{p}".encode(),ec.ECDSA(hashes.SHA256())))
    return f"{h}.{p}.{b(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}"
def call(method, path, body=None):
    req=urllib.request.Request("https://api.appstoreconnect.apple.com"+path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization":"Bearer "+token(),"Content-Type":"application/json"})
    try:
        r=urllib.request.urlopen(req); t=r.read(); return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")
if __name__=="__main__":
    m,p=sys.argv[1],sys.argv[2]; body=json.loads(sys.argv[3]) if len(sys.argv)>3 else None
    s,d=call(m,p,body); print(s); print(json.dumps(d,indent=1))
