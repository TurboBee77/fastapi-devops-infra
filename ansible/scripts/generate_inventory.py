#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TERRAFORM_DIR = REPO_ROOT / "terraform"
INVENTORY_PATH = REPO_ROOT / "ansible" / "inventory" / "hosts.yml"

# nazwa grupy Ansible -> nazwa outputu w terraform/outputs.tf
ROLE_TO_OUTPUT = {
    "ci": "ci_public_ip",
    "app": "app_public_ip",
    "monitoring": "monitoring_public_ip",
}


def get_terraform_outputs() -> dict:
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"`terraform output -json` w {TERRAFORM_DIR} zakończyło się błędem:\n{result.stderr}"
        )
    return json.loads(result.stdout)


def build_inventory(outputs: dict) -> dict:
    children = {}
    for role, output_name in ROLE_TO_OUTPUT.items():
        if output_name not in outputs:
            raise KeyError(
                f"Brak outputu '{output_name}' w terraform output — sprawdź terraform/outputs.tf "
                f"albo czy infrastruktura jest zaaplikowana (terraform apply)."
            )
        ip = outputs[output_name]["value"]
        children[role] = {"hosts": {f"{role}-VM": {"ansible_host": ip}}}

    return {"all": {"children": children}}


def main() -> None:
    outputs = get_terraform_outputs()
    inventory = build_inventory(outputs)

    INVENTORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    with INVENTORY_PATH.open("w") as f:
        f.write("# Plik wygenerowany automatycznie przez scripts/generate_inventory.py\n")
        f.write("# NIE edytuj ręcznie — zmiany zostaną nadpisane przy kolejnym uruchomieniu.\n")
        yaml.safe_dump(inventory, f, default_flow_style=False, sort_keys=False)

    print(f"Zapisano inventory: {INVENTORY_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Błąd: {exc}", file=sys.stderr)
        sys.exit(1)
