# CLAUDE.md

This file provides guidance to Claude Code when working with this Sysdig Shield ArgoCD deployment repository.

<base-instructions>
    <rule id="1" name="No Hardcoding">Use configuration files or environment variables. Enums are allowed.</rule>
    <rule id="2" name="Fix Root Causes">No workarounds; address issues properly.</rule>
    <rule id="3" name="Remove Legacy Code">Delete old code when replacing it; no shims or compatibility layers.</rule>
    <rule id="4" name="Minimal Comments">Code must be self-explanatory; use comments only when necessary.</rule>
    <rule id="5" name="Avoid Circular Dependencies">Keep modules loosely coupled.</rule>
    <rule id="6" name="Use Logging">Always use logging facilities; no echo statements in scripts. Always write to the logs folder inside the project, and datestamp and timestamp them.</rule>
    <rule id="7" name="Mandatory Testing">Ensure comprehensive testing coverage, including edge cases. Use real API validation.</rule>
    <rule id="8" name="No Unused Resources">Remove any modules, configurations, or dependencies that are not in use.</rule>
    <rule id="9" name="Follow Documentation">Verify implementation against documentation.</rule>
    <rule id="10" name="Version Consistency">Always update the version when making significant changes. Ensure version consistency across all documentation.</rule>
</base-instructions>

## Repository Overview

This repository contains ArgoCD Application manifests and Helm values for deploying Sysdig Shield components using the official `sysdig/shield` Helm chart. ArgoCD Multi-Source Applications are used to combine the chart from `charts.sysdig.com` with values files from this repository.

## Project Structure

The repository follows GitOps principles with ArgoCD + Helm for continuous deployment:
- **argocd-apps/**: ArgoCD Application manifests (Helm Multi-Source)
- **helm-values/**: Helm values files for environment-specific configuration (base + dev/staging/production)
- **secrets/**: Secret management templates (External Secrets, Sealed Secrets, Vault Plugin)
- **test/**: Test manifests and validation scripts
- **docs/**: Operational documentation (Korean)

## Common Commands

### ArgoCD Commands
```bash
# Login to ArgoCD
argocd login <ARGOCD_SERVER>

# Create application from manifest
argocd app create -f argocd-apps/sysdig-shield-dev.yaml

# Sync application
argocd app sync sysdig-shield-dev

# Check application status
argocd app get sysdig-shield-dev

# Delete application
argocd app delete sysdig-shield
```

### Kubernetes Commands
```bash
# Check Sysdig Shield components
kubectl get pods -n sysdig-shield
kubectl get svc -n sysdig-shield

# View Sysdig agent logs
kubectl logs -f daemonset/sysdig-agent -n sysdig-shield

# Check Sysdig admission controller
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
```

### Sysdig-Specific Commands
```bash
# Verify Sysdig agent connectivity
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- sysdig-agent-check

# Check Sysdig agent configuration
kubectl get configmap sysdig-agent -n sysdig-shield -o yaml

# Test admission controller policies
kubectl apply -f test/sample-deployment.yaml --dry-run=server
```

## Architecture

### Sysdig Shield Components
- **Sysdig Agent**: DaemonSet for runtime security and monitoring
- **Admission Controller**: Webhook for policy enforcement at deployment time
- **Node Analyzer**: Image scanning and compliance checking
- **KSPM Collector**: Kubernetes Security Posture Management
- **Rapid Response**: Interactive troubleshooting and forensics

### ArgoCD Integration
- **Automated Sync**: GitOps-based deployment from this repository
- **Health Checks**: Custom health assessments for Sysdig components
- **Sync Waves**: Ordered deployment of dependencies
- **Pruning**: Automatic cleanup of removed resources

## Configuration Management

### Secrets Management
Never commit secrets to this repository. Use one of the following approaches:
- **Sealed Secrets**: Encrypt secrets with kubeseal
- **External Secrets Operator**: Sync from external secret stores (AWS Secrets Manager, Vault, etc.)
- **ArgoCD Vault Plugin**: Inject secrets at deployment time

Required secrets:
- `sysdig-agent-access-key`: Sysdig backend access key
- `sysdig-admission-controller-secret`: TLS certificates for webhook

### Environment-Specific Configuration
Use Helm values files for environment-specific configurations:
```
helm-values/
├── base-values.yaml          # Common settings for all environments
├── dev-values.yaml            # Dev overrides (dryRun, reduced features)
├── staging-values.yaml        # Staging overrides (full features, Ignore policy)
└── production-values.yaml     # Production overrides (Fail policy, ML policies)
```

## Security Considerations

### RBAC Requirements
Sysdig Shield requires cluster-level permissions:
- Read access to all pods, nodes, namespaces
- Webhook configuration management
- Security policy enforcement

### Network Policies
Configure network policies to:
- Allow Sysdig agents to communicate with Sysdig backend
- Restrict admission controller webhook traffic
- Isolate node analyzer scanning

### Compliance
- Ensure all manifests follow organizational security standards
- Use resource limits and security contexts
- Enable admission controller policies before production deployment

## Testing

### Pre-Deployment Validation
```bash
# Validate ArgoCD application manifests
argocd app create -f argocd-apps/sysdig-shield.yaml --validate

# Validate Helm values
helm template sysdig-shield sysdig/shield \
  --version 1.28.0 \
  -f helm-values/base-values.yaml \
  -f helm-values/dev-values.yaml \
  --debug
```

### Post-Deployment Verification
```bash
# Check all Sysdig pods are running
kubectl wait --for=condition=ready pod -l app=sysdig-agent -n sysdig-shield --timeout=300s

# Verify admission controller webhook
kubectl run test-pod --image=nginx --dry-run=server

# Test policy enforcement
kubectl apply -f test/policy-violation.yaml
```

## Troubleshooting

### Common Issues

**Agent not connecting to backend:**
```bash
# Check access key
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d

# Verify network connectivity
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- curl -v https://app.sysdigcloud.com
```

**Admission controller blocking deployments:**
```bash
# Check webhook configuration
kubectl get validatingwebhookconfigurations sysdig-admission-controller -o yaml

# Review admission controller logs
kubectl logs -f deployment/sysdig-admission-controller -n sysdig-shield
```

**ArgoCD sync failures:**
```bash
# Check ArgoCD application events
argocd app get sysdig-shield --show-events

# Force sync with replace
argocd app sync sysdig-shield --force --replace
```

## Development Workflow

1. **Make changes** to manifests or Helm values
2. **Test locally** using kubectl dry-run or helm template
3. **Commit changes** to feature branch
4. **Create pull request** for review
5. **Merge to main** triggers ArgoCD auto-sync (if enabled)
6. **Monitor deployment** via ArgoCD UI or CLI

## Best Practices

- **Use Helm charts** from official Sysdig repository when possible
- **Pin versions** of Sysdig components for stability
- **Enable auto-sync** only after thorough testing
- **Configure sync waves** for ordered deployment
- **Use health checks** to ensure proper rollout
- **Implement monitoring** for Sysdig components themselves
- **Regular updates** to address security vulnerabilities
- **Backup configurations** before major changes

## Resources

- [Sysdig Documentation](https://docs.sysdig.com/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sysdig Helm Charts](https://github.com/sysdiglabs/charts)
- [Sysdig Shield Features](https://sysdig.com/products/secure/)
