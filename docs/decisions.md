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

Sessions: 3 September 2026 (scaffold, decisions 1-4), 12 September 2026
(four objects imported, decisions 5-8), 14 September 2026 (state to S3,
published, first PR, decisions 9-11), 15 September 2026 (plan in CI,
decision 12).

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

### 5. Import is a three-step loop, and the tooling fails differently at each step

All four objects (the API Services app, the custom admin role, the resource
set, and the role binding) are now under Terraform management with a
zero-diff plan. The loop per object is: declare the object exists (an
`import` block), obtain a description of it, confirm the description matches
reality (`plan` reporting no changes). Each step failed at least once, and
the failures were more instructive than the successes.

**Config generation needs the provider named; the resource block then
forbids it.** `terraform plan -generate-config-out` could not resolve
`okta_admin_role_custom` to a provider, defaulted to the `hashicorp`
namespace, and failed. HashiCorp documents the fix as adding a `provider`
block and re-running `init`; that did not resolve it. Adding
`provider = okta` inside the import block did. Once the generated resource
block was moved into configuration, that same argument became an error: the
provider argument is only valid in import blocks that generate
configuration.

The reasoning is sound. A resource block is where provider association
belongs, so permitting it in both places would allow two lines to disagree.
But the sequence is undocumented as far as I could find, and the error
surfaced as "Inconsistent dependency lock file" with the real cause nested
inside. The parse failure meant provider requirements could not be computed,
and the lock check failed downstream. Loud line, quiet cause.

**Generated configuration does not validate.** For the resource set, the
generator emitted both `resources` and `resources_orn` as null. The provider
requires exactly one, so generation produced configuration that fails its
own validation. The two fields are alternative representations of the same
thing, REST URLs or Okta Resource Names, and the generator could not choose.
Written by hand instead.

**Generated configuration includes attributes the object cannot have.** For
the service app, the generator emitted `omit_secret`,
`refresh_token_leeway`, `refresh_token_rotation`, and
`skip_authentication_policy`. Okta returned 403 on the update. These are
refresh-token, client-secret, and sign-on-policy attributes. None apply to a
`client_credentials` app authenticating with `private_key_jwt`. The
generator is schema-aware but not app-type-aware: it writes every attribute
the provider supports, whether or not the object can hold it. Removing the
four lines produced a clean plan.

**What this cost, and what it is worth:** a 403 on an app update is
indistinguishable at first glance from a permissions problem. I checked the
service app's scopes and role assignment before concluding otherwise, which
was the right order, but only because the console eventually stated plainly
that a Super Administrator assignment "cannot be further constrained and
will be active for the entire org." Without that line I would have kept
looking at permissions.

Config generation is flagged experimental. It is worth using. It supplied
field names I would not have guessed and the correct values for everything
that did apply. But its output is a draft, not configuration.

### 6. Two tools, one tenant, one auth pattern, incompatible key formats

The Terraform provider authenticates with a PKCS#8 PEM private key.
svc-okta-log-triage and svc-okta-identity-mcp authenticate with a JWK. Both
use `private_key_jwt` against the same Okta tenant, with the same kind of
service app. The key generated for the first two projects does not work for
Terraform; the provider reports "invalid private key," which is accurate and
easy to misread as a corrupt or mismatched key rather than a format
mismatch.

Okta's console will generate either format. A second keypair was generated
in PEM, registered as an additional public key on the service app, and the
original removed. This is the same multiple-public-key capability recorded
in entry 3 of svc-okta-identity-mcp's journal as what makes per-machine keys
and zero-downtime rotation possible.

**Worth stating because it is easy to gloss:** there is nothing wrong with
either tool. A Python project parsing JWK and a Go provider expecting PEM
are both reasonable. But a service app is a single object with one set of
registered public keys, and a person moving between two projects against the
same tenant will reasonably assume the credential material is portable. It
is not. The format is a property of the consuming tool, not of the app.

### 7. The role binding was recreated rather than imported

The binding between the custom role, the resource set, and the MCP service
app was deleted in the console and recreated by Terraform, rather than
imported like the other three objects.

**Why:** the import ID for `okta_app_oauth_role_assignment` is
`<clientID>/<roleAssignmentID>`. The role assignment ID is not exposed
anywhere in the Admin Console. Obtaining it requires calling
`GET /oauth2/v1/clients/{clientId}/roles`, an authenticated API call, which
in this container would have meant writing a signing script in bash, since
the Terraform devcontainer deliberately has no Python.

**Why this was acceptable here and would not be in production:** the binding
is a pure join. It holds no data and nothing references its ID, unlike the
service app whose client ID is configured in svc-okta-identity-mcp. Deleting
and recreating produces an identical result. But between the delete and the
apply there is a window with no grant, which for a live integration is a
permissions outage. In production the correct answer is to find the ID and
import, precisely to avoid that window.

