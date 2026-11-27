# Getting non-technical users a server (exploration)

Status: open question, researched on 2026-11-26. Follows from `embedded-bridges.md`, which shelved
running the server and bridges inside Seam because of app-store rules. This is the other route:
help users get their own hosted Matrix server with bridges, without Seam's owner running it.

## Goal

A user who cannot self-host taps through Seam and ends up with their own Matrix server and bridges.
Billing is between the user and the hosting company. After setup Seam (and its owner) holds no keys
and carries no ongoing liability for the server.

## etke.cc (managed Matrix hosting)

- No affiliate or referral program, no reseller or white-label program, no ordering API on the
  public site (read 2026-11-26: home, help, FAQ, order, services, contacts, llms.txt). Ordering is
  "possible only using the JavaScript form"; their team then sets servers up by hand. Contacts page:
  "We only offer the services described on the services page, nothing beyond those." Partnership
  questions would go to their general support email.
- Pricing: subscription from 5 EUR/month (Matrix base), about 12 EUR/month more for a Hetzner server
  they rent for you; no per-user charges.
- Their automation is open source (github.com/etkecc; Ansible roles in the
  mother-of-all-self-hosting organization, i.e. matrix-docker-ansible-deploy). Actively maintained:
  pushes on 2026-11-25 and 2026-11-26.

## Provisioning in the user's own cloud account

| Host | Third-party OAuth | Notes |
|---|---|---|
| DigitalOcean | yes | Documented OAuth API for third-party apps, granular scopes (e.g. `droplet:create`), PKCE for public clients. https://docs.digitalocean.com/reference/api/oauth/ |
| Linode / Akamai | yes | OAuth clients via `login.linode.com/oauth/authorize`, read-only or read-write scopes per area. https://techdocs.akamai.com/linode-api/reference/oauth-clients |
| Hetzner Cloud | no | Project-bound API tokens only; the user would paste a token. |

Handover shape: the user signs in to the host from Seam and approves server creation; Seam creates
the server in their account and runs the open-source setup; the user's own SSH key is the admin key;
Seam then revokes its token (the user can also revoke it in the host's settings). The host bills the
user directly. DigitalOcean and Linode marketplaces ("1-Click Apps") are a no-code variant: publish an
image, users deploy it from the host's site.

## What still ties the owner in after setup

- **Updates:** the server must keep itself patched (automatic OS and container updates), or the user
  owns that; a paid managed tier would be separate and opt-in.
- **Domain:** Matrix needs a stable server name. Handing out `user.<our domain>` keeps the owner in
  the loop as DNS provider; the user's own domain avoids it at the cost of friction.
- **Backups:** the host's snapshot feature, enabled in the user's account.
- **Terms:** a short "you own and operate this server" page (not legal advice).

## Open questions for the next session

- Which host first (DigitalOcean has the cleanest OAuth); minimum server size for Synapse vs a
  lighter homeserver plus the bridges Seam relies on.
- iMessage is not covered by any of this: it needs Apple hardware (the macoun setup).
- The domain question above.
- Whether to approach etke.cc anyway (custom deal) versus driving the same open-source playbooks.
