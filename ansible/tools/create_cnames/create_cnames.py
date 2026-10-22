#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request


def load_env(env_path=".env"):
    """Simple parser for .env files without external dependencies."""
    if not os.path.exists(env_path):
        return

    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip("'\"")
            if key not in os.environ:
                os.environ[key] = val


def create_cname(server_url, token, domain, cname_target, overwrite=True):
    """Call Technitium DNS API /api/zones/records/add to create a CNAME record."""
    endpoint = f"{server_url.rstrip('/')}/api/zones/records/add"
    
    params = {
        "token": token,
        "domain": domain,
        "type": "CNAME",
        "cname": cname_target,
        "overwrite": "true" if overwrite else "false",
    }
    
    url = f"{endpoint}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, method="GET")
    
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            res_data = json.loads(response.read().decode("utf-8"))
            if res_data.get("status") == "ok":
                return True, "Successfully created CNAME record"
            else:
                err_msg = res_data.get("errorMessage", "Unknown API error")
                return False, f"API Error: {err_msg}"
    except Exception as e:
        return False, f"HTTP Request failed: {e}"


def main():
    parser = argparse.ArgumentParser(
        description="Create Technitium DNS CNAME records from a text file."
    )
    parser.add_argument(
        "cname_target",
        help="The target canonical domain/host for the CNAME records (e.g. test.example.com or 192.168.1.10)"
    )
    parser.add_argument(
        "domains_file",
        nargs="?",
        default="domains.txt",
        help="Path to the text file containing domain names, one per line (default: domains.txt)"
    )
    parser.add_argument(
        "--env-file",
        default=".env",
        help="Path to .env file (default: .env)"
    )
    parser.add_argument(
        "--server",
        help="Technitium DNS Server URL (default: TECHNITIUM_SERVER_URL from .env or http://localhost:5380)"
    )
    parser.add_argument(
        "--no-overwrite",
        action="store_true",
        help="Do not overwrite existing DNS records if they already exist"
    )

    args = parser.parse_args()

    # Load environment variables
    load_env(args.env_file)

    # Retrieve API key
    api_key = os.getenv("TECHNITIUM_API_KEY") or os.getenv("TECHNITIUM_TOKEN") or os.getenv("TECHNITIUM_API_TOKEN")
    if not api_key:
        print(f"Error: TECHNITIUM_API_KEY not found in environment or '{args.env_file}'.", file=sys.stderr)
        print("Please define TECHNITIUM_API_KEY in your .env file.", file=sys.stderr)
        sys.exit(1)

    # Determine server URL
    server_url = args.server or os.getenv("TECHNITIUM_SERVER_URL") or os.getenv("TECHNITIUM_URL") or "http://localhost:5380"

    # Check input domain file
    if not os.path.exists(args.domains_file):
        print(f"Error: Domains file '{args.domains_file}' not found.", file=sys.stderr)
        sys.exit(1)

    # Read domain names from file
    domains = []
    with open(args.domains_file, "r", encoding="utf-8") as f:
        for line in f:
            domain = line.strip()
            if domain and not domain.startswith("#"):
                domains.append(domain)

    if not domains:
        print(f"No valid domain names found in '{args.domains_file}'.")
        sys.exit(0)

    print(f"Technitium Server URL: {server_url}")
    print(f"CNAME Target:          {args.cname_target}")
    print(f"Processing {len(domains)} domain(s) from '{args.domains_file}'...\n")

    overwrite = not args.no_overwrite
    success_count = 0

    for domain in domains:
        ok, msg = create_cname(server_url, api_key, domain, args.cname_target, overwrite=overwrite)
        if ok:
            print(f"  [SUCCESS] {domain} -> {args.cname_target}")
            success_count += 1
        else:
            print(f"  [FAILED]  {domain}: {msg}")

    print(f"\nCompleted: {success_count}/{len(domains)} CNAME record(s) created successfully.")


if __name__ == "__main__":
    main()
