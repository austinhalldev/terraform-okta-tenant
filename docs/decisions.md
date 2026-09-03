# Governance journal: terraform-okta-tenant

Working notes captured while codifying the Okta tenant configuration
built by hand for the two previous projects. The decisions made, the
alternatives declined, and what I got wrong. Entries record decisions as
they're made, ahead of and alongside implementation — a decision logged
here is a commitment the build will honor, not a description of code that
already exists.

Two companion journals exist at the same path. svc-okta-log-triage
governed what data may cross a boundary. svc-okta-identity-mcp governed
what an agent is permitted to do. Both concerned reads. This project
governs writes: who is permitted to change the tenant, and through what
path. The objects being codified here — the API Services app, its custom
admin role, its resource set, the role binding, and the granted API
scopes — are the same objects the MCP server depends on, so this project
manages the configuration that the previous one runs on.

Sessions: 3 September 2026 (scaffold, decisions 1-2).

---

## Part 1: Decisions

### 1. A separate repo and a separate container, not an addition to project 2

Project 3 gets its own repository and its own devcontainer, rather than a
`terraform/` directory inside svc-okta-identity-mcp.

**The easier path:** add Terraform to the existing repo. The objects being
codified are that project's objects, the tenant is the same, and the
container is already built.

**Why not:** the credentials differ in kind. Project 2's container holds
an Okta key scoped to two read permissions. Terraform needs manage scopes
on apps and roles — a credential that can delete the very app project 2
depends on. Putting both in one container means one compromised
environment yields both, and it means the MCP server's image carries
tooling it has no use for.

This is entry 3 of project 2's journal one level up: one credential, one
place, independently revocable. There it was about two development
machines. Here it's about two trust levels in the same tenant.

**Consequence worth stating:** the dependency now runs in one direction
and is invisible from the other side. Nothing in svc-okta-identity-mcp
records that its Okta configuration is managed elsewhere. A README note
in that repo is the cheapest fix and isn't written yet.

### 2. Provider pinned to `~> 7.0`, ten days after v7.0.0 shipped

The Okta provider is pinned to the 7.x line. `required_version` is set to
`>= 1.10`, the floor for S3 native state locking, decided in entry 3.

**The easier path, and the one I initially argued for:** v6.15.0. The
provider's README warns against v6.14.0 and names v6.15.0 as the highest
recommended version, which reads like an instruction to stay on 6.x.

**Why not:** the README line appears to predate v7.0.0 rather than to be a
warning about it — v7.0.0 shipped 24 August 2026, and the README wasn't
updated. More to the point, v6.14.0 was a *minor* release. A policy of
staying one major behind would not have avoided the one release that is
actually known to be bad. Version numbers don't predict breakage.

Choosing 6.15.0 for a greenfield project means starting with a migration
already owed. That's the argument from entry 4 of project 2's journal,
where the MCP SDK was pinned to v2 rather than the maintenance line, and
where Okta's own MCP server was noted carrying a `<2` pin and a pending
migration. Same reasoning, same vendor, different tool.

**What was checked before deciding:** all eight breaking changes in
v7.0.0. They affect email templates, threat insight settings, role
subscriptions, SMS templates, trusted origins, and CAPTCHA. None touch
`okta_app_oauth`, `okta_admin_role_custom`, `okta_resource_set`,
`okta_app_oauth_role_assignment`, or `okta_app_oauth_api_scope`.

**What this costs, stated plainly:** v7.0.0 is ten days old. Fewer people
have hit its bugs. Against a production tenant I would let a major bake
for a release or two. This is a sandbox whose only dependant is my own MCP
server, and any breakage surfaces in a plan before it applies.

**The pin is two mechanisms, not one.** `.terraform.lock.hcl` records the
exact version and its checksums; the constraint in `terraform.tf` records
what range I'm willing to accept. The lock file is the seatbelt, the
constraint is the policy. Committing the lock file also gets
supply-chain integrity for free — a substituted artifact fails the
checksum. Project 2's entry 10 named unpinned `npx`-fetched `mcp-remote`
as residual risk; here the tooling closes that gap by default.

**A smaller lesson, recorded because it nearly cost a decision:** I
quoted the vendor README's "highest recommended version" as current. It
wasn't; the release tags were newer than the prose. Read the tags, not
the README.