# ${{ values.name }}

${{ values.description }}

Created from the platform team's **ITL service** golden path. Owned by `${{ values.owner }}`; first cloud: `${{ values.cloud }}`.

| What | Where |
| --- | --- |
| Kubernetes manifests | `deploy/` (Kustomize: `base`, `overlays/dev`) |
| Deployment | Argo CD application `argocd/application.yaml`: a merge to `main` that changes `deploy/` is deployed |
| CI | `.github/workflows/ci.yml`: build, scan and push the image |
| SLOs | `docs/slo.md`: fill in your targets before going to production |
| Catalog | `catalog-info.yaml`: this service in Backstage |

Everything here can be changed: the golden path is the easy, supported way, not the only way.
