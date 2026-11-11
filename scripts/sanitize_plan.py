#!/usr/bin/env python3
"""Assainit un plan Terraform JSON avant de le versionner.

Remplace par "REDACTED" toute valeur que Terraform marque comme sensible :
  - variables déclarées `sensitive = true`
  - attributs signalés par after_sensitive / before_sensitive (resource_changes)
  - attributs signalés par sensitive_values (planned_values, prior_state)
  - sorties sensibles (output_changes)

Usage : python sanitize_plan.py <plan.json> <sortie.json>
"""
import json
import re
import sys

R = "REDACTED"
# Clés dont la valeur est masquée même si Terraform ne la marque pas sensible
# (ex. secret écrit en dur dans la version naïve).
SECRET_KEY = re.compile(r"(password|passwd|secret|token|private_key)", re.I)


def scrub(value):
    """Masque les valeurs des clés « secrètes », y compris dans du JSON encodé."""
    if isinstance(value, dict):
        return {k: (R if SECRET_KEY.search(k) and isinstance(v, str) and v else scrub(v))
                for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, str) and value[:1] in "{[":
        try:
            inner = json.loads(value)
        except ValueError:
            return value
        cleaned = scrub(inner)
        if cleaned != inner:
            return json.dumps(cleaned, separators=(",", ":"))
    return value


def mask(value, sens):
    """Applique le masque `sens` (bool / dict / list) à `value`."""
    if sens is True:
        return None if value is None else R
    if isinstance(sens, dict) and isinstance(value, dict):
        return {k: mask(v, sens.get(k, False)) for k, v in value.items()}
    if isinstance(sens, list) and isinstance(value, list):
        return [mask(v, sens[i] if i < len(sens) else False) for i, v in enumerate(value)]
    return value


def walk_module(mod):
    for res in mod.get("resources", []) or []:
        if "values" in res:
            res["values"] = mask(res["values"], res.get("sensitive_values", {}))
    for child in mod.get("child_modules", []) or []:
        walk_module(child)


def sensitive_vars(plan):
    root = plan.get("configuration", {}).get("root_module", {})
    return {n for n, v in root.get("variables", {}).items() if v.get("sensitive")}


def main(src, dst):
    with open(src, encoding="utf-8") as f:
        plan = json.load(f)

    for name in sensitive_vars(plan):
        if name in plan.get("variables", {}):
            plan["variables"][name]["value"] = R

    for rc in plan.get("resource_changes", []) or []:
        ch = rc.get("change", {})
        ch["after"] = mask(ch.get("after"), ch.get("after_sensitive", False))
        ch["before"] = mask(ch.get("before"), ch.get("before_sensitive", False))

    for key in ("planned_values", "prior_state"):
        section = plan.get(key, {})
        if "values" in section:
            section = section["values"]
        if "root_module" in section:
            walk_module(section["root_module"])

    for out in (plan.get("output_changes") or {}).values():
        if out.get("after_sensitive") is True:
            out["after"] = R
        if out.get("before_sensitive") is True:
            out["before"] = R

    plan = scrub(plan)

    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        json.dump(plan, f, indent=2, ensure_ascii=False, sort_keys=False)
        f.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
