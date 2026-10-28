# Connexion CyberArk et déploiement en production

## 1. Contexte

Dans l'environnement de production Vodacom, l'accès aux serveurs se fait via CyberArk (PAM - Privileged Access Management).
Contrairement à l'environnement DEV où on utilise une clé SSH directe, en PROD :

- On n'utilise **pas** de clé SSH stockée localement
- On se connecte via la commande CyberArk : `ssh username@ip-de-la-vm-a-se-connecter@ip-de-cyberark`
- CyberArk demande alors le mot de passe de l'account
- Après authentification, on accède au serveur cible

## 2. Adaptation des inventaires Ansible

### Inventaire DEV (actuel)

```yaml
# inventories/dev/hosts.yml
all:
  children:
    observability_servers:
      hosts:
        obs_dashboard:
          ansible_host: 172.31.35.92
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /home/ec2-user/.ssh/ekey.pem
```

### Inventaire PROD (à configurer)

```yaml
# inventories/prod/hosts.yml
all:
  children:
    observability_servers:
      hosts:
        obs_dashboard:
          ansible_host: <IP_VIA_CYBERARK>
          ansible_user: <CYBERARK_USER>
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
          ansible_ssh_timeout: 30
          ansible_connection: ssh
```

## 3. Méthode recommandée pour CyberArk

### Option A : Utiliser le proxy CyberArk (recommandé)

CyberArk fournit un proxy SSH qui permet d'utiliser Ansible sans modifier la chaîne de connexion.
Configurez l'inventaire pour utiliser le proxy :

```yaml
# inventories/prod/hosts.yml
all:
  children:
    observability_servers:
      hosts:
        obs_dashboard:
          ansible_host: <IP_SERVEUR_CIBLE>
          ansible_user: <UTILISATEUR_CIBLE>
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p <CYBERARK_USER>@<IP_CYBERARK>"'
```

### Option B : Utiliser les variables d'environnement Ansible

Ansible supporte les variables d'environnement pour les connexions SSH :

```bash
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_ARGS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p <CYBERARK_USER>@<IP_CYBERARK>"'
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml
```

### Option C : Configuration via ansible.cfg

```ini
# inventories/prod/ansible.cfg (optionnel)
[defaults]
host_key_checking = False
ansible_ssh_common_args = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ssh_args = '-o ProxyCommand="ssh -W %h:%p <CYBERARK_USER>@<IP_CYBERARK>"'
```

## 4. Exemple de workflow complet

### Étape 1 : Se connecter au bastion via CyberArk

```bash
ssh <utilisateur_bastion>@<ip_bastion>@<ip_cyberark>
```

### Étape 2 : Activer l'environnement Ansible

```bash
source ~/ansible-venv/bin/activate
```

### Étape 3 : Récupérer le code

```bash
cd /path/to/monitoringops
git pull origin main
```

### Étape 4 : Lancer le déploiement

```bash
# Simulation (check mode)
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml --check --diff

# Application
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml

# Avec vault si nécessaire
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml --ask-vault-pass
```

## 5. Variables de connexion recommandées

Ajouter dans `inventories/prod/group_vars/observability.yml` :

```yaml
# --- Connexion ---
ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30'
ansible_ssh_timeout: 30
ansible_become: true
ansible_become_method: sudo
```

## 6. Sécurité

- **Ne jamais** stocker les mots de passe CyberArk dans Git
- **Ne jamais** stocker les clés SSH privées dans le dépôt
- Utiliser Ansible Vault pour les secrets (mot de passe, tokens)
- Les fichiers vault.yml doivent être chiffrés avec `ansible-vault encrypt`
- Les fichiers vault.yml en clair doivent être dans .gitignore

## 7. Déploiement progressif

Pour minimiser les risés en production :

1. D'abord déployer sur un serveur de test en production
2. Vérifier la connectivité avec `ansible -i inventories/prod obs_dashboard -m ping`
3. Lancer le playbook en mode `--check` pour simulation
4. Lancer le playbook en mode normal
5. Vérifier le service sur le serveur cible

## 8. Commandes de vérification

```bash
# Test de connectivité
ansible -i inventories/prod obs_dashboard -m ping

# Vérifier le service Loki
ansible -i inventories/prod obs_dashboard -b -m shell -a 'systemctl status loki --no-pager'

# Vérifier l'endpoint Loki
curl http://<IP_SERVEUR>:3100/ready
curl http://<IP_SERVEUR>:3100/loki/api/v1/label/__logs__/values
```