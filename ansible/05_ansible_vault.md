# 🔐 Vault — Secrets Management

Encrypt sensitive data — passwords, API keys, certificates — so they're safe to store in Git.

---

## 📚 Table of Contents

- [1. What is Ansible Vault?](#1-what-is-ansible-vault)
- [2. Encrypting Files](#2-encrypting-files)
- [3. Encrypting Single Values](#3-encrypting-single-values)
- [4. Using Vault in Playbooks](#4-using-vault-in-playbooks)
- [5. Multiple Vault Passwords](#5-multiple-vault-passwords)
- [6. Vault Password Files & CI/CD](#6-vault-password-files--cicd)
- [7. Best Practices](#7-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. What is Ansible Vault?

Ansible Vault encrypts sensitive data using AES-256. Encrypted files look like:

```
$ANSIBLE_VAULT;1.1;AES256
38623534353830393665306261363039336239343034363139306130353639316265
37326164626538633361376431386632303839383633343065633866386565353839
...
```

You can safely commit this to Git — without the vault password, it's unreadable.

---

## 2. Encrypting Files

```bash
# Encrypt a new file
ansible-vault create secrets.yml

# Encrypt an existing file
ansible-vault encrypt group_vars/all/vault.yml

# View encrypted file (decrypts to stdout)
ansible-vault view group_vars/all/vault.yml

# Edit encrypted file (opens in $EDITOR)
ansible-vault edit group_vars/all/vault.yml

# Decrypt a file (converts back to plaintext — careful!)
ansible-vault decrypt group_vars/all/vault.yml

# Re-encrypt with new password
ansible-vault rekey secrets.yml

# Encrypt multiple files at once
ansible-vault encrypt vars/db.yml vars/api.yml vars/ssl.yml
```

---

## 3. Encrypting Single Values

Instead of encrypting entire files, encrypt just the sensitive value inline:

```bash
# Encrypt a single string value
ansible-vault encrypt_string 'MySecretPassword123' --name 'db_password'

# Output:
# db_password: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   38623534353830393665...
```

Use that output directly in your vars file:

```yaml
# group_vars/all/vars.yml
db_host: db.example.com
db_port: 5432
db_name: myapp

# Only the password is encrypted — everything else is readable
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38623534353830393665306261363039336239343034363139306130353639316265
  37326164626538633361376431386632303839383633343065633866386565353839

api_key: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  61636163633934353234313637656339...

ssl_key: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  66363639363834376466653534326562...
```

This is the **recommended approach** — keep variable names readable, only encrypt values.

---

## 4. Using Vault in Playbooks

### Provide vault password at runtime

```bash
# Prompt for password interactively
ansible-playbook site.yml --ask-vault-pass

# Use a password file
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Use an environment variable for the password file
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
ansible-playbook site.yml
```

### In ansible.cfg

```ini
[defaults]
vault_password_file = ~/.vault_pass
```

### Using vault variables in tasks

Once the vault password is provided, vault variables work exactly like normal variables:

```yaml
- name: Configure database
  ansible.builtin.template:
    src: database.conf.j2
    dest: /etc/myapp/database.conf
  vars:
    # These come from vault — Ansible decrypts automatically
    password: "{{ db_password }}"
    api: "{{ api_key }}"

- name: Create database user
  community.postgresql.postgresql_user:
    name: myapp
    password: "{{ db_password }}"   # vault variable, used transparently
    state: present
```

---

## 5. Multiple Vault Passwords

Use multiple vault IDs to manage different secrets with different passwords (e.g. per environment):

```bash
# Encrypt with a specific vault ID
ansible-vault encrypt_string 'ProdPassword' \
  --name 'db_password' \
  --vault-id production@prompt

ansible-vault encrypt_string 'StagingPassword' \
  --name 'db_password' \
  --vault-id staging@prompt

# Run playbook with multiple vault passwords
ansible-playbook site.yml \
  --vault-id production@~/.vault_pass_prod \
  --vault-id staging@~/.vault_pass_staging
```

```yaml
# Encrypted value shows its vault ID
db_password: !vault |
  $ANSIBLE_VAULT;1.2;AES256;production
  38623534353830393665...
```

---

## 6. Vault Password Files & CI/CD

### Password file (simplest)

```bash
# Create password file
echo "MyVaultPassword" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Add to .gitignore — NEVER commit this
echo ".vault_pass" >> .gitignore
```

### CI/CD integration (GitHub Actions example)

```yaml
# .github/workflows/deploy.yml
- name: Create vault password file
  run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > .vault_pass

- name: Run playbook
  run: ansible-playbook -i inventory/ site.yml --vault-password-file .vault_pass

- name: Remove vault password file
  run: rm -f .vault_pass
  if: always()
```

### Using a script as vault password source

```bash
# vault_pass.py — fetches password from AWS Secrets Manager
#!/usr/bin/env python3
import boto3
client = boto3.client('secretsmanager', region_name='eu-central-1')
secret = client.get_secret_value(SecretId='ansible/vault-password')
print(secret['SecretString'])
```

```bash
chmod +x vault_pass.py
ansible-playbook site.yml --vault-password-file ./vault_pass.py
```

---

## 7. Best Practices

```
✅ DO:
  - Encrypt with encrypt_string for individual values
  - Keep vault.yml separate from vars.yml
  - Use vault IDs for multiple environments
  - Store vault password in CI secrets (GitHub/GitLab secrets)
  - Add .vault_pass* to .gitignore
  - Use a password manager or secrets manager for the vault password

❌ DON'T:
  - Commit plaintext secrets to Git (ever)
  - Commit .vault_pass files to Git
  - Use the same vault password for all environments
  - Decrypt files just to read them (use ansible-vault view)
  - Store vault password in ansible.cfg in the repo
```

### Recommended vault file layout

```
group_vars/
├── all/
│   ├── vars.yml      # non-sensitive — commit freely
│   └── vault.yml     # encrypted — safe to commit
├── production/
│   ├── vars.yml
│   └── vault.yml     # different vault password than staging
└── staging/
    ├── vars.yml
    └── vault.yml
```

```yaml
# group_vars/all/vars.yml
db_host: db.example.com
db_port: 5432
db_name: myapp
db_user: myapp
# Reference vault variable by convention: vault_ prefix
db_password: "{{ vault_db_password }}"
api_key: "{{ vault_api_key }}"

# group_vars/all/vault.yml (encrypted)
vault_db_password: SuperSecret123
vault_api_key: sk-abc123xyz
```

Using the `vault_` prefix naming convention makes it immediately clear which variables come from vault.

---

## Cheatsheet

```bash
# Create / encrypt
ansible-vault create secrets.yml
ansible-vault encrypt existing.yml
ansible-vault encrypt_string 'value' --name 'var_name'

# View / edit
ansible-vault view secrets.yml
ansible-vault edit secrets.yml

# Decrypt (careful!)
ansible-vault decrypt secrets.yml

# Rekey (change password)
ansible-vault rekey secrets.yml

# Run playbook with vault
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Multiple vault IDs
ansible-playbook site.yml \
  --vault-id prod@~/.vault_pass_prod \
  --vault-id staging@~/.vault_pass_staging
```

---

*Next: [Jinja2 Templating →](./06-ansible-jinja2.md)*
