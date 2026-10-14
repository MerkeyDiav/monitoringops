import jinja2, yaml, sys

src = open(sys.argv[1]).read()
for name, env in [("trim_blocks=True", jinja2.Environment(trim_blocks=True)),
                  ("plain", jinja2.Environment())]:
    v = {
        "prometheus_scrape_interval": "15s",
        "prometheus_evaluation_interval": "15s",
        "prometheus_config_dir": "/etc/prometheus",
        "prometheus_port": 9090,
        "node_exporter_targets": ["18.217.30.53:9100", "3.21.100.7:9100"],
    }
    r = env.from_string(src).render(**v)
    d = yaml.safe_load(r)
    tgts = d["scrape_configs"][1]["static_configs"][0]["targets"]
    print(name, "-> targets =", tgts)
    assert tgts == ["18.217.30.53:9100", "3.21.100.7:9100"], "MISMATCH"
    if name == "trim_blocks=True":
        print("--- rendered lines 20-27 ---")
        for i, l in enumerate(r.splitlines()[19:27], start=20):
            print(i, repr(l))
print("ALL OK")
