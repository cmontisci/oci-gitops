# Setup guidato (lab OCI)

Ordine consigliato. Il repo è già su GitHub (`main`); la VM risponde su **80/443** (Argo CD UI), ma **kubectl** richiede SSH sulla VM (porta **6443** non esposta).

## 0. Sbloccare SSH (se non ci entri)

Il NSG OCI permette SSH solo da `allowed_ssh_cidr` in `oci-infrastructure/infra/terraform/terraform.tfvars`.

1. Il tuo IPv4 pubblico (da casa): apri [https://ifconfig.me](https://ifconfig.me) o `curl -4 ifconfig.me`.
2. Imposta `allowed_ssh_cidr = "TUO_IP/32"` e `terraform apply` nella cartella terraform.
3. Prova: `ssh -i ~/.ssh/id_ed25519 ubuntu@129.152.30.248`

Senza SSH non puoi creare i secret né leggere la password iniziale di Argo CD (serve `kubectl` sulla VM).

## 1. Argo CD — login

URL: [http://argocd.129.152.30.248.nip.io](http://argocd.129.152.30.248.nip.io)

Password iniziale `admin` (solo se non l’hai già cambiata), dalla VM:

```bash
sudo kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

(`KUBECONFIG` di default sulla VM è `/etc/rancher/k3s/k3s.yaml`.)

## 2–3. Repo GitOps + Application root (script)

Dopo **ansible-playbook** (Argo CD installato). Se hai **ricreato la VM**, Argo CD è vuoto: va rifatto il bootstrap; la **deploy key su GitHub** può restare quella già aggiunta (`~/.ssh/oci-gitops-argocd.pub`).

**Una tantum** — genera la coppia e aggiungi la `.pub` su GitHub (Deploy keys):

```bash
bash scripts/generate-argocd-deploy-key.sh
```

**Ogni reinstall di k3s/Argo CD** — dal PC (usa SSH verso la VM):

```bash
bash scripts/bootstrap-argocd-gitops.sh
bash scripts/setup-secrets-via-ssh.sh
```

Lo script crea il Secret `repo-oci-gitops` in `argocd` e applica `scripts/bootstrap-argocd-root.yaml` (Application `oci-gitops`).

**Manuale (UI):** Settings → Repositories + New App `oci-gitops` path `argocd` — equivalente allo script.

Sync: figli `platform`, `datastores-*`, ApplicationSet workload (vuoti finché non ci sono overlay).

## 4. Secret **prima** dei datastore

Sulla VM (o con kubeconfig che funziona):

```bash
cd oci-gitops   # clone del repo
cp scripts/setup-secrets.example.env scripts/setup-secrets.env
# compila le password (prod ≠ staging)
bash scripts/setup-secrets.sh
```

Poi in Argo CD: **Refresh + Sync** su `datastores-production` e `datastores-staging`.

## 5. Platform e certificati

Sync `platform` (figlio di `oci-gitops`). Attendi pod `cert-manager` Ready e ClusterIssuer `letsencrypt-prod`.

Poi pgAdmin: [https://pgadmin.129.152.30.248.nip.io](https://pgadmin.129.152.30.248.nip.io) (certificato dopo qualche minuto).

## 6. Alloy / Loki (opzionale)

Se non compili `LOKI_*` in `setup-secrets.env`, il DaemonSet Alloy in `monitoring` non parte finché non crei `grafana-cloud-loki`. Puoi ignorarlo all’inizio.

## 7. Checklist rapida

- [ ] SSH sulla VM
- [ ] Repo GitOps **Successful** in Argo CD
- [ ] Application `oci-gitops` synced
- [ ] Secret in `apps` e `apps-staging`
- [ ] Pod Postgres/Valkey Running
- [ ] cert-manager Ready, pgAdmin con TLS

Problemi comuni: secret creati **dopo** il primo avvio Postgres su PVC già inizializzato con credenziali sbagliate → serve reset PVC (lab) o allineare password al volume esistente.