The general rule this follows: **import when the object's identity is
referenced elsewhere, recreate when it is not.** Recreation during a
migration is a legitimate tactic. It is not a default, and the condition
that makes it safe should be stated rather than assumed.

**A side benefit worth noting:** the recreated binding references
`okta_admin_role_custom.mcp_read_only.id` and
`okta_resource_set.mcp_resources.id` rather than literal IDs, so Terraform
knows the dependency order. An imported binding would have carried hardcoded
IDs and expressed no relationship.

**One correction to the record:** the console permission labels do not match
the API. What the console calls "view users' profile attributes" is
`okta.users.userprofile.read`, and "View groups and their details" is
`okta.groups.read`. svc-okta-identity-mcp's README hedges on this, noting
the wording shifts between console versions. The API names are the stable
ones, and that README should say so.

### 8. API scope grants are not codifiable, and the boundary is authentication, not privilege

Entry 3 recorded an open question: whether `okta_app_oauth_api_scope` works
under OAuth 2.0 provider authentication. It does not. The resource has been
removed from the configuration and the two scope grants on
svc-okta-identity-mcp remain a console operation.

**What was tested.** `terraform apply` against a correctly-formed resource
returned "The access token provided does not contain the required scopes"
from the Application Grants endpoint. The service app holds Super
Administrator, unconstrained, and `okta.apps.manage`, which is the scope the
endpoint would plausibly require.

The first hypothesis was that a client cannot grant a scope it does not
itself hold, which would be a sensible privilege-escalation guard.
`okta.users.read` and `okta.groups.read` were temporarily granted to the
Terraform service app and the apply retried. Identical error. The hypothesis
is wrong, and the scopes were revoked immediately afterward.

**What remains, and it matches Okta's own documentation:** some objects have
no corresponding OAuth scope, and specifically there is no scope for
managing scopes. A service app cannot grant API scopes no matter what it
holds, because the capability is not expressible in the scope system at all.
Okta's guide states separately that granting new API scopes to a service app
requires Super Administrator permission, which is a statement about human
admins rather than about tokens.

**Why this is a different shape from entry 3.** Entry 3 found that
least-privilege objects require a maximum-privilege credential: a problem of
degree, solved badly but solved. This is a problem of kind. No credential
of any privilege level, authenticating this way, can perform this operation.
The ceiling on what is codifiable here is set by the authentication method,
not by the permissions attached to it.

**What was deliberately not tested.** The provider also supports SSWS API
token authentication, tied to a human admin account rather than a service
app. The grant may well succeed that way, which would narrow the finding to
"not codifiable under OAuth 2.0 provider authentication." That test was
declined: an API token bound to my own admin user is the credential model
decisions 3 and 4 exist to argue against, and confirming a boundary is not
worth introducing one, even briefly. The finding is therefore recorded at
the precision actually established and not beyond it.

**Consequence for the project, stated plainly.** Four of five objects are
under Terraform management. The fifth is not, and this is a permanent
exception rather than unfinished work. The README and this journal name it,
so a reader can tell the difference between a documented boundary and a gap
someone forgot to close. That distinction is the one most migrations get
wrong: not that something was left manual, but that nobody wrote down which
things were left manual on purpose.

### 9. State moved to S3, and the bucket is a third bootstrap object

Terraform state now lives in an S3 bucket, encrypted with SSE-S3, versioned,
with native locking enabled through `use_lockfile = true`. Migrated with
`terraform init -migrate-state`.

**Why not leave it local.** A local state file exists in exactly one place.
Losing it means Terraform no longer knows it owns anything and will attempt
to create duplicates of objects that already exist. It also cannot be reached
by anything but the machine holding it, which forecloses the CI workflow in
decision 4.

**Why not DynamoDB.** Most guides describe a DynamoDB table for state
locking. That mechanism is deprecated. S3 conditional writes now support
locking directly, and `use_lockfile = true` on the backend block replaces the
table entirely. This is the second time in this project that the
highest-ranked search results described a pattern the vendor is retiring; see
decision 2 for the first.

**Why versioning is not optional.** It is what makes a corrupted or truncated
state file recoverable, and it cannot be applied retroactively to objects
already written. It also holds the lock object.

**What the bucket contains, and who can read it.** State holds the client ID,
the tenant hostname, the role and resource set IDs, and the public key. Read
access to the bucket therefore discloses the tenant's privileged
configuration without any access to Okta. Write access is worse: state is
what Terraform believes, so altering it makes Terraform act on a false
picture — pointing an entry at a different object's ID would cause the next
apply to modify that object instead, with no error. The IAM policy is scoped
to `s3:ListBucket` on this one bucket and get, put, and delete on objects
within it. Nothing broader.

**A credential quality note.** The AWS access key is a long-lived shared
secret sent with every request, which is weaker than the Okta credential,
where a private key signs an assertion and never crosses the network. The
better answer for automation is short-lived credentials through OIDC. Not
implemented here; named so it is not mistaken for an oversight.

**Third bootstrap object.** The bucket cannot be created by the run that
stores its state in it, so it was created by hand, as were the IAM user and
policy. Decision 1 predicted this; it is now concrete rather than
hypothetical.

### 10. The repository is public, and what that required

Published at github.com/austinhalldev/terraform-okta-tenant.

**What was verified first.** `git ls-files` to confirm exactly what was
tracked, a search of history for any filename matching env, pem, tfstate, or
key, and a grep of every `.tf` file for the tenant hostname and client ID
prefix. All clean. The tenant hostname, client ID, key ID, RSA modulus, and
authentication policy ID are Terraform variables supplied from a gitignored
`.env`; `.env.example` is committed with placeholders.

**The split between secrecy and portability, because they are not the same
thing.** The key ID and client ID are variables because they are values I
have chosen not to publish. The RSA modulus and the policy ID are variables
for a different reason: the modulus is a public key and discloses nothing,
and the policy ID is an opaque identifier. They are parameterised so the
configuration is portable to another tenant rather than to keep them secret.
Treating every value as a secret is a weaker position than knowing which
ones are.

**The repository was created private and made public after review.** The
gitignore rules had never been tested against a real push. The first test of
an ignore rule should not happen against a public repository.

### 11. One change through a pull request, end to end

A one-line change to the custom role description, taken through a branch, a
pull request, a merge, and an apply. The purpose was the process rather than
the change.

The sequence: branch from `main`, edit `roles.tf`, run `terraform plan` and
confirm `1 to change, 0 to destroy`, commit, push, open a pull request,
review the diff, merge, pull `main`, apply, verify in the Okta console.

**What the pull request does and does not show.** The Files changed tab
shows one line replaced by another. It does not show what that means for the
tenant. The plan summary had to be pasted into the description by hand. That
gap is exactly what plan-on-pull-request automates, and it is why decision 4
treats the CI workflow as the part that makes review meaningful rather than
as polish. A reviewer reading only the HCL diff cannot tell the difference
between a description change and a change that forces replacement of the app
and mints a new client ID.

**What this proves and what it does not.** The tenant now has a change whose
provenance is a commit, an author, a timestamp, and a reviewable diff. What
it does not prove is enforcement: the merge button was available because
nothing required another reviewer, and the apply was mine to run or skip.
The mechanism exists. The control does not.

**The distinction that matters, recorded plainly.** Migrating configuration
into Terraform was a one-time act. This is the ongoing one. A claim to have
moved from console clicks to GitOps is a claim about this loop, not about the
import.

### 12. Plan runs in CI under a credential that cannot apply

A GitHub Actions workflow runs `terraform plan` on every pull request and
posts the output as a PR comment. It does not apply. The credential it uses
cannot apply even if the workflow were changed to try.

**The CI credential is a separate Okta service app**, `terraform-okta-tenant-ci`,
with `okta.apps.read` and `okta.roles.read` and a custom admin role holding
exactly two permissions: view applications and their details, and view roles,
resources, and admin assignments. There is no manage scope and no manage
permission anywhere in the grant.

**This is the least-privilege role that decision 3 could not build.** Apply
needs to manage roles and resource sets, which Okta can only express as
Super Administrator. Read needs neither, so the CI credential is a genuine
custom role scoped to a resource set. The asymmetry is the point: the
operation that changes things requires the broadest credential in the tenant,
and the operation that only looks requires almost nothing.

**Why this matters more than the workflow file.** Decision 4 argued for
plan-only on the grounds that a one-person repository cannot supply the
review that makes automated apply safe. That was a decision about what the
pipeline does. This is a decision about what the pipeline *can* do. A
workflow edited to run apply would fail on permissions rather than succeed.
The constraint is enforced by the credential, not by the contents of a file
that any pull request could change.

**Eleven values now live in GitHub Actions secrets.** Tenant identifiers, the
CI private key, and the AWS credentials for the state backend. That is a
second store holding the same material as the local `.env`, with its own
access model and its own set of people who could reach it. Publishing a
repository and wiring up CI both expand where these values exist; neither
is free.

**One boundary worth recording precisely.** GitHub redacts registered secrets
from workflow logs; the MCP client ID appeared as `***` in the run output.
It did not appear redacted in the plan comment, because the comment body is
written by the workflow from a file rather than emitted to the log stream.
Log scrubbing is not a general secret filter. Anything a workflow writes to
a comment, an artifact, or an external service bypasses it.

**What still is not enforced.** Nothing requires the check to pass before
merging, because branch protection requiring review cannot be satisfied by a
single maintainer. The plan is visible; heeding it remains a matter of
discipline. The mechanism is complete and the control is still partial,
which is the same shape as decision 11 and for the same reason.