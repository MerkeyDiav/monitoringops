# Alertmanager – Notifications (Outlook / Teams)

> Statut actuel : **notifications désactivées (option A – test sans notification externe).**
> Le bloc « NOTIFICATIONS » de `ansible/group_vars/observability_servers/vars.yml` est commenté.

## 1. Pourquoi il faut un canal de notification

Alertmanager **reçoit, regroupe, déduplique et route** les alertes envoyées par Prometheus.
Il ne prévient personne tout seul : il faut lui donner au moins un canal de sortie
(e-mail, Teams, webhook...). Sans canal, les alertes sont visibles uniquement dans :

- l'interface web : `http://<obs_collector>:9093`
- la ligne de commande : `amtool alert query`
- Prometheus : `http://<obs_collector>:9090/alerts`

## 2. Option A – Tester la chaîne sans notification (à faire maintenant)

Objectif : prouver que **Prometheus → Alertmanager → routage** fonctionne avant de
demander une intégration Outlook/Teams.

### 2.1 Déployer

```bash
cd ansible
ansible-playbook playbooks/site_observability.yml
```

### 2.2 Vérifier que Prometheus voit Alertmanager

```bash
curl -s http://localhost:9090/api/v1/alertmanagers
# attendu : "activeAlertManagers": [{"url": "http://localhost:9093/api/v2/alerts"}]
```

### 2.3 Vérifier l'alerte Watchdog (toujours active)

```bash
amtool --alertmanager.url=http://localhost:9093 alert query
# Alertname  Starts At  Summary                                         State
# Watchdog   ...        Alerte de contrôle de la chaîne d'alerting ...  active
```

Si `Watchdog` est présente : Prometheus évalue les règles **et** les transmet à Alertmanager.

### 2.4 Déclencher une alerte de test manuelle

```bash
amtool --alertmanager.url=http://localhost:9093 alert add TestAlert \
  severity=critical instance=test-vm \
  --annotation=summary="Alerte de test, ignorer"
```

Vérifier dans l'UI (port 9093) qu'elle apparaît, routée vers `critical`.

### 2.5 Vérifier le routage sans rien envoyer

```bash
CFG=/etc/alertmanager/alertmanager.yml
amtool config routes --config.file=$CFG
amtool config routes test --config.file=$CFG alertname=Watchdog severity=none            # -> null
amtool config routes test --config.file=$CFG alertname=InstanceDown severity=critical    # -> critical
amtool config routes test --config.file=$CFG alertname=HostHighCpuUsage severity=warning # -> default
```

### 2.6 Tester une vraie alerte (InstanceDown)

Sur une VM `k8s_nodes` de test :

```bash
sudo systemctl stop node_exporter
```

| Délai | Où regarder | État attendu |
|---|---|---|
| ~15–30 s | Prometheus `/alerts` | `InstanceDown` **Pending** |
| ~2 min | Prometheus `/alerts` | `InstanceDown` **Firing** |
| ~2 min 30 s | Alertmanager UI 9093 | Alerte présente, receiver `critical` |

Puis rétablir :

```bash
sudo systemctl start node_exporter
```

L'alerte passe à « resolved » et disparaît d'Alertmanager.

### 2.7 Critères de validation de l'option A

- [ ] `activeAlertManagers` contient `localhost:9093`
- [ ] `Watchdog` visible dans Alertmanager
- [ ] `TestAlert` visible et routée vers `critical`
- [ ] `InstanceDown` passe Pending → Firing → Resolved
- [ ] Aucun e-mail / message Teams envoyé (comportement attendu)

---

## 3. Options d'intégration chez Vodacom (Microsoft 365 : Outlook + Teams)

Alertmanager envoie les e-mails en **SMTP** : il ne parle pas l'API Microsoft Graph et
ne gère pas l'authentification OAuth2 pour SMTP. La méthode dépend donc de ce que
l'équipe Messagerie / Microsoft 365 autorise.

### 3.1 Comparatif

