# Clé SSH des nœuds

Dépose ici ta clé privée **`ops.pem`** (celle référencée par
`ansible/inventory.ini` via `keys/ops.pem`).

Tu la trouveras sous Windows dans `C:\Users\NehemieDiav\Downloads\ops.pem`.

```bash
# Depuis WSL, en étant dans ~/monitoringops/ansible
mkdir -p keys
cp /mnt/c/Users/NehemieDiav/Downloads/ops.pem keys/ops.pem
chmod 400 keys/ops.pem
```

> ⚠️ Ce fichier est ignoré par Git (`.gitignore` → `*.pem`) : **ne le commit jamais.**
> Le `chmod 400` est obligatoire, sinon SSH refuse la clé (« permissions trop ouvertes »).
> Ne le fais **pas** dans `/mnt/c` (le `chmod` y est sans effet) — travaille dans `~/`.

