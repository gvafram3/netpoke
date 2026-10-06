#!/usr/bin/env python3
"""
Make the two experiment arms for the authors' 'mutex' benchmark from their own yamls.

  python3 make_mutex_yamls.py --image gvafram3/slowpoke:mutex-netpoke --payload 8192

creates  evaluation/mutex/yamls-freeze/   (SLOWPOKE_NETPOKE=0  -> SIGSTOP only = SlowPoke as published)
         evaluation/mutex/yamls-hold/     (SLOWPOKE_NETPOKE=1  -> SIGSTOP + network hold)

Both arms use the SAME image and BOTH get NET_ADMIN, so the only difference is one env var.
(If the two arms used different images, the comparison would not isolate the hold.)
--payload N sets RESPONSE_PAYLOAD_BYTES on service2 (needs the patched image). 0 = leave off.
"""
import argparse, copy, os, sys, yaml

ap = argparse.ArgumentParser()
ap.add_argument("--src", default=os.path.expanduser("~/slowpoke/evaluation/mutex/yamls"))
ap.add_argument("--image", required=True)
ap.add_argument("--payload", type=int, default=0)
ap.add_argument("--suffix", default="", help="e.g. _cpu -> yamls-freeze_cpu / yamls-hold_cpu (keep several variants side by side)")
a = ap.parse_args()
base = os.path.dirname(a.src.rstrip("/"))
orig = os.path.join(base, "yamls-orig")
if not os.path.isdir(orig):
    os.system(f"cp -r '{a.src}' '{orig}'")          # keep the authors' originals safe
src = orig

def setenv(env, name, value):
    for e in env:
        if e["name"] == name:
            e["value"] = value; return
    env.append({"name": name, "value": value})

# Every env value must stay a QUOTED string: after envsubst fills "${X}" with a number, an unquoted value would become a
# YAML number and Kubernetes rejects it ("cannot unmarshal number into ... EnvVar ... value of type string").
class Q(str): pass
yaml.SafeDumper.add_representer(Q, lambda d, v: d.represent_scalar("tag:yaml.org,2002:str", str(v), style='"'))
def quote_env(c):
    for e in c.get("env", []):
        if "value" in e: e["value"] = Q("" if e["value"] is None else str(e["value"]))

for arm, flag in (("freeze", "0"), ("hold", "1")):
    out = os.path.join(base, f"yamls-{arm}{a.suffix}")
    os.makedirs(out, exist_ok=True)
    for fn in sorted(os.listdir(src)):
        if not fn.endswith(".yaml"): continue
        docs = list(yaml.safe_load_all(open(os.path.join(src, fn))))
        for d in docs:
            if d and d.get("kind") == "Deployment":
                c = d["spec"]["template"]["spec"]["containers"][0]
                c["image"] = a.image
                c.setdefault("securityContext", {}).setdefault("capabilities", {})["add"] = ["NET_ADMIN"]
                env = c.setdefault("env", [])
                setenv(env, "SLOWPOKE_NETPOKE", flag)
                if a.payload and d["metadata"]["name"] == "service2":
                    setenv(env, "RESPONSE_PAYLOAD_BYTES", str(a.payload))
                quote_env(c)
        with open(os.path.join(out, fn), "w") as f:
            yaml.safe_dump_all(docs, f, default_flow_style=False, sort_keys=False)
    print(f"wrote {out}")