| # | Méthode | Ce qu'il faut côté Vodacom | Avantages | Points d'attention |
|---|---|---|---|---|
| **E1** | **Relais SMTP interne** (Exchange on-prem, passerelle mail d'entreprise) | Nom/IP du relais, port, autorisation de l'IP de `obs_collector` | Le plus simple, pas de mot de passe | Le relais est-il joignable depuis AWS ? |
| **E2** | **Connecteur SMTP Microsoft 365** (SMTP relay + inbound connector) | Connecteur entrant M365 lié à l'IP publique fixe (Elastic IP) de `obs_collector`, port 25 sortant ouvert, SPF à jour | Pas de mot de passe | Nécessite une **IP publique statique** ; AWS bloque le port 25 sortant par défaut |
| **E3** | **Direct Send** vers `<domaine>.mail.protection.outlook.com:25` | Éventuellement une règle d'autorisation ; SPF recommandé | Rien à créer | Destinataires **internes uniquement** ; risque de spam/quarantaine ; souvent bloqué par la sécurité |
| **E4** | **SMTP AUTH** sur `smtp.office365.com:587` avec une **boîte de service** | Boîte de service + mot de passe, SMTP AUTH activé sur cette boîte, exclusion MFA / Conditional Access | Configuration Alertmanager immédiate | Authentification « basique » en cours de **dépréciation par Microsoft**, souvent refusée par la sécurité. À éviter pour un usage durable |
| **E5** | **High Volume Email (HVE)** Microsoft 365 | Compte HVE créé par l'admin M365 | Prévu pour les applications | Destinataires internes ; à confirmer par l'équipe M365 |
| **T1** | **Microsoft Teams – Workflows** (Power Automate) | Droit de créer le Workflow « Send webhook alerts to a channel », sortie HTTPS 443 | Pas de SMTP, rapide, notifications mobiles | Les anciens « Incoming Webhooks » Office 365 sont **arrêtés** ; le Workflow appartient à un compte (prévoir un co-propriétaire) |

> **Recommandation** : demander **T1 (Teams Workflows)** pour la notification rapide, et
> **E1 ou E2 (relais / connecteur, sans mot de passe)** pour l'e-mail.
> Garder deux canaux : si Teams tombe, l'e-mail prévient (alerte
> `AlertmanagerNotificationsFailing` déjà présente dans les règles).

### 3.2 Pourquoi ne pas utiliser ton propre compte Outlook comme expéditeur

- ton mot de passe se retrouverait sur un serveur (même chiffré) ;
- la MFA de ton compte bloque l'authentification SMTP ;
- si tu changes de mot de passe ou quittes l'équipe, les alertes s'arrêtent ;
- c'est généralement interdit par la politique de sécurité.

👉 Ton adresse est le **destinataire** (`alertmanager_email_to`).
L'**expéditeur** doit être une boîte de service / adresse applicative
(ex. `monitoring-alerts@<domaine>`) validée par l'équipe Messagerie.

---


## 4. Questions à poser

### 4.1 À l'équipe Messagerie / Microsoft 365 (Exchange Online)

**Méthode d'envoi**
1. Quelle méthode est **approuvée** pour qu'une application serveur (Linux, hébergée sur AWS) envoie des e-mails d'alerte vers des boîtes Outlook internes : relais SMTP interne, connecteur SMTP M365, Direct Send, SMTP AUTH ou HVE ?
2. Existe-t-il déjà un **relais SMTP d'entreprise** utilisé par d'autres outils de supervision (Zabbix, Nagios, SolarWinds, Splunk...) ? Si oui : nom d'hôte, port, TLS et procédure pour y ajouter un nouveau serveur ?
3. **SMTP AUTH** (identifiant/mot de passe sur `smtp.office365.com:587`) est-il autorisé pour une boîte de service, ou bloqué par la politique de sécurité / Conditional Access ?
4. Si un **connecteur entrant** est nécessaire : quelles informations vous faut-il (IP publique, nom de domaine, certificat TLS) ?

**Expéditeur**
5. Pouvez-vous créer une **boîte de service / adresse applicative** dédiée (ex. `monitoring-alerts@<domaine>`) ? Faut-il une licence ?
6. Quelle **adresse « From »** dois-je utiliser ? Doit-elle appartenir à un domaine accepté particulier ?
7. Faut-il mettre à jour **SPF / DKIM** pour éviter que les alertes arrivent en spam ?

**Destinataires et limites**
8. Puis-je envoyer à **mon adresse** `prenom.nom@<domaine>` et à une **liste de distribution** d'équipe ? Faut-il créer une DL (ex. `platform-oncall@<domaine>`) ?
9. Les destinataires sont-ils **uniquement internes**, ou faut-il pouvoir envoyer à l'extérieur ?
10. Y a-t-il des **limites d'envoi** (messages/minute, destinataires/jour) ?
11. Comment **mettre l'expéditeur en liste blanche** pour qu'il ne soit pas filtré par l'anti-spam / la quarantaine ?

