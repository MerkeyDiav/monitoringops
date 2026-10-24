#!/bin/bash
export ANSIBLE_HOST_KEY_CHECKING=False
cd ~/monitoringops/ansible || exit 1

echo "===== app_server : services node_exporter / promtail ====="
ansible app_server -i inventory.ini -m shell -a 'for s in node_exporter promtail; do printf "%-14s: " $s; systemctl is-active $s 2>/dev/null || echo absent; done' 2>/dev/null | grep -vE 'world writable|Deprecation|deprecat|discovered_interpreter|interpreter_discovery|WARNING|SUCCESS|CHANGED|rc=0'

echo
echo "===== obs_collector : cibles scrapees par Prometheus (/targets) ====="
ansible obs_collector -i inventory.ini -m shell -a 'curl -s http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); [print(\"  %-14s %-8s %s\" % (t[\"labels\"].get(\"job\",\"?\"), t[\"health\"], t.get(\"lastError\",\"\"))) for t in d[\"data\"][\"activeTargets\"]]" 2>/dev/null || echo "  (pas de reponse de Prometheus)"' 2>/dev/null | grep -vE 'world writable|Deprecation|deprecat|discovered_interpreter|interpreter_discovery|WARNING|SUCCESS|CHANGED|rc=0'
