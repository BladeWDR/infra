# Certbot ansible role

I found Jeff Geerling's version of this a bit too complex for my needs, so I wrote my own.

This version uses a DNS challenge instead of HTTP01.

## Variables that need to be set:

- `certbot_cloudflare_api_key`
- `certbot_email`
- `certbot_domains`

I recommend putting this in a secrets store. Ansible vault is fine.

## Variables and their defaults

| Variable                          | Defaults                |
| --------------------------------- | ----------------------- |
| `certbot_secrets_dir`             | /root/.secrets          |
| `certbot_secrets_file`            | cloudflare.ini          |
| `certbot_cloudflare_api_key`      | None                    |
| `certbot_domains`                 | none. Should be a list. |
| `certbot_dns_propagation_seconds` | 60                      |
