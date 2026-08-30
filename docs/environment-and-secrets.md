# Environment And Secrets

This repository owns deployment plumbing. The canonical backend runtime
contract lives in the backend repository:

```text
nitrogen-backend/docs/environment-and-secrets.md
```

Do not duplicate the local Docker Compose environment here. Local development
is owned by `nitrogen-backend/compose.local.yml`.

## GitHub Environments

Create two GitHub Environments in this infrastructure repository:

| Environment | Purpose | Required reviewers |
|---|---|---|
| `development` | Deploys the shared dev backend target on AWS | Optional for the learning setup |
| `production` | Deploys the production backend target | Recommended |

## Development Variables

Store these as GitHub Environment variables under `development`:

| Name | Example | Notes |
|---|---|---|
| `APP_DOMAIN` | `dev.example.com` | Used for the environment URL. |
| `AWS_ROLE_ARN` | `arn:aws:iam::<account-id>:role/nitrogen-github-actions-dev` | OIDC role assumed by GitHub Actions. |
| `AWS_REGION` | `ap-southeast-1` | Must match the deploy target region. |
| `EC2_INSTANCE_ID` | `i-0123456789abcdef0` | SSM target instance. |
| `DEPLOY_PATH` | `/opt/nitrogen/backend` | Directory containing deployment scripts. |
| `NITROGEN_ENVIRONMENT` | `dev` | Passed to every backend deploy script. |
| `BACKEND_IMAGE` | `ghcr.io/nitrogen-nit/nitrogen-backend` | Immutable image repository. |
| `BACKEND_IMAGE_DIGEST` | `sha256:...` | Can be supplied by workflow dispatch or release automation. |
| `BACKEND_VERSION` | `sha-<git-sha>` | Human-readable version marker. |

Development runtime config for the app should be stored on AWS:

| Name | Recommended AWS storage |
|---|---|
| `NITROGEN_DB_URL` | SSM String `/nitrogen/dev/db/url` |
| `NITROGEN_DB_USER` | SSM String `/nitrogen/dev/db/user` |
| `NITROGEN_DB_PASSWORD` | SSM SecureString or Secrets Manager secret |
| `NITROGEN_DB_POOL_SIZE` | SSM String `/nitrogen/dev/db/pool-size` |
| `NITROGEN_RABBIT_HOST` | SSM String `/nitrogen/dev/rabbit/host` |
| `NITROGEN_RABBIT_PORT` | SSM String `/nitrogen/dev/rabbit/port` |
| `NITROGEN_RABBIT_USER` | SSM String `/nitrogen/dev/rabbit/user` |
| `NITROGEN_RABBIT_PASSWORD` | SSM SecureString or Secrets Manager secret |
| `NITROGEN_RABBIT_HEALTH_ENABLED` | SSM String `/nitrogen/dev/rabbit/health-enabled` |
| `NITROGEN_LOG_LEVEL` | SSM String `/nitrogen/dev/log-level` |
| `NITROGEN_APPLICATION_VERSION` | SSM String `/nitrogen/dev/application-version` |
| `NITROGEN_TRACING_ENABLED` | SSM String `/nitrogen/dev/tracing/enabled` |
| `NITROGEN_TRACING_SAMPLING_PROBABILITY` | SSM String `/nitrogen/dev/tracing/sampling-probability` |
| `NITROGEN_OTLP_ENDPOINT` | SSM String `/nitrogen/dev/otlp/endpoint` |

## Production Variables And Secrets

Store these as GitHub Environment variables under `production`:

| Name | Example | Notes |
|---|---|---|
| `APP_DOMAIN` | `app.example.com` | Used for the environment URL. |
| `HETZNER_HOST` | `203.0.113.10` | Production host. |
| `HETZNER_PORT` | `22` | SSH port. |
| `DEPLOY_USER` | `deploy` | Least-privileged deployment user. |
| `DEPLOY_PATH` | `/opt/nitrogen/backend` | Directory containing deployment scripts. |
| `SSH_KNOWN_HOSTS` | `app.example.com ssh-ed25519 ...` | Host key pinning. |
| `NITROGEN_ENVIRONMENT` | `prod` | Passed to every backend deploy script. |
| `BACKEND_IMAGE` | `ghcr.io/nitrogen-nit/nitrogen-backend` | Immutable image repository. |
| `BACKEND_IMAGE_DIGEST` | `sha256:...` | Immutable image digest. |
| `BACKEND_VERSION` | `v1.0.0` | Release tag or version marker. |

Store this as a GitHub Environment secret under `production`:

| Name | Notes |
|---|---|
| `HETZNER_SSH_PRIVATE_KEY` | SSH key used only by the production deploy workflow. |

Production runtime secrets should live on the production host or in the
platform secret store, not in repository files:

| Name | Recommended production storage |
|---|---|
| `NITROGEN_DB_URL` | Host env file or production secret store |
| `NITROGEN_DB_USER` | Host env file or production secret store |
| `NITROGEN_DB_PASSWORD` | Host secret file or production secret store |
| `NITROGEN_DB_POOL_SIZE` | Host env file |
| `NITROGEN_RABBIT_HOST` | Host env file |
| `NITROGEN_RABBIT_PORT` | Host env file |
| `NITROGEN_RABBIT_USER` | Host env file or production secret store |
| `NITROGEN_RABBIT_PASSWORD` | Host secret file or production secret store |
| `NITROGEN_RABBIT_HEALTH_ENABLED` | Host env file |
| `NITROGEN_LOG_LEVEL` | Host env file |
| `NITROGEN_APPLICATION_VERSION` | Host env file |
| `NITROGEN_TRACING_ENABLED` | Host env file |
| `NITROGEN_TRACING_SAMPLING_PROBABILITY` | Host env file |
| `NITROGEN_OTLP_ENDPOINT` | Host env file or production observability config |

## Deployment Script Contract

Every target script under `DEPLOY_PATH/scripts` receives:

```text
NITROGEN_ENVIRONMENT
BACKEND_IMAGE
BACKEND_IMAGE_DIGEST
BACKEND_IMAGE_REF
BACKEND_VERSION
```

The scripts must load the runtime env contract before starting the backend
container. The production app must run with `SPRING_PROFILES_ACTIVE=web,prod`
or `worker,prod`; migration is a separate deploy step.

Never commit `.env`, `.env.local`, copied certificates, SSH keys, AWS keys,
database passwords, RabbitMQ passwords, or Sonar tokens.
