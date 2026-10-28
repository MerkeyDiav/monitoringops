# Connexion CyberArk et déploiement en production

## 1. Contexte

Dans l'environnement de production Vodacom, l'accès aux serveurs se fait via **CyberArk** (PAM - Privileged Access Management).
Contrairement à l'environnement DEV où on utilise une clé SSH directe, en PROD :

- On n'utilise **pas** de clé SSH stockée localement
- On se connecte via la commande CyberArk : `ssh <utilisateur>@<IP-serveur-cible>@<IP-CyberArk>`
- CyberArk demande le mot de passe de l'account (interaction humaine requise)
- Après authentification, on accède au serveur cible

## 2. Problème : CyberArk et Ansible ne sont pas compatibles directement

CyberArk exige une saisie manuelle du mot de passe à chaque connexion.
Ansible ne peut pas gérer cette interaction (pas de prompt interactif dans les playbooks).

**Solution :** Utiliser le proxy SSH de CyberArk en mode "connection through bastion" ou configurer un accès "Passwordless" via CyberArk (recommandé par la sécurité).

## 3. Méthode recommandée pour CyberArk

### Option A : Proxy SSH CyberArk (mode non-interactif) ⭐

CyberArk supporte le mode `ProxyCommand` via SSH. Si le compte est configuré pour l'accès automatique (sans saisie manuelle du mot de passe), on peut utiliser :

```yaml
# inventories/prod/hosts.yml
all:
  children:
    observability_servers:
      hosts:
        obs_dashboard:
          ansible_host: <IP_SERVEUR_CIBLE>
          ansible_user: <UTILISATEUR_CIBLE>
          ansible_ssh_common_args: >-
            -o StrictHostKeyChecking=no
            -o UserKnownHostsFile=/dev/null
            -o ConnectTimeout=30
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p <CYBERARK_USER>@<IP_CYBERARK>"
```

**Prérequis :** Le compte `<CYBERARK_USER>` doit avoir un accès automatisé (clé SSH ou mot de passe stocké de manière sécurisée via CyberArk).

### Option B : Accès direct via CyberArk (avec interaction humaine)

Si l'automatisation n'est pas possible, le workflow est :

1. **Se connecter manuellement** au serveur via CyberArk :
   ```bash
   ssh <utilisateur_bastion>@<ip_bastion>@<ip_cyberark>
   ```
2. **Depuis le bastion**, exécuter Ansible :
   ```bash
   cd /path/to/monitoringops
   ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml
   ```
3. Les connexions SSH depuis le bastion utilisent la clé SSH ou le compte local (pas CyberArk).

### Option C : Configurer un compte de service CyberArk (recommandé pour l'automatisation)

Auprès de l'équipe sécurité, demander :
- Créer un compte de **service** dans CyberArk pour Ansible
- Configurer ce compte avec un accès **non-interactif** (clé SSH ou mot de passe automatique)
- Fournir l'IP du bastion/serveur d'exécution Ansible
- Ce compte sera utilisé uniquement pour les déploiements automatisés

## 4. Inventaire PROD-Type (à adapter selon la politique sécurité)

```yaml
# inventories/prod/hosts.yml
all:
  children:
    observability_servers:
      hosts:
        obs_dashboard:
          ansible_host: <IP_SERVEUR_CIBLE>
          ansible_user: <UTILISATEUR_CIBLE>
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30'
          ansible_ssh_timeout: 30
          ansible_connection: ssh
```

## 5. Workflow de déploiement en production

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

### Étape 4 : Simulation (check mode)
```bash
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml --check --diff
```

### Étape 5 : Application
```bash
ansible-playbook -i inventories/prod ansible/playbooks/site_loki.yml
```

## 6. Sécurité

- **Ne jamais** stocker les mots de passe CyberArk dans Git
- **Ne jamais** stocker les clés SSH privées dans le dépôt
- Utiliser Ansible Vault pour les secrets (mot de passe, tokens)
- Les fichiers vault.yml doivent être chiffrés avec `ansible-vault encrypt`
- Les fichiers vault.yml en clair doivent être dans `.gitignore`

## 7. Commandes de vérification

```bash
# Test de connectivité
ansible -i inventories/prod obs_dashboard -m ping

# Vérifier le service Loki
ansible -i inventories/prod obs_dashboard -b -m shell -a 'systemctl status loki --no-pager'

# Vérifier l'endpoint Loki
curl http://<IP_SERVEUR>:3100/ready
```