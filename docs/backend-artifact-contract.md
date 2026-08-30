# Backend Artifact Contract

The backend delivery pipeline publishes immutable container images to:

```text
ghcr.io/nitrogen-nit/nitrogen-backend
```

Deployment workflows consume these values from repository/environment variables
or `workflow_dispatch` inputs:

```text
BACKEND_IMAGE=ghcr.io/nitrogen-nit/nitrogen-backend
BACKEND_IMAGE_DIGEST=sha256:<digest>
BACKEND_VERSION=sha-<40-character-git-sha> or vX.Y.Z
```

The deploy target must expose these executable scripts under `DEPLOY_PATH`:

```text
./scripts/predeploy-backend.sh
./scripts/migrate-backend.sh
./scripts/deploy-backend.sh
./scripts/healthcheck-backend.sh
./scripts/smoke-test-backend.sh
```

Each script receives:

```text
BACKEND_IMAGE
BACKEND_IMAGE_DIGEST
BACKEND_IMAGE_REF=<BACKEND_IMAGE>@<BACKEND_IMAGE_DIGEST>
BACKEND_VERSION
NITROGEN_ENVIRONMENT=dev or prod
```

Required order:

1. `predeploy-backend.sh` validates host, Docker access, registry auth,
   configuration, database reachability, and free disk space.
2. `migrate-backend.sh` runs Flyway against the target database and exits
   non-zero on migration failure. Production application startup keeps Flyway
   disabled, so this step is mandatory.
3. `deploy-backend.sh` deploys only `BACKEND_IMAGE_REF`, never `latest`.
4. `healthcheck-backend.sh` waits for `/actuator/health/readiness`.
5. `smoke-test-backend.sh` verifies one minimal user-facing path.
