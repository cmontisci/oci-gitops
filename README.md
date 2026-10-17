# oci-gitops

Fonte di verità dei manifest Kubernetes per il lab OCI: un cluster **k3s** su una VM Ampere. Production e staging convivono sullo stesso nodo in namespace diversi. [Argo CD](https://argo-cd.readthedocs.io/) sincronizza questo repository con `prune` e `selfHeal`.

Il cluster (k3s, Traefik, Argo CD) **non** sta qui: lo installa [oci-infrastructure](https://github.com/cmontisci/oci-infrastructure). Vocabolario interno: [CONTEXT.md](CONTEXT.md).

## Struttura

```
argocd/           # unico path visto dalla Application root
platform/         # cert-manager, Alloy, Headlamp (tutti gli ambienti)
datastores/       # Postgres, Valkey (+ pgAdmin in production)
workloads/        # una cartella per app (overlay = presenza in quell'ambiente)
```

## Modello Argo CD (apps-of-apps)

Application root **`oci-gitops`** (creata una tantum sul cluster, path `argocd/`):

```
Application root oci-gitops
├── Application platform
├── Application datastores-production  → namespace apps
├── Application datastores-staging   → namespace apps-staging
├── ApplicationSet workloads-production
└── ApplicationSet workloads-staging
```

Aggiungi o rimuovi `workloads/<app>/overlays/<env>/`: l’ApplicationSet crea o fa il prune dell’Application corrispondente.

## Ambienti

| | Production | Staging |
|---|------------|---------|
| Namespace | `apps` | `apps-staging` |
| Overlay | `overlays/production/` | `overlays/staging/` |
| Nome Argo CD | `<app>` | `stg-<app>` |
| Datastore | Postgres + Valkey + pgAdmin | Postgres + Valkey |
| Tag immagine CI | push su `main` → `:latest` + `:sha` | push su `develop` → `:sha` (non `:latest`) |

Hostname pubblici (sen dominio dedicato): **nip.io** sull’IP pubblico della VM (`129.152.30.248` nel lab attuale). Esempi:

- pgAdmin: `https://pgadmin.129.152.30.248.nip.io`
- App future: `<app>.129.152.30.248.nip.io` / `staging-<app>.129.152.30.248.nip.io`

Ingress: Traefik (k3s). TLS: cert-manager + ClusterIssuer `letsencrypt-prod` (HTTP-01).

## Bootstrap Argo CD (una tantum)

Dopo `ansible-playbook playbooks/lab.yml` in oci-infrastructure:

1. **Repository** — In Argo CD (Settings → Repositories) aggiungi `git@github.com:cmontisci/oci-gitops.git` con deploy key SSH (read-only sul repo GitOps; la chiave privata resta nel cluster).

2. **Application root** — Crea un’Application:

   - Name: `oci-gitops`
   - Project: `default`
   - Repo URL: `git@github.com:cmontisci/oci-gitops.git`
   - Revision: `main`
   - Path: `argocd`
   - Cluster: `https://kubernetes.default.svc`
   - Namespace: `argocd` (solo metadati dell’Application)
   - Sync: automated, prune, selfHeal

   Oppure applica l’equivalente con `kubectl` **solo per questa Application** (non per workload o datastore).

3. **Sync order** — La Application `platform` installa cert-manager; pgAdmin e altri Ingress TLS diventano utilizzabili quando il ClusterIssuer è Ready.

## Secret (non in Git)

Creati **una tantum** sul cluster con `kubectl create secret`. I pod datastore restano in errore finché i secret non esistono. **Postgres inizializza il PVC solo al primo avvio riuscito con volume vuoto**: crea i secret **prima** del primo sync dei datastore.

### Ordine consigliato

1. Secret datastore nel namespace target (`apps` / `apps-staging`)
2. Secret `grafana-cloud-loki` in `monitoring` (prima o insieme al sync di `platform`)
3. Secret `ghcr` in `apps` e `apps-staging` (prima dei workload)
4. Secret `<app>-config` per ogni workload

### Datastore — `apps` (production)

```bash
kubectl -n apps create secret generic postgresql \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD='…' \
  --from-literal=POSTGRES_DB=postgres

kubectl -n apps create secret generic valkey \
  --from-literal=valkey.conf='requirepass …
appendonly yes'

kubectl -n apps create secret generic pgadmin \
  --from-literal=PGADMIN_DEFAULT_EMAIL='…@…' \
  --from-literal=PGADMIN_DEFAULT_PASSWORD='…'
```

### Datastore — `apps-staging`

Stesse chiavi di Postgres e Valkey (password **diverse** da production):

```bash
kubectl -n apps-staging create secret generic postgresql \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD='…' \
  --from-literal=POSTGRES_DB=postgres

kubectl -n apps-staging create secret generic valkey \
  --from-literal=valkey.conf='requirepass …
appendonly yes'
```

### Monitoring — Grafana Cloud Loki

```bash
kubectl -n monitoring create secret generic grafana-cloud-loki \
  --from-literal=LOKI_URL='https://…' \
  --from-literal=LOKI_USERNAME='…' \
  --from-literal=LOKI_PASSWORD='…'
```

### Workload — pull GHCR

```bash
kubectl -n apps create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username=… \
  --docker-password=…

kubectl -n apps-staging create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username=… \
  --docker-password=…
```

I manifest workload devono referenziare `imagePullSecrets: [{ name: ghcr }]`.

## Connessioni datastore

| Servizio | Stesso namespace | Da altro namespace |
|----------|------------------|---------------------|
| Postgres | `postgresql:5432` | `postgresql.apps.svc.cluster.local:5432` |
| Valkey | `valkey:6379` | `valkey.apps.svc.cluster.local:6379` |

Staging: sostituisci `apps` con `apps-staging`.

DSN Postgres esempio (production): `postgresql://USER:PASS@postgresql.apps.svc.cluster.local:5432/DBNAME`

pgAdmin (Ingress TLS) espone due server preconfigurati: Postgres locale in `apps` e `postgresql.apps-staging.svc.cluster.local`. Le password vanno salvate in pgAdmin al primo login (non sono nel ConfigMap).

## Nuovo workload

1. Crea `workloads/<app>/overlays/staging/` (staging-first).
2. DNS nip.io: record **A** verso l’IP pubblico della VM (o usa `<app>.<IP>.nip.io` se il resolver nip.io basta).
3. Secret `<app>-config` in `apps-staging` e `ghcr` se manca.
4. Nel repo app: CI con job `update-gitops-staging` su `develop` (secret `GITOPS_PAT` con write su questo repo).
5. Quando è stabile, aggiungi `overlays/production/`; CI su `main` con `update-gitops`.

Convenzione Kustomize:

```
workloads/<app>/
  base/                 # opzionale
  overlays/staging/
  overlays/production/
```

**Non** fare `kubectl apply` di Deployment/Ingress: Argo CD li sovrascrive.

## Upgrade PVC (`local-path`)

La StorageClass `local-path` di k3s **non espande** i PVC in place. Per aumentare lo spazio:

1. Scala a 0 lo StatefulSet (o ferma il pod).
2. Crea un nuovo PVC con la dimensione desiderata.
3. Copia i dati (es. job temporaneo o `kubectl cp` / tool del DB).
4. Aggiorna il manifest con la nuova dimensione (nuovo claim o sostituzione documentata).
5. Riavvia e verifica.

Pianifica il cutover: Postgres non reinizializza se il volume non è vuoto.

## Accesso UI (senza Ingress)

**Argo CD** — dopo bootstrap: `http://argocd.<IP>.nip.io` (HTTP) oppure port-forward.

**Headlamp**:

```bash
kubectl -n headlamp port-forward svc/headlamp 8080:80
kubectl -n headlamp create token headlamp
```

Apri `http://localhost:8080` e incolla il token.

## Deploy immagini

1. CI del repo app pubblica su GHCR (`ghcr.io/cmontisci/...`).
2. Job GitOps committa il nuovo tag in questo repo (`update-gitops` su `main`, `update-gitops-staging` su `develop`).
3. Argo CD sincronizza su commit su `main`.

## Validazione locale

```bash
kubectl kustomize argocd
kubectl kustomize platform
kubectl kustomize datastores/overlays/production
kubectl kustomize datastores/overlays/staging
```

`platform` scarica il manifest upstream di cert-manager: serve rete.

## Cosa non sta in Git

- Secret elencati sopra
- Deploy key SSH di Argo CD verso questo repo
- Application root `oci-gitops` (definita sul cluster)
- kubeconfig e stato Terraform (repo oci-infrastructure)
