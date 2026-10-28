# monitoringops — multi-environment Ansible + Helm monitoring stack

Ce dépôt automatiser le déploiement d'une stack de monitoring (Prometheus, Alertmanager, Loki, Grafana Alloy, Node Exporter)
sur deux environnements **dev** et **prod**, avec une seule source de vérité pour les playbooks.

## Structure

- `inventories/dev/` — inventaire + variables DEV (IP, ports, endpoints, versions).
- `inventories/prod/` — inventaire + variables PROD (avec placeholders à remplir).
- `ansible/playbooks/` — playbooks communs (un seul playbook par composant).
- `ansible/playbooks/roles/` — rôles Ansible (Alertmanager, Prometheus, Loki, Node Exporter, Alloy).
- `helm/alloy/` — chart Helm pour Alloy, avec `values-dev.yaml` et `values-prod.yaml`.
- `helm/loki/` — chart Helm pour Loki, avec `values-dev.yaml` et `values-prod.yaml`.
- `docs/` — documentation.

## Architecture

Deux méthodes de déploiement sont utilisées selon le type de serveur :

- **Serveurs Docker/Linux** : déploiement via Ansible (rôles `loki`, `alloy`, `prometheus`, `alertmanager`, `node_exporter`).
- **Serveurs Kubernetes** : déploiement via Helm (charts `grafana/loki`, `grafana/alloy`).

## Utilisation

### Choisir un environnement

```bash
# --- DEV ---

# 1. Loki sur serveurs Docker/Linux (obs_dashboard)
ansible-playbook -i inventories/dev ansible/playbooks/site_loki.yml

# 2. Loki sur Kubernetes (si nécessaire)
ansible-playbook -i inventories/dev ansible/playbooks/site_loki_k8s.yml

# 3. Prometheus + Alertmanager (obs_collector)
ansible-playbook -i inventories/dev ansible/playbooks/site_observability.yml

# 4. Node Exporter sur K8s
ansible-playbook -i inventories/dev ansible/playbooks/site.yml

# 5. Alloy sur Kubernetes (Helm)
ansible-playbook -i inventories/dev ansible/playbooks/site_alloy.yml

# 6. Alloy sur serveurs Docker/Linux (Ansible)
ansible-playbook -i inventories/dev ansible/playbooks/site_alloy_docker.yml

# --- PROD ---

# Mêmes commandes avec l'inventaire prod
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml
ansible-playbook -i inventories/prod ansible/playbooks/site_loki_k8s.yml
ansible-playbook -i inventories/prod ansible/playbooks/site_observability.yml
ansible-playbook -i inventories/prod ansible/playbooks/site.yml
ansible-playbook -i inventories/prod ansible/playbooks/site_alloy.yml
ansible-playbook -i inventories/prod ansible/playbooks/site_alloy_docker.yml
```

### Ordre de déploiement recommandé

1. **Loki** (doit être prêt avant Alloy et Prometheus)
2. **Prometheus + Alertmanager**
3. **Node Exporter**
4. **Alloy** (nécessite Loki opérationnel)

### Secrets (Vault)

Les secrets (mot de passe SMTP, webhook Teams) sont chiffrés avec `ansible-vault` :
1. Copier `inventories/<env>/group_vars/vault.yml.example` vers `vault.yml`.
2. Remplir les valeurs réelles.
3. Chiffrer : `ansible-vault encrypt inventories/<env>/group_vars/vault.yml`.
4. Lancer avec `--ask-vault-pass` ou `--vault-password-file`.

### Variables par environnement

Toutes les variables (IP, ports, namespaces, versions, stockage) sont définies dans :
- `inventories/<env>/group_vars/observability.yml`
- `inventories/<env>/hosts.yml`

Les fichiers Helm values sont séparés par environnement :
- `helm/alloy/values-dev.yaml` / `values-prod.yaml`
- `helm/loki/values-dev.yaml` / `values-prod.yaml`

## Documentation

- **[Connexion CyberArk et déploiement en production](docs/cyberark_connection.md)** — Configuration pour l'environnement Vodacom avec CyberArk PAM.
- **[Alertmanager](docs/alertmanager.md)** — Rôle Ansible, configuration, notifications.
- **[Notifications Alertmanager](docs/alertmanager_notifications.md)** — Procédure de test et intégration Outlook/Teams.
- **[Installation Ansible](docs/ansible_installation.md)** — Configuration du bastion et prérequis.

## Principes

- **Un seul code, plusieurs environnements** : les playbooks et rôles sont communs.
- **Variables par environnement** : IP, ports, namespaces, versions sont dans `inventories/<env>/group_vars/`.
- **Secrets chiffrés** : jamais en clair dans Git.
- **Helm values par environnement** : `values-dev.yaml` / `values-prod.yaml` pour chaque chart.
- **Deux méthodes complémentaires** : Ansible pour serveurs Docker/Linux, Helm pour Kubernetes.