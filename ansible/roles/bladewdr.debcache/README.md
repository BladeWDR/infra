# Ansible role for modifying the Debian server sources

This role is meant to be used with a local caching reverse proxy.

## Needed variables

You need to set up a variable called `internal_cache_server_name` that is the local DNS name or IP address of your internal proxy.

```yaml
internal_cache_server_name: https://deb.domain.tld
```

That way, once one machine updates, the rest of them can pull from the local cache instead of going out over the internet for every request.

Only works with the primary Debian, Ubuntu and Proxmox repositories, I have no plans for adding support for more unless someone wants to contribute.
