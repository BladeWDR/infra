Script logic

main function calls these other functions in order:

- checkSelinux
- build_dependency_package
- install_dependent_packages
- Checks to make sure that the FTL binary is available.
- if the config files exist (either a toml file for v6 or a .conf file for v5), then it sets fresh_install to false and runs an unattended setup. It does so by setting an env var called DEBIAN_FRONTEND="noninteractive"
- if they don't exist it does the following in order:
  - Creates the pihole directory, owned by pihole, mode 755
  - runs the get_available_interfaces function
  - Runs collect_v4andv6_information function
  - Runs setDNS function
  - Runs chooseBlocklists
  - Runs queryLogging
  - runs setPrivacyLevel
- Downloads and installs FTL.
