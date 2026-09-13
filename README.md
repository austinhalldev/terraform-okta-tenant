# terraform-okta-tenant

Terraform configuration for the Okta objects that svc-okta-identity-mcp and
svc-okta-log-triage depend on. Those projects were built by clicking through
the Okta Admin Console. This one codifies what they run on.

The governance question here is who is permitted to change the tenant, and
through what path. The two companion projects governed reads: what data may
cross a boundary, and what an agent is permitted to do. This one governs
writes, by anyone, including me.

A decision journal lives at [docs/decisions.md](docs/decisions.md). It
records the choices made, the alternatives declined, and what turned out to
be wrong. It is the more useful half of this repository.

## What is managed

| Object | Resource |
|---|---|
| API Services app `svc-okta-identity-mcp` | `okta_app_oauth` |
| Custom admin role `Identity MCP Read-Only` | `okta_admin_role_custom` |
| Resource set `Identity MCP Resources` | `okta_resource_set` |
| Role binding between the three | `okta_app_oauth_role_assignment` |

Three of the four were imported from existing console-built objects. The role
binding was recreated, for reasons recorded in decision 7.

## What is deliberately not managed

**API scope grants.** The two scopes granted to svc-okta-identity-mcp
(`okta.users.read`, `okta.groups.read`) cannot be managed by an
OAuth-authenticated service app. Okta documents that some objects have no
corresponding scope, and specifically that there is no scope for managing
scopes. Tested and confirmed; see decision 8. This is a permanent exception,
not unfinished work.

**Bootstrap objects.** Three things were created by hand because they cannot
create themselves:

- The Terraform service app in Okta. Granting API scopes to a service app
  requires a human Super Administrator.
- The S3 bucket holding Terraform state. A bucket cannot be created by the
  run that stores its state in it.
- The IAM user and policy used to reach that bucket.

Infrastructure as code has a floor. The honest move is to name where it is.

## Prerequisites

- An Okta org with an API Services app for Terraform, authenticating with
  `private_key_jwt` using a **PKCS#8 PEM** private key. Note the format: the
  companion Python projects use JWK, and the two are not interchangeable
  (decision 6).
- That app granted `okta.apps.read`, `okta.apps.manage`, `okta.roles.read`,
  `okta.roles.manage`, and assigned the **Super Administrator** role.
  Super admin is required rather than chosen; see decision 3.
- An S3 bucket with versioning enabled, and AWS credentials scoped to it.
- Terraform 1.10 or later, for S3 native state locking.

## Configuration

Copy `.env.example` to `.env` and fill in the values. `.env` is gitignored.
No tenant-specific value is committed to this repository.

```

cp .env.example .env
set -a; source .env; set +a
terraform init
terraform plan
```

A clean plan reports no changes. Anything else is drift, or a bug.

## State

State lives in S3, encrypted, versioned, with native locking
(`use_lockfile = true`; the DynamoDB table described in older guides is
deprecated). It contains the client ID, the tenant hostname, and the IDs of
every admin object here, so read access to that bucket discloses the tenant's
privileged configuration, and write access lets Terraform be lied to. The
bucket policy is scoped to a single IAM user and a single bucket.

## What this does not do

There is no apply-on-merge pipeline. Changes are applied by hand from a
devcontainer using a super admin credential that stays on one machine.
The reasoning is in decision 4: a one-person repository cannot satisfy the
review requirement that makes automated apply safe, and automating it anyway
would produce a super admin credential on a hair trigger behind a review gate
that is theater.

Terraform detects drift. It does not prevent console changes. Making
configuration genuinely exclusive is an organizational act, requiring reduced
standing admin access, a defined break-glass path, and drift treated as an
incident. None of that is enforced here.

## How this was built

Written with Claude Code running in manual-approval mode inside a rootless
Podman devcontainer, with each action reviewed before it ran. The decision
journal reflects that working method: I reviewed decisions and plan output
rather than syntax, and the entries record where the tooling was wrong as
often as where it was right.