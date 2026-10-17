# OCI GitOps — vocabolario

Termini usati in questo repository e nel cluster k3s sulla VM Oracle. Le procedure operative sono in [README.md](README.md).

## Cluster

Un solo cluster Kubernetes (k3s) su una VM. Production e staging **non** sono cluster separati: convivono sullo stesso nodo in namespace diversi.

## Ambiente

Una delle due slice logiche del cluster:

| Ambiente   | Namespace Kubernetes | Overlay Kustomize      | Nome Application Argo CD (workload) |
|------------|----------------------|------------------------|-------------------------------------|
| Production | `apps`               | `overlays/production/` | `<app>`                             |
| Staging    | `apps-staging`       | `overlays/staging/`    | `stg-<app>`                         |

Un workload esiste in un ambiente **solo** se esiste la cartella overlay corrispondente.

## Application root

L’Application Argo CD `oci-gitops` (creata una tantum sul cluster, non in questo repo) che punta al path `argocd/` di questo repository. È la radice del modello apps-of-apps.

## Platform

Componenti condivisi da tutti gli ambienti, deployati dal path `platform/`: cert-manager, ClusterIssuer Let’s Encrypt, Grafana Alloy (log verso Loki), Headlamp (dashboard). Non è il path di deploy delle applicazioni business.

## Datastore

Servizi di persistenza interni al cluster (Postgres, Valkey; pgAdmin in production). Nessun Ingress sulle porte dati, tranne pgAdmin come unica UI pubblica dei database. Host corti nello stesso namespace (`postgresql`, `valkey`); da altri namespace si usano i FQDN (`postgresql.apps.svc.cluster.local`, ecc.).

## Workload

Un’applicazione business sotto `workloads/<app>/`, tipicamente con `base/` opzionale e overlay per ambiente. L’ApplicationSet crea o rimuove l’Application Argo CD quando aggiungi o togli un overlay.

## Overlay

Directory Kustomize `overlays/production/` o `overlays/staging/` che specializza base (o manifest locali) per un ambiente. È la leva con cui un’app entra o esce da un ambiente.

## GitOps

Questo repository è la fonte di verità dei manifest. Argo CD sincronizza con `prune` e `selfHeal`. Non si applicano Deployment o Ingress con `kubectl apply`: Argo CD li sovrascrive.

## Confine con Ansible

**Ansible** ([oci-infrastructure](https://github.com/cmontisci/oci-infrastructure)): k3s, Traefik, installazione Argo CD, bootstrap VM, firewall. **Questo repo**: platform, datastore, workload, Application e ApplicationSet sotto `argocd/`.
