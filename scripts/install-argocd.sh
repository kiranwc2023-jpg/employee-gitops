#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# install-argocd.sh — Argo CD Installation and Configuration Script
#
# Run this script ONCE on a fresh Kubernetes cluster to install Argo CD.
# After running, point your browser to the Argo CD UI and configure
# the employee-service Application using argocd/application.yaml.
#
# Prerequisites:
#   - kubectl configured and connected to your cluster
#   - Cluster admin permissions
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

ARGOCD_VERSION="v2.10.0"
ARGOCD_NAMESPACE="argocd"

echo "============================================"
echo "  Installing Argo CD ${ARGOCD_VERSION}"
echo "============================================"

# ───────────────────────────────────────────────────────────────────────
# STEP 1: Create Argo CD namespace
# ───────────────────────────────────────────────────────────────────────
echo "Creating namespace: ${ARGOCD_NAMESPACE}"

# kubectl create namespace: creates the 'argocd' namespace.
# --dry-run=client -o yaml | kubectl apply -f - is the IDEMPOTENT pattern:
#   - If namespace exists: apply is a no-op (not an error like 'create' would be)
#   - If namespace doesn't exist: it is created
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ───────────────────────────────────────────────────────────────────────
# STEP 2: Install Argo CD from the official manifest
# ───────────────────────────────────────────────────────────────────────
echo "Installing Argo CD from official manifest..."

# kubectl apply -f <URL>: downloads the YAML from the URL and applies it to the cluster.
# This installs all Argo CD components:
#   - argocd-server: the API server and web UI
#   - argocd-repo-server: clones git repos and renders manifests
#   - argocd-application-controller: reconciles desired vs current state
#   - argocd-dex-server: authentication (OIDC/LDAP/GitHub)
#   - argocd-redis: caching layer for performance
#   - argocd-applicationset-controller: manages sets of Applications
# All are Deployments + Services inside the 'argocd' namespace.
kubectl apply -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# ───────────────────────────────────────────────────────────────────────
# STEP 3: Wait for Argo CD to be ready
# ───────────────────────────────────────────────────────────────────────
echo "Waiting for Argo CD deployment to be ready..."

# kubectl rollout status: waits until the Deployment's pods are all running.
# --timeout=300s: give up after 5 minutes (cluster might be slow).
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=300s

echo "Argo CD is running."

# ───────────────────────────────────────────────────────────────────────
# STEP 4: Get initial admin password
# ───────────────────────────────────────────────────────────────────────
echo ""
echo "Retrieving initial admin password..."

# Argo CD stores the initial admin password in a Kubernetes Secret.
# The password is the admin pod's name (or a bcrypt hash, depending on version).
# kubectl get secret: retrieves the Secret object.
# -o jsonpath: extracts a specific field using JSONPath syntax.
# base64 --decode: the secret value is base64-encoded; decode to plaintext.
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

echo ""
echo "============================================"
echo "  Argo CD Installation Complete"
echo "============================================"
echo ""
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo ""
echo "SECURITY: Change this password immediately after first login!"
echo ""

# ───────────────────────────────────────────────────────────────────────
# STEP 5: Expose Argo CD UI (development only)
# ───────────────────────────────────────────────────────────────────────
echo "Starting port-forward for local access..."
echo "Access Argo CD UI at: https://localhost:8080"
echo "(Press Ctrl+C to stop port-forwarding)"
echo ""

# kubectl port-forward: creates a tunnel from your local machine to the Kubernetes Service.
# localhost:8080 → argocd-server Service:443 (inside the cluster).
# This is for LOCAL DEVELOPMENT ONLY.
# In production: expose via Ingress (Nginx/Traefik) with TLS from cert-manager.
kubectl port-forward svc/argocd-server -n "${ARGOCD_NAMESPACE}" 8080:443

# ───────────────────────────────────────────────────────────────────────
# STEP 6: Register the employee-gitops repository with Argo CD
# (Run these commands in a separate terminal while port-forward is running)
# ───────────────────────────────────────────────────────────────────────
# argocd login localhost:8080 --username admin --password "${ARGOCD_PASSWORD}" --insecure
#
# argocd repo add https://github.com/mycompany/employee-gitops \
#   --username mycompany \
#   --password "${GITOPS_PAT}"
#
# kubectl apply -f argocd/application.yaml
