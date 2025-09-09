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
  - "127.0.0.1#5335" # If you need a port other than 53.
```

Dependencies

---

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

## Example Playbook

    - hosts: pihole
      roles:
         - bladewdr.pihole

## To Do

- [x] Finish work checking on SELinux enforcement state.
- [ ] Clean up
- [ ] Documentation
- [x] Make it so that the upstream DNS servers can be changed upon subsequent runs of the playbook.
- [ ] Same thing with adlists.

## License

MIT

## Author Information

[My links site.](https://links.bladewdr.xyz)