**Procédure**
12. Quelle est la **procédure de demande** (ticket ServiceNow, formulaire, CAB) et le **délai** habituel ?
13. Qui est le **contact technique** pour tester l'envoi ensemble (message trace en cas de non-réception) ?

### 4.2 À l'équipe Réseau / Sécurité / Cloud (AWS)

14. Le serveur `obs_collector` (AWS) peut-il joindre en sortie :
    - le relais SMTP interne (port 25 ou 587) ?
    - `smtp.office365.com:587` ou `<domaine>.mail.protection.outlook.com:25` ?
    - les URL Teams Workflows (`*.powerplatform.com:443`) ?
15. Le trafic sortant passe-t-il par un **proxy HTTP(S)** obligatoire ? (à configurer dans Alertmanager)
16. Faut-il une **Elastic IP** fixe pour `obs_collector` (requise pour un connecteur M365) ?
17. Le **port 25 sortant** est-il débloqué sur ce compte AWS (bloqué par défaut) ?
18. Où stocker les secrets : **Ansible Vault** est-il accepté, ou faut-il **CyberArk** / AWS Secrets Manager ?

### 4.3 À l'équipe Collaboration / Teams

19. Les **Workflows (Power Automate)** sont-ils autorisés dans Teams ? Puis-je créer le workflow « *Send webhook alerts to a channel* » ?
20. Faut-il une **licence Power Automate** ou un environnement Power Platform dédié ?
21. Pouvez-vous créer un **canal Teams** dédié (ex. `Platform – Alerts`), et éventuellement un second pour les alertes critiques ?
22. Le workflow peut-il appartenir à un **compte de service** plutôt qu'à mon compte, pour continuer de fonctionner si je change de poste ?
23. Une politique **DLP** bloque-t-elle les déclencheurs HTTP entrants dans Power Automate ?

### 4.4 À valider avec ton manager / l'équipe

24. Qui reçoit les alertes **warning** (e-mail seulement ?) et **critical** (Teams + e-mail ?) ?
25. Faut-il des **heures de silence** ou une astreinte (on-call) ?
26. Une intégration future avec un outil d'astreinte (PagerDuty, Opsgenie, ServiceNow) est-elle prévue ?

---

## 5. Activer un canal une fois l'accord obtenu

### 5.1 E-mail (exemple : relais SMTP sans authentification)

Dans `ansible/group_vars/observability_servers/vars.yml`, décommenter et adapter :

```yaml
alertmanager_smtp_smarthost: "smtp-relay.<domaine>:25"
alertmanager_smtp_from: "monitoring-alerts@<domaine>"
alertmanager_smtp_auth_username: ""
alertmanager_smtp_require_tls: true      # false si le relais ne supporte pas STARTTLS
alertmanager_email_to: "prenom.nom@<domaine>"
alertmanager_critical_email_to: "{{ alertmanager_email_to }}"
```

Avec SMTP AUTH (si autorisé) : renseigner `alertmanager_smtp_auth_username`, décommenter
`alertmanager_smtp_auth_password` et mettre le mot de passe dans `vault.yml` chiffré.

### 5.2 Teams (Workflows)

1. Dans le canal Teams : `⋯` → **Workflows** → *Send webhook alerts to a channel* → copier l'URL.
2. Tester l'URL sans Alertmanager :

   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' \
     -d '{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":"Test Alertmanager","wrap":true}]}}]}' \
     "$TEAMS_URL"
   # 202 = accepté, la carte doit apparaître dans le canal
   ```

3. Mettre l'URL dans `vault.yml` (`vault_alertmanager_msteams_webhook_url`), puis
   `ansible-vault encrypt vault.yml`.
4. Décommenter `alertmanager_msteams_webhook_url` dans `vars.yml`.

### 5.3 Déployer et tester

```bash
ansible-playbook playbooks/site_observability.yml --ask-vault-pass
amtool --alertmanager.url=http://localhost:9093 alert add NotifTest severity=critical instance=test \
  --annotation=summary="Test de notification, ignorer"
journalctl -u alertmanager -f      # erreurs d'envoi éventuelles
```

La notification arrive après `group_wait` (30 s). En cas d'échec, la métrique
`alertmanager_notifications_failed_total` augmente et l'alerte
`AlertmanagerNotificationsFailing` se déclenche.

