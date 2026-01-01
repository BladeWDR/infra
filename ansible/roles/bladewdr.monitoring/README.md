# Monitoring stack role

## Overview

This role is intended to set up a monitoring stack.

Right now it sets up the following:

- Grafana
- Grafana Alloy
- Prometheus
- AlertManager

You need to set a list variable called `prometheus_servers` with the list of your Prometheus endpoints.
