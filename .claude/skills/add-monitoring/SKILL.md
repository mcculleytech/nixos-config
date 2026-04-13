Add Prometheus monitoring and a Grafana dashboard for a service. The service to add monitoring for is: $ARGUMENTS

If no service name was provided in $ARGUMENTS, ask the user which service needs monitoring before proceeding.

---

## Step 1: Identify the Service

Confirm the service name and which host it runs on. Read the service's `.nix` file to understand its current configuration.

---

## Step 2: Determine the Monitoring Path

Choose one of the two paths:

**Path A — Service has a built-in Prometheus metrics endpoint**
(Examples: Traefik exposes metrics on port 8080, Blocky on port 4000)

1. Enable the metrics endpoint within the service's own config if not already enabled.
2. Ensure the metrics port is open in `networking.firewall.allowedTCPPorts` in the service's `.nix` file.
3. Skip to Step 3.

**Path B — Service needs a dedicated NixOS exporter**
(Examples: PostgreSQL → `services.prometheus.exporters.postgres`, nginx → `services.prometheus.exporters.nginx`)

1. Check available exporters at `https://search.nixos.org/options?channel=25.11&query=services.prometheus.exporters` to find the right one.
2. Enable the exporter in the service's `.nix` file:
   ```nix
   services.prometheus.exporters.<name> = {
     enable = true;
     port = <exporter-port>;
   };
   networking.firewall.allowedTCPPorts = [ <exporter-port> ];
   ```
3. Note the exporter port for Step 3.

---

## Step 3: Add a scrapeConfigs Entry

Edit `hosts/common/optional/roles/server/prometheus.nix` and add a new entry to the `scrapeConfigs` list.

Follow the existing pattern exactly — IPs must come from `hosts = config.lab.hosts` (never hardcoded):

```nix
{
  job_name = "<service-name>";
  static_configs = [
    {
      targets = [ "${hosts.<hostname>.ip}:<port>" ];
    }
  ];
}
```

---

## Step 4: Grafana Dashboard

Search `https://grafana.com/grafana/dashboards/` for a community dashboard matching the service.

- If a good match is found: report the dashboard ID and name to the user, and remind them to import it in the Grafana UI on **atreides** (Dashboards → Import → enter ID).
- If no match is found: note that no community dashboard was found; the user can build a custom one.

Key existing dashboard IDs for reference: `1860` (Node Exporter Full), `17346` (Traefik), `13768` (Blocky).
