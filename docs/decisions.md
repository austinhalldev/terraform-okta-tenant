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

### 3. Terraform requires super admin, and that is not a configuration choice

The Terraform service app is granted the Super Administrator standard
role. Scopes are minimum viable — `okta.apps.read`, `okta.apps.manage`,
`okta.roles.read`, `okta.roles.manage` — but the role is the broadest
one Okta has.

**The easier path, and the one I went looking for:** a custom admin role
scoped to exactly the objects this project manages, mirroring what
svc-okta-identity-mcp already does. Two read permissions there; some
small manage set here.

**Why not — it does not exist.** Okta's custom role permission picker
has one entry under Identity and Access Management: *View roles,
resources, and admin assignments*. There is no manage counterpart. A
custom role can be granted the ability to read roles, resource sets, and
admin assignments, and cannot be granted the ability to create, change,
or delete them.

The two fallbacks close as well. Organization Administrator, per its own
console description, cannot manage applications or other admins — which
is precisely the two things needed here. Super Administrator is what
remains.

**Why this is structural rather than a gap in Okta:** if a custom role
could grant role management, any principal holding it could author a new
role carrying any permission in the tenant. A bounded grant that includes
the power to unbound itself is not bounded. Role management is privilege
escalation by construction, so the only coherent place to put it is the
top. This is the correct design, not an oversight, and I would expect the
same shape in any IAM system that supports delegated administration.

**The consequence, stated plainly:** codifying least privilege requires
a credential that holds everything. svc-okta-identity-mcp runs on two
read permissions. The app that creates and maintains that configuration
is a super admin. The tightest object in the tenant is produced by the
loosest credential in it, and there is no arrangement of scopes and roles
that avoids this.

**What this does to auditability, which is the part I initially had
backwards.** Console clicking has one real virtue: Okta's System Log
attributes every change to the human admin who made it, for free, enforced
by the IdP. Routing changes through Terraform destroys that. Every change
is now attributed to one service app, and Okta can no longer say which
person caused it.

Accountability therefore does not come from Terraform. It moves to git —
commit authorship, review, and branch protection — and Terraform is
simply what makes that possible. Run Terraform from a laptop with no PR
discipline and the result is strictly worse than console clicking: all
changes concentrated into a single super-admin identity, with the
attribution that used to be automatic now gone and nothing put in its
place.

This is why the IaC half is not the deliverable. The GitOps half is where
the accountability lives, and without it this project would be a
regression.

**What has to be true for the trade to pay off:**

- Changes reach the tenant through a reviewed path — see entry 4 for why
  this project implements only half of one.
- The credential lives where a human cannot casually invoke it.
- Console write access is reduced, or plans report drift forever and the
  code becomes documentation that lies.
- A break-glass path exists, is logged, and its changes are back-ported
  to code.

**What is true here instead, recorded rather than glossed:** this is a
sandbox tenant with one dependant, my own MCP server. I retain super
admin in the console. Nothing in the list above is enforced yet; the CI
workflow that would enforce the first two isn't built. The credential
being created in this session is a super admin credential on a
workstation, which is the exact posture this entry argues against. It is
acceptable here only because the blast radius is a tenant I can rebuild,
and it should not be mistaken for the recommended arrangement.

**Open question, recorded rather than resolved:** whether
`okta_app_oauth_api_scope` works at all under OAuth 2.0 provider
authentication. Okta documents that some objects have no corresponding
scope, and specifically that there is no scope for managing scopes. If
the API scope grants turn out not to be codifiable, that is a fifth object
staying in the console permanently, and the boundary is worth recording
precisely rather than working around silently.

### 4. Plan in CI, apply by hand — because I am the only reviewer

The GitHub Actions workflow runs `terraform plan` on pull requests and
posts the output as a comment. It does not run `terraform apply`. Applying
is done by hand from the devcontainer, using the super admin credential
from entry 3, which never leaves that machine.

**The easier path, and the one entry 3 argues for:** apply on merge. The
pipeline holds the credential, merging is the deploy, and no human is ever
in a position to change the tenant directly. That is the arrangement that
makes entry 3's accountability argument actually true, and in an org with
real reviewers it is the correct answer.

**Why not, here:** apply-on-merge requires storing a super admin
credential in GitHub Actions secrets, fired automatically by a merge. That
is safe when a merge means several engineers reviewed the change. This is
a one-person repository. A merge here means I approved my own work, so the
review step the automation depends on does not exist. Automating apply
under those conditions would not produce accountability; it would produce
a super admin credential on a hair trigger, with a review gate that is
theater.

Branch protection makes this structural rather than a matter of
discipline: the common configuration requires approval from someone other
than the author, and a solo repository cannot satisfy that rule. The
constraint is real, not a shortcut.

**What plan-only still buys:** the pull request carries the plan output,
so what gets reviewed is the effect on the tenant rather than a diff of
HCL. That is the review that matters — "changes a description" and
"destroys and recreates the app, minting a new client ID" are one line
apart in configuration and very far apart in consequence. It also means
the credential CI holds can be read-scoped rather than super admin.

**What it does not buy, stated rather than glossed:** nothing prevents me
applying a change that never appeared in a pull request. The discipline
is mine to keep and nothing enforces it. Entry 3's requirement that
changes reach the tenant only through a reviewed path is therefore not
met by this project; it is half-met, deliberately, and the missing half
is named here rather than left implied.

**A note on the read-scoped CI credential:** plan reads every object it
manages, so "read-only" still means a credential that can enumerate the
tenant's admin configuration. Less dangerous than write. Not nothing.

**What would change this in an org:** required reviews from people other
than the author, protected branches, restricted review on the workflow
file itself — it lives in the repository it protects, so a pull request
can modify the pipeline — and environment approvals gating the credential
separately from merge. With those in place, apply-on-merge is right and
this entry's reasoning no longer applies.