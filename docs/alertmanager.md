# Alertmanager – rôle Ansible

## 1. Architecture

```text
node_exporter (k8s_nodes :9100) ──scrape──> Prometheus (obs_collector :9090)
                                               │ évalue rules/alert_rules.yml
                                               ▼
                                        Alertmanager (obs_collector :9093)
                                               │ regroupe / déduplique / route
                                 ┌─────────────┼──────────────┐
                                 ▼             ▼              ▼
                          "null" (Watchdog)  default        critical
                                             (warning)      (severity=critical)
                                             e-mail/Slack   e-mail/Slack
```

## 2. Fichiers

| Fichier | Rôle |
|---|---|
| `ansible/playbooks/roles/alertmanager/defaults/main.yml` | Valeurs par défaut (version, ports, routage, notifications) |
| `ansible/playbooks/roles/alertmanager/tasks/main.yml` | Installation, configuration, service, health check |
| `ansible/playbooks/roles/alertmanager/handlers/main.yml` | `Restart` (binaire / systemd) et `Reload` (config, sans coupure) |
| `ansible/playbooks/roles/alertmanager/templates/alertmanager.yml.j2` | Configuration Alertmanager |
| `ansible/playbooks/roles/alertmanager/templates/alertmanager.service.j2` | Unité systemd durcie |
| `ansible/playbooks/roles/prometheus/templates/alert_rules.yml.j2` | Règles d'alerte Prometheus |
| `ansible/group_vars/observability_servers/vars.yml` | Paramètres de l'environnement |
| `ansible/group_vars/observability_servers/vault.yml` | Secrets chiffrés (à créer, voir §4) |

## 3. Bonnes pratiques appliquées

- **Version épinglée** et archive vérifiée par **SHA256** officiel.
- **Idempotence** : `creates:` sur l'extraction, `copy`/`template` ne changent que si le contenu diffère.
- **Compte système dédié** `alertmanager` sans shell ni home.
- **Permissions** : config `root:alertmanager 0640` (le service lit mais ne peut pas modifier) ; seul `/var/lib/alertmanager` est inscriptible.
- **Validation avant déploiement** : `amtool check-config` (Alertmanager) et `promtool check rules` (Prometheus). Une config invalide fait échouer la tâche, l'ancienne reste en place.
- **Reload à chaud** (SIGHUP) quand seule la config change ; redémarrage uniquement si binaire ou unité systemd changent.
- **Secrets** dans Ansible Vault, masqués dans les logs (`no_log`).
- **systemd durci** : `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`.
- **Health check** sur `/-/ready` à la fin du rôle.
- **Mode cluster désactivé** par défaut (instance unique) ; HA possible via `alertmanager_cluster_peers`.
- **Alerte Watchdog** toujours active pour prouver que la chaîne Prometheus → Alertmanager fonctionne, routée vers `null` pour ne pas spammer.
- **Inhibition** : une alerte `critical` masque la `warning` équivalente sur la même instance.

## 4. Configurer les notifications

> Actuellement **désactivées** (phase de test). Procédure de test, options
> Outlook / Teams et questions à poser : [alertmanager_notifications.md](alertmanager_notifications.md).

1. Décommenter le bloc du canal voulu dans `group_vars/observability_servers/vars.yml`
   (e-mail : `alertmanager_smtp_*`, Teams : `alertmanager_msteams_webhook_url`).
2. Créer et chiffrer les secrets :

```bash
cd ansible/group_vars/observability_servers
cp vault.yml.example vault.yml
vi vault.yml                 # vraies valeurs
ansible-vault encrypt vault.yml
```

Sans configuration de notification, les alertes restent visibles dans l'interface web (`http://<obs_collector>:9093`) mais ne sont pas envoyées.

## 5. Déploiement

```bash
cd ansible
ansible-playbook playbooks/site_observability.yml --check --diff --ask-vault-pass   # simulation
ansible-playbook playbooks/site_observability.yml --ask-vault-pass                  # application
ansible-playbook playbooks/site_observability.yml --ask-vault-pass                  # 2e passage : changed=0
```

(`--ask-vault-pass` n'est nécessaire que si `vault.yml` existe.)

## 6. Vérifications sur obs_collector

```bash
systemctl status alertmanager
curl -s http://localhost:9093/-/ready
amtool --alertmanager.url=http://localhost:9093 alert query        # Watchdog doit apparaître
curl -s http://localhost:9090/api/v1/alertmanagers                 # Prometheus voit Alertmanager
amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=critical
```

Test d'envoi manuel :

```bash
amtool --alertmanager.url=http://localhost:9093 alert add TestAlert severity=critical instance=test
```

## 7. Sécurité réseau

Alertmanager n'a pas d'authentification native. Dans le Security Group / firewall :

| Port | Source autorisée |
|---|---|
| 9093/tcp | Prometheus, Grafana, bastion d'administration |
| 9094/tcp+udp | Autres instances Alertmanager (uniquement en mode cluster) |
