# Role Name

A brief description of the role goes here.

## Requirements

None.

## Role Variables

All needed variables are set via defaults, but you can override whatever you like.

`pihole_upstream_dns_servers` should be specified as a YAML list:

```yaml
pihole_upstream_dns_servers:
  - "8.8.8.8"
  - "1.1.1.1"
```

Dependencies

---

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

## Example Playbook

    - hosts: pihole
      roles:
         - bladewdr.pihole

## To Do

- [ ] Finish work checking on SELinux enforcement state.
- [ ] Clean up
- [ ] Documentation

## License

MIT

## Author Information

[My links site.](https://links.bladewdr.xyz)
