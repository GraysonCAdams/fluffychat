# Seam hosted servers: disclaimers, placement and terms (draft)

Status: research draft, 2026-11-26, for Grayson to review. **Not legal advice.** Nothing here has
been reviewed by a lawyer. Section 7 lists what a lawyer should look at before the first paying
user. Every external source is cited inline as `[Sn]` and listed in section 8 with URL and fetch
date. Items marked **UNVERIFIED** were not confirmed from a primary source this session; items
marked **(background)** come from general knowledge and were not fetched.

Inputs read: `C:\src\fluffychat-search\docs\hosted-servers.md`, `docs\embedded-bridges.md`, the
scratchpad mockups `server-setup-flow.html` and `server-lifecycle.html`, the architecture draft
`hosted-servers-architecture.md` (sections 1 to 4; it was still being written), and the Railway doc
snapshot in `scratchpad/rw/` (Railway docs fetched 2026-11-26).

---

## 0. Headline findings (read these first)

1. **Disclaimers only allocate risk between Seam and the user.** They do nothing about claims by
   Meta, Google, Discord, LinkedIn or X against Seam itself, and they do not cure an app-store policy
   violation. The precedent to know is *Facebook v. Power Ventures* (9th Cir. 2016): an aggregator
   that logged in with users' own permission was held liable under the CFAA for continuing after a
   cease-and-desist and IP block (background, verify). A written plan for "what Seam does on a
   cease-and-desist" (drop that network from the catalog) belongs in the launch checklist.
2. **Railway's own rules are a new risk.** Railway's Acceptable Use Policy prohibits "running bots
   or scrapers that violate applicable terms of service" [S1][S2]. Unofficial-client bridges are
   arguably exactly that. Railway can restrict the user's workspace [S2], remove the template, and
   removed templates lose kickbacks [S3][S4]. Railway's docs invite you to ask before deploying
   ("If you're unsure whether your workload is permitted, ask through Central Station or email
   abuse@railway.com before deploying" [S2]). **Ask Railway in writing before launch.**
3. **Recommend maintenance variant (a), "Seam sends updates, best effort, no guarantee".** The
   default design pushes signed releases to every server automatically, and Railway's template
   publishing terms make the publisher promise "You'll maintain it. You keep it working as its
   dependencies change, and you answer questions from the people who deploy it" [S4]. Telling users
   "hosting does not include maintenance" while Seam auto-updates their server would contradict
   Seam's actual conduct, which is the classic way a disclaimer becomes a deceptive statement. Use
   variant (b) wording only for the states where it is true: Seam access turned off, or the server
   exported and self-hosted. Details in 3.4.
4. **The kickback must be disclosed next to the Railway recommendation**, not only in the terms.
   FTC 16 CFR 255.5 requires material connections to be disclosed "clearly and conspicuously"
   [S5], and the FTC says "The closer the disclosure is to your recommendation, the better" [S6].
   Telegram's API terms separately require "all monetization methods" to be mentioned in app-store
   descriptions [S7].
5. **Two mockup statements may be false as drawn and need fixing before copy is final:**
   - Setup step 7 says "Seam no longer has access to your Railway account"; the architecture keeps
     access by default (architecture section 1 already flags this).
   - The access screen says "Seam can only see the one project it created", but the architecture
     says "Scope needed to create a project is workspace-wide" (architecture, decisions table). Also,
     revoking Seam's app in Railway's Authorized Apps invalidates the app's OAuth tokens [S8] but the
     **manager's project token on the server is a separate credential**; "access off" must delete
     that too, or the copy must say updates still arrive. Copy in this draft assumes the scope is
     honestly described once U2 in the architecture is settled.
6. **Initial scope: United States only, 18+.** EU and UK consumer law makes the core disclaimers
   (as-is, no update duty, liability caps) partly unenforceable and adds GDPR duties (section 4.3).
7. **An LLC is worth forming before money flows** (section 7.3), mainly for liability separation
   and because Microsoft Store wants a company account from "any person acting in relation to their
   trade or profession" [S9].

---

## 1. Risk inventory

"Bearer" is who actually suffers the loss if it happens. "Disclose because" is the legal or
practical reason the notice is needed.

| # | Risk | Bearer | Disclose because |
|---|---|---|---|
| R1 | **Third-party terms and account bans.** Bridges are unofficial clients. WhatsApp's terms forbid accessing the service "in an unauthorized manner" and building software that functions "substantially the same as our Services" [S10]; Signal forbids using the service "in unauthorized manners" [S11]; Discord forbids "any unauthorized software designed to modify the services" and automated access [S12]. mautrix's own docs warn: "WhatsApp is known to ban accounts that are too suspicious" [S13]. Telegram is the exception: its API terms welcome third-party clients [S7]. | User (loses WhatsApp, Instagram etc. account, possibly permanently; WhatsApp says "you agree not to create another account without our permission" [S10]). Seam secondarily (platform claims, store removal). | The user cannot weigh the risk without being told; loss of a primary messaging account is serious and not obvious. Affirmative acknowledgment per network is the strongest evidence the user accepted it. |
| R2 | **No affiliation; trademark use.** Seam shows WhatsApp, Signal, Google Messages etc. by name. Play: "Don't use another party's trademarks, such as logos or brand names without permission" [S14]. WhatsApp brand rules forbid use that "implies partnership, sponsorship, or endorsement" and logos "confusingly similar" [S15]. Telegram: no official logo, and "Telegram" only in a title if preceded by "Unofficial" [S7]. | Seam (trademark claims, store removal). | Nominative fair use (naming a product to say you work with it) generally requires no implied endorsement and no more of the mark than needed (background: *New Kids on the Block v. News America*, *Toyota v. Tabari*, verify). A "not affiliated" line supports that; using real logos undermines it. The mockups' initials badges ("WA", "GM") are the right instinct; keep them. |
| R3 | **No guaranteed functionality or uptime.** Bridges break when networks change; WhatsApp drops linked devices after about 2 weeks offline [S13]; Railway has outages; one replica, no HA (architecture non-goals). | User (missed or delayed messages). | Messaging is relied on for time-sensitive and safety matters. Needs a plain "don't rely on this for emergencies" line, and a conspicuous as-is clause (Georgia requires exculpatory terms to be "explicit, prominent, clear and unambiguous" [S16]). |
| R4 | **Privacy and E2EE.** Bridges decrypt each network's end-to-end encrypted messages on the server so they can be shown in Matrix. Anyone controlling the server (the user, and in principle the host, Railway) can read them. mautrix notes end-to-bridge encryption exists precisely so a cloud provider "can't see messages" when hosting locally [S17]; on Railway the bridge itself runs at the cloud provider. In unencrypted rooms "events are stored in plaintext in the homeserver database" [S17]. | User and their contacts (who never agreed to Matrix). | Users choose WhatsApp/Signal for E2EE; bridging changes the security model. Play requires a prominent in-app disclosure when data use "may not be within the reasonable expectation of the user" [S18]. |
| R5 | **User owns and operates the server; user is the data controller.** The server holds the user's messages and their contacts' messages, and up to about 5 family accounts (architecture non-goals). | User. | Sets who answers for data, legal requests, family members' accounts and lawful use. Railway's terms already make the user use services "only in a manner that complies with all laws that apply to you" [S19]. |
| R6 | **Railway is a separate company.** Its terms, prices, plan rules, outages, restrictions and bans apply directly; Railway's liability cap is "the greater of (I) one-hundred ($100) dollars or (II) the amounts paid" [S19]; Railway requires users to be 16+ [S19]. | User (and Seam if the template is removed). | The user contracts with Railway, not Seam; they need to know the server lives or dies by Railway's account rules (see headline 2). |
| R7 | **Payments go to Railway, not Seam; cost estimates.** Hobby is $5/month plus usage; the mockup shows "about $3 to 6" usage. | User. | Cost claims must be truthful and substantiated (FTC Act section 5, Georgia FBPA, background). Label figures as estimates and point to Railway's bill as final; recommend a spending limit (architecture: minimum hard limit $10, per workspace). |
| R8 | **Kickback.** Seam earns 15% of Railway usage, 25% with template-queue support [S3]. | User (conflict of interest: Seam's income rises with the user's bill). | FTC endorsement guides [S5][S6]; Telegram API terms 3.2 [S7]. Also good faith: the architecture chose continuwuity partly to keep the user's bill low; saying so helps. |
| R9 | **AI assistant limits (deferred past v1; section 9).** Optional, runs through a Seam-run relay that "sees assistant conversation text (bridge help output, error text)" and never credentials (architecture 2.4). Model output can be wrong. | User (bad advice; data seen by relay and model provider). | Privacy disclosure (who sees what), plus accuracy caveat. Play's AI-Generated Content policy requires in-app reporting for apps where a chatbot is "a central feature" [S20]; probably not central here, but a report button is cheap. |
| R10 | **Open source (AGPL) obligations.** Seam app is AGPL-3.0; the server image bundles AGPL mautrix bridges and Apache continuwuity. Publishing the image on ghcr.io is conveying object code, so Corresponding Source must be offered (AGPL section 6); a modified AGPL program used over a network must offer source to its users (section 13) (background, verify against the license text). | Seam (compliance); user (if they modify). | License condition; also the honest basis of "you can self-host". AGPL's own warranty disclaimer (sections 15 and 16) covers the software, not Seam's service, so the terms still need their own. |
| R11 | **Support scope.** One person; no SLA. Railway's 25% tier requires answering the template queue [S3]; publishing terms require answering questions [S4]. | User (waits, unsolved problems). | Sets expectations; avoids an implied promise. Note the contradiction to avoid: "no support" is false if Seam answers the template queue for the bonus. |
| R12 | **Technical skills still needed.** Convenience does not remove the need to troubleshoot a real server: Railway dashboard, logs, variables, or a shell. Railway does offer a shell: `railway ssh` "Open[s] an interactive shell session inside a deployed Railway service container" and requires an SSH key registered with Railway [S21]. (SSH is disabled only for services using hidden private-registry credentials [S22]; Seam's image is public, so it should be available.) | User. | Grayson's added theme (2026-11-26). Prevents the "I paid, so someone else fixes it" expectation. |
| R13 | **Export and self-host.** Export is encrypted with a password Seam cannot recover; a server on the free Railway address cannot keep its address when moved; bridge logins can only run in one place (lifecycle mockup). After moving, Seam no longer updates it. | User (data loss, broken address). | The ownership promise is only true with these limits stated. |
| R14 | **Data loss.** Backups optional, Hobby volume 5 GB, restores can lose recent data, backup password unrecoverable. | User. | Conspicuous data-loss exclusion plus in-flow honesty (the backup password screen already says "Seam can't recover it"). |
| R15 | **Supply chain.** A bad Seam release reaches every server (architecture 2.4). | User, then Seam. | Can't be disclaimed away in practice; it is a reason for an LLC and insurance, and for staged rollout. Terms say updates are best effort and can fail. |
| R16 | **Minors.** Railway 16+ [S19]; WhatsApp and Signal 13+ [S10][S11]; COPPA covers services directed to under-13s or with actual knowledge [S23]. Minors can generally disaffirm contracts (background). | Seam. | Setup requires a card and a Railway contract: require 18+ for the server owner. Family accounts created by the owner are the owner's responsibility. |
| R17 | **Export controls and sanctions.** Seam and the bridges contain encryption; publicly available open-source encryption source code is generally outside the EAR, with the email notice to BIS dropped for most cases by a later rule (search results [S24], UNVERIFIED: confirm current 15 CFR 742.15(b) and 734.3(b)(3)). Sanctioned-country use is barred by Railway's own regime anyway. | Seam (low). | One clause in the terms; a lawyer check, not a UI notice. |
| R18 | **Third-party pieces Seam relies on.** Push notifications go through `push.fluffychat.im` (a gateway Grayson does not run, architecture 2.4); optional backups to Google Drive or OneDrive. | User (metadata to the gateway; storage provider terms). | Privacy policy must list them. |
| R19 | **Platform action against Seam.** Cease-and-desist, CFAA or contract claims, DMCA 1201 theories (background; Beeper Mini precedent with Apple [S25]). | Seam. | Not a user disclaimer: a terms clause letting Seam remove a network at any time without liability, and an internal response plan. |

---

## 2. Where each disclaimer goes

### 2.1 Layering rule

Each notice has three layers:

1. **In-flow line** (one or two sentences, plain English) on the screen where the risk becomes
   real.
2. **"Learn more" link** to a plain-language explainer page (website, also bundled in the app so it
   works offline).
3. **Terms clause** in the Seam Server Terms (section 3 gives both short and long copy).

Consent types:

- **Clickwrap (affirmative):** an unticked checkbox or a button whose label says what is agreed,
  with the terms link right beside it. Courts enforce these most reliably; "browsewrap" (a footer
  link) and weak "sign-in wraps" fail more often (background: *Meyer v. Uber* 2d Cir. 2017,
  *Berman v. Freedom Financial* 9th Cir. 2022, verify). Georgia additionally wants exculpatory
  terms prominent [S16].
- **Tap-through acknowledgment:** a sheet with an "I understand" button, used per network.
- **Passive notice:** text on screen, no action required.

### 2.2 Placement map (setup flow, `server-setup-flow.html`)

| Step (mockup label) | Notice | Type | Copy ref |
|---|---|---|---|
| 1 Offer setup | What Seam is and isn't: you own it, Railway hosts and bills, Seam sends updates best effort, you may need to troubleshoot yourself, Seam earns a share, cost is an estimate. **Terms acceptance** with an unticked checkbox: "I'm 18 or older and agree to the Seam Server Terms and Privacy Policy." Button stays disabled until ticked. | Clickwrap | C1, C2, C3, C5, C6, C12 |
| 1 Offer setup, cost card | "Estimate" label on the "$3 to 6" row; "Seam earns a share of what you pay Railway" directly under "Paid to: Railway". | Passive, but next to the recommendation [S6] | C5, C6 |
| 2 Railway sign-in sheet | Above the sheet (Seam chrome, not inside Railway's page): "This is Railway's page. Your Railway account follows Railway's terms." Before "Approve Seam", a Seam line stating what access Seam gets, worded to match the real OAuth scope. | Passive | C7, C8 |
| 3 Add a card / Hobby | "You pay Railway directly. Seam never sees your card. Railway sets the price and can change it. We suggest a spending limit." Repeat of the troubleshooting line (Grayson asked for it at the plan step). | Passive | C5, C12 |
| 4 Create the server | None needed. Optional "Seam will keep updating this server (you can turn that off)". | Passive | C3 |
| 5 Choose your address | Already says it can't change. Add: "A free Railway address can't come with you if you move hosts. Use your own domain if you might." | Passive | C13 |
| 6 Connect your networks | **Per-network risk sheet** the first time each network is linked: unofficial, ban risk (network-specific), not affiliated, messages decrypted on your server. "I understand, link WhatsApp" button. Re-shown if the risk text version changes. Experimental-tier bridges (architecture `tier`) get an extra line. | Tap-through, per network | C9, C10, C11 |
| 7 Ready (to be redrawn) | "Seam's Railway access: On (change)"; "Updates: from Seam, best effort"; link "What Seam does and doesn't do". | Passive | C3, C8 |

### 2.3 Placement map (lifecycle, `server-lifecycle.html`)

| Screen | Notice | Type | Copy ref |
|---|---|---|---|
| Server home | Footer link "What Seam does and doesn't do" and "Help" (new **Server > Help** row) | Passive | C3, C12 |
| Server > Help (new) | Troubleshooting expectation, where to look (Railway dashboard, logs, `railway ssh`), support channels and that help is best effort. | Passive | C12, C14 |
| Server offline | Keep current honest copy; add "Alerts can be late or missed." | Passive | C15 |
| Networks list | "Experimental" tag on experimental bridges; "Not affiliated" line at list foot. | Passive | C9 |
| Add network (Telegram "Add", etc.) | Same per-network sheet as setup step 6. | Tap-through | C9, C10, C11 |
| Re-link WhatsApp | None new (already explains why). | | |
| Updates, Update available | "Seam tests updates but can't promise every network keeps working." | Passive | C3 |
| Automatic updates (toggle) | With access on: variant (a). When the user turns auto-updates or access off: variant (b) text appears inline. | Passive | C3, C4 |
| Update rolled back, "Send details to Seam" | Before sending: what is sent (redacted logs), who sees it. Per send. | Tap-through | C16 |
| Backups / backup password | Keep "Seam can't recover it"; add "Backups can fail; check they're running." On choosing Google Drive/OneDrive: "Stored under that company's terms." | Passive | C17 |
| Restore | Already honest. | | |
| Move or export | "After you move it, Seam stops updating it and you run it yourself." Address warning. | Passive | C4, C13 |
| Billing | Kickback line again; "Estimates. Railway's bill is final." | Passive | C5, C6 |
| Payment failed | Already right (Seam can't take payment). | | |
| Alerts | "Best effort, can be late or missed" in alert settings. | Passive | C15 |
| Seam's access | Scope stated accurately (see headline 5); variant (b) for "access off". | Passive | C4, C8 |
| Delete server | "Seam keeps no copy. Once deleted on Railway, it's gone." | Passive, plus existing type-to-confirm | C18 |

The AI assistant is deferred past v1 (Grayson, 2026-11-26); its placement and copy are in
section 9 and are not part of this map.

### 2.4 Outside the flows

| Place | Contents |
|---|---|
| **Settings > About > Legal** | Seam Server Terms; Privacy Policy; "Networks and trademarks" (affiliation notice, list of marks); "How Seam makes money" (kickback); Open-source licenses (the existing Flutter license page) plus **Source code** link to the exact tagged source of the app and of the server image; Support and contact. Also a record view: "You accepted Terms v1.0 on Nov 26, 2026." |
| **Google Play listing** | Short description: no third-party names in the title or icon (Play IP and Misrepresentation policies [S14][S26]). Full description: Matrix client first; "optional bridges to other networks run on your own server"; "Seam is not affiliated with or endorsed by WhatsApp, Meta, Google, Signal, Telegram, Discord, Slack, LinkedIn or X"; "Uses the Telegram API" (Telegram 2.2 [S7]); "How Seam earns money: a share of Railway hosting fees from servers set up through Seam" (Telegram 3.2 [S7], FTC). Privacy policy URL and Data safety form. |
| **Microsoft Store listing** | Same text; 10.1.1 requires the listing to describe "any important limitations" and not "mislead customers as to its ... relationship to other products" [S9]. Privacy policy URL (10.5 [S9]). |
| **Website** | Home/hosting page: same layered lines next to the Railway call-to-action; full terms; privacy; "Networks and risks" explainer per network; support page; self-hosting guide (supports the "service of convenience" framing). |
| **Seam Server Terms / Privacy Policy** | Full clauses (section 3 long copy, section 4 outlines). |

### 2.5 Consent record-keeping

Seam has no server of its own in the required path (architecture goal 2), so consent has to be
recorded somewhere Seam doesn't run. Proposal:

- **On the user's own server:** a Matrix account-data event on the owner account, e.g.
  `net.graysons.seam.consent`, holding `{terms_version, privacy_version, accepted_at, app_version,
  platform, network_acks: {whatsapp: {text_version, at}, ...}, assistant_ack: {...}}`. Survives
  phone changes and export.
- **On the device:** the same record in local storage, so the gate works before the server exists
  (step 1 happens before deploy).
- **In the repo:** every released version of the terms, the risk sheets and the setup screens
  (screenshots per release) kept under version control, so Seam can show what a user saw for a
  given version. This is what usually wins enforceability disputes.
- **Optional receipt (lawyer question):** a minimal acceptance receipt to a Seam endpoint (random
  install ID, version hash, timestamp, no identity). Gives Seam its own evidence but adds a
  Seam-run component and personal data; decide with counsel.
- Re-prompt when a material version changes; never silently roll forward the acceptance.

---

## 3. Draft copy

Short copy (C-numbers) is in-app text. Long copy is for the Seam Server Terms. Tone: plain,
specific, no "we are not liable for anything" walls in the UI. Long clauses that limit liability
must be set in their own headed section and visually distinct (Georgia prominence rule [S16]).

### 3.1 Ownership and what Seam is (C1)

**Short:** "Your server runs in your own Railway account, so you own it and you're in charge of it.
Seam is a free tool that sets it up and helps you run it."

**Long:** *Your server, your responsibility.* The server Seam sets up is created in your Railway
account and belongs to you. You are its operator. You decide who uses it, what it connects to and
what data it keeps, and you are responsible for using it lawfully, including for messages from
other people that your server stores. Seam does not host, operate or have custody of your server or
its data. Seam provides software and setup tools as a convenience; you can run the same open-source
software yourself without Seam.

### 3.2 Service of convenience, self-host option (C2)

**Short:** "Everything Seam installs is open source. You can run it yourself instead, and you can
export your server and leave at any time."

**Long:** *Convenience, not a hosting service.* Seam Server is an optional convenience that
automates setting up and maintaining open-source software on infrastructure you rent from Railway.
You are not paying Seam. Paying Railway buys computing resources from Railway; it does not buy a
service, warranty or support commitment from Seam. The source code for the Seam app and the server
image is available at [source URL], and instructions for running it yourself are at [URL].

### 3.3 Maintenance, variant (a): RECOMMENDED for the default (C3)

**Short (setup step 1 and Updates):** "Seam sends tested updates to your server automatically. We
try hard, but we can't promise every update works or that every network keeps working."

**Long:** *Updates.* While Seam's access to your Railway project is on, Seam may publish and install
updates to your server's software, including security fixes, on the schedule you choose. Updates
are provided on a best-effort basis. Seam does not promise that updates will be released on any
schedule, will fix any particular problem, will succeed, or will keep any network working. An update
can fail, roll back, or cause data loss. Seam may stop publishing updates for any network, or
altogether, at any time, and will try to give notice in the app when it does. Seam's decision to
publish updates is not a promise to keep doing so.

### 3.4 Maintenance, variant (b): use for access-off and self-hosted states (C4)

**Short (access off / auto-updates off):** "With Seam's access off, your server keeps running but
gets no updates from Seam. Keeping it patched is up to you."

**Short (after export/move):** "Once you move your server, you run it yourself. Seam doesn't update
or support it there."

**Long (if Grayson chose (b) as the whole offering):** *No maintenance.* Seam sets up your server
once. Seam does not maintain, patch, monitor, back up or support your server after setup. You are
responsible for keeping its software up to date and secure.

**Why (a) for the default, (b) only for those states:**

- The default design installs Seam releases automatically, with rollback (architecture goal 3,
  lifecycle Updates screens). A terms clause saying "no maintenance" would contradict the product
  and invite a deception claim; disclaimers do not override a misleading net impression (FTC Act
  section 5, background).
- Railway's publishing terms make Seam, as template publisher, commit to Railway "You'll maintain
  it ... and you answer questions" [S4]. That is a duty owed to Railway, not to users, but (b)
  would be inconsistent with it.
- (a) keeps the honest limit: best effort, no schedule, may stop, may fail.
- Watch the EU: the Digital Content Directive makes traders ensure consumers are "informed of and
  supplied with updates, including security updates" and terms excluding that are "not binding on
  the consumer" [S27]. Another reason for US-only launch.

### 3.5 Railway cost and payments (C5)

**Short (step 1 cost card):** "Estimate. Railway bills you directly and its bill is final."
**Short (step 3):** "You pay Railway, not Seam. Seam never sees your card. Railway sets prices and
can change them. We suggest setting a spending limit."

**Long:** *Payments and costs.* All hosting charges are between you and Railway under Railway's
terms. Seam does not charge you, does not process your payment details and cannot refund Railway
charges. Cost figures shown in Seam are estimates based on typical use and Railway's published
prices on the date shown; your actual charges depend on your usage and Railway's pricing and may be
higher. You are responsible for all Railway charges, including those caused by updates, backups,
storage growth or a malfunction.

### 3.6 Kickback disclosure (C6)

**Short (step 1, directly under the cost card, and in Billing):** "Seam earns a share of what you
pay Railway, through Railway's template program. It doesn't add to your bill."

(UNVERIFIED: "doesn't add to your bill" assumes the kickback comes out of Railway's revenue and
the user's price is the same with or without the template. Confirm with Railway before using
that half sentence.)

**Store listings / website:** "How Seam earns money: Railway pays Seam a share of hosting fees from
servers set up through Seam."

**Long:** *How Seam is paid.* Seam participates in Railway's template kickback program. Railway pays
Seam a percentage of the usage charges for servers deployed from Seam's template, currently between
15% and 25%. Seam therefore benefits when your Railway usage is higher. Seam recommends Railway
because [reason], not because of this payment, and you may host the same software elsewhere.

### 3.7 Railway as a third party (C7)

**Short (sheet header):** "This is Railway's page. Your Railway account is between you and Railway,
under Railway's terms."

**Long:** *Railway.* Railway Corporation is an independent company and not Seam's agent. Your use of
Railway is governed by Railway's terms, acceptable use policy and privacy policy. Railway may
restrict, suspend or delete your services or account, including for running software it considers
against its policies, and Seam cannot prevent or reverse that. Seam is not responsible for Railway's
availability, pricing, security, data handling or decisions.

### 3.8 Seam's Railway access (C8)

**Short (before "Approve Seam"):** "Seam asks Railway for access to create your server and keep it
updated. [Exact scope sentence, e.g. 'Railway shows this as access to your workspace.'] You can turn
it off in Seam or in Railway's Account Settings > Apps."

Do not ship "Seam can only see the one project it created" unless the OAuth scope actually limits it
to that project (architecture U2).

**Short (access off):** see C4. Also: "Turning access off here also removes the key your server uses
to update itself." (Only if the design does that; otherwise say "Your server still installs Seam
updates on its own until you turn off automatic updates.")

**Long:** *Access you grant.* If you approve Seam in Railway, the Seam app on your devices and the
software on your server use that access only to set up, update, back up, restore, report cost for,
and delete your Seam server. Seam's developer does not receive or store your Railway credentials on
any Seam-operated system. You can revoke access at any time; features that depend on it stop
working.

### 3.9 Per-network risk sheet (C9, C10, C11)

Shown before the first link of each network. Title: "Before you link WhatsApp".

**C9 (all networks, base text):** "Seam connects to WhatsApp through open-source software that
isn't made or approved by WhatsApp. Seam isn't affiliated with WhatsApp or Meta."

**C10 (ban risk, network specific):**

| Network | Line | Basis |
|---|---|---|
| WhatsApp | "WhatsApp's terms don't allow unofficial apps, and WhatsApp can suspend or permanently ban accounts it finds suspicious. New accounts and VoIP numbers are riskier." | [S10][S13] |
| Facebook Messenger, Instagram | "Meta's terms don't allow unofficial apps. Meta may lock your account until you verify it, or restrict it." | [S13] (Meta "may decide your account has suspicious activity and block you until you do some tasks") |
| Signal | "Signal's terms don't allow unofficial use. This links Seam as one of your Signal devices." | [S11] |
| Telegram | "Telegram allows third-party apps, but may flag brand-new accounts used this way." | [S7][S13] |
| Discord | "Discord's terms don't allow unofficial software or automation on user accounts, and Discord may ban accounts it finds suspicious." | [S12][S13] |
| Google Messages | "This pairs like Messages for Web, through software Google doesn't make or approve. Google could stop it working." | UNVERIFIED: Google Messages terms not fetched |
| Slack, LinkedIn, X | "[Network]'s terms may not allow unofficial apps, and it may restrict your account." | UNVERIFIED: terms not fetched |
| Experimental tier, any | Extra line: "This network is experimental in Seam and may lose messages or stop working without notice." | architecture `tier` |

**C11 (privacy, all networks):** "To show these chats in Seam, your server decrypts them. Anyone who
controls your server (you, and Railway as the host) could read them. Your contacts haven't agreed to
Seam."

Button: **"I understand, link WhatsApp"**. Secondary: "Not now".

**Long:** *Connecting other networks.* Bridges are open-source programs that act as unofficial clients
of third-party messaging services. Those services have not authorized them, and using a bridge may
violate their terms. A service may at any time restrict, suspend or permanently ban your account,
block the bridge, or change in ways that stop it working, and Seam cannot prevent, predict or undo
that. You choose whether to connect each service and you accept these risks for each one. Seam may
add, change or remove support for any service at any time without liability, including at a
service's request. Seam is not affiliated with, endorsed by or sponsored by any of these services.
Names of services are used only to identify them and are the trademarks of their owners.

*Privacy of bridged messages.* Messages on many services are end-to-end encrypted. To show them in
Matrix, your server decrypts them and stores them on your server. They are then protected by your
server's security and, in encrypted Matrix rooms, by Matrix encryption; in unencrypted rooms they are
stored in plain text. Your server's host can technically access your server. Your contacts on other
services have not agreed to their messages being stored on your server; you are responsible for
handling their messages lawfully and respectfully.

### 3.10 Troubleshooting skills (C12), Grayson's added theme

Confirmed: Railway offers shell access into a running service with `railway ssh` ("Open an
interactive shell session inside a deployed Railway service container"), using an SSH key registered
with Railway [S21]. Railway's dashboard has service logs and variables (the architecture already
relies on variables for admin recovery).

**Short, before setup (step 1):** "Seam makes setup easy, but this is a real server. If something
goes wrong, you may need to use Railway's dashboard, read logs, or open a command line on your
server to fix it."

**Short, at the plan step (step 3):** "Paying Railway buys the server, not support. Some problems
can only be fixed by you, in Railway."

**Short, Server > Help:** "Most problems have a button here. Some don't: then you may need Railway's
dashboard (logs, settings) or a shell into your server with `railway ssh`. Our help is best effort,
with no guaranteed response."

**Long:** *Technical responsibility.* Seam simplifies setup and routine tasks, but your server is
real software running on infrastructure you control. Seam cannot fix every problem from the app.
Some problems may require you to use Railway's dashboard, read logs, change settings or variables, or
open a command-line session into your service (for example with Railway's `railway ssh` tool), or to
get help from someone who can. Any guidance Seam provides, including from the assistant, is best
effort and may be incomplete or wrong. Seam is not responsible for problems you cannot resolve, or
for the results of commands you or anyone helping you run on your server.

### 3.11 Address and moving (C13)

**Short:** "Your server's name is permanent. A free Railway address can't come with you if you move;
your own domain can."

### 3.12 Support scope (C14)

**Short (Help and About):** "Seam is made by one person. Help is through [GitHub issues / Matrix room /
Railway's template page] and is best effort. Seam can't recover banned accounts on other networks."

**Long:** *Support.* Seam may offer help through public channels and Railway's template question queue.
Support is provided on a best-effort basis with no promised response time, service level or
outcome. Seam cannot help with your accounts on Railway or on other messaging services, including
restrictions or bans.

### 3.13 Availability and alerts (C15)

**Short:** "Your server can go offline, and alerts can be late or missed. Don't rely on Seam for
emergencies; keep your other apps for anything urgent."

**Long:** *No guarantee of availability.* Seam Server is provided without any uptime commitment.
Messages may be delayed, lost, duplicated or delivered out of order. Status information and alerts
are best effort. Do not rely on Seam Server for emergency, safety-critical or time-sensitive
communication.

### 3.14 Diagnostics (C16)

**Short (before "Send details to Seam"):** "This sends recent server logs to Seam's developer, with
passwords and message text removed. It may include your server's address, network names and error
details." Buttons: "Send" / "Cancel". (Confirm the redaction claim against the implementation.)

### 3.15 Backups (C17)

**Short:** "Backups can fail; Seam will tell you when it notices. Keep your backup password safe:
without it no one, including Seam, can restore your data." When choosing Drive/OneDrive: "Backups are
stored under Google's (or Microsoft's) terms."

### 3.16 Deletion (C18)

**Short:** "Seam keeps no copy of your server. Once Railway deletes the project, it's gone."

### 3.17 AI assistant (C19): deferred, see section 9

### 3.18 As-is and limitation of liability (terms only, own headed section)

**Long (outline wording, for counsel to finalize):**

*DISCLAIMER OF WARRANTIES.* SEAM SERVER, THE SEAM APP AND ALL UPDATES ARE PROVIDED "AS IS" AND "AS
AVAILABLE", WITHOUT WARRANTIES OF ANY KIND, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
NON-INFRINGEMENT, AND ANY WARRANTY THAT ANY NETWORK CONNECTION WILL WORK, THAT YOUR ACCOUNTS ON OTHER
SERVICES WILL NOT BE RESTRICTED, OR THAT DATA WILL NOT BE LOST. SOME STATES DO NOT ALLOW THESE
EXCLUSIONS, SO THEY MAY NOT APPLY TO YOU.

*LIMITATION OF LIABILITY.* TO THE EXTENT PERMITTED BY LAW, SEAM [LLC] IS NOT LIABLE FOR INDIRECT,
INCIDENTAL, SPECIAL, CONSEQUENTIAL OR PUNITIVE DAMAGES, LOSS OF DATA OR MESSAGES, LOSS OF ACCOUNTS ON
THIRD-PARTY SERVICES, OR HOSTING CHARGES, AND ITS TOTAL LIABILITY IS LIMITED TO [$100 / THE GREATER OF
$50 AND AMOUNTS SEAM RECEIVED IN CONNECTION WITH YOUR SERVER IN THE PRIOR 12 MONTHS].

Comparable caps: WhatsApp "the greater of one hundred dollars ($100) or the amount you have paid us
in the past twelve months" [S10]; Railway the same structure [S19]. Note Seam's "amount you paid us"
is $0 by design; a lawyer should say whether tying the cap to kickbacks received is better than a
flat figure.

---

## 4. Terms of Service and Privacy Policy outlines

### 4.1 Seam Server Terms (outline)

1. Who we are (Seam [LLC], Georgia, contact); what these terms cover (the Seam app's server
   features, the template, updates, assistant). Relationship to the app's AGPL license (license
   governs the code; these terms govern the service).
2. Eligibility: 18+, United States residents at launch, not in sanctioned countries; must hold a
   Railway account in good standing.
3. What Seam Server is: convenience tooling; user owns and operates (3.1, 3.2).
4. Railway: separate company, payments, costs, estimates (3.5, 3.7).
5. How Seam is paid: kickback (3.6).
6. Access you grant, and revoking it (3.8).
7. Updates (variant (a) 3.3), and what changes when access is off (3.4).
8. Connecting other networks: risks, no affiliation, trademarks, Seam may remove networks (3.9).
9. Technical responsibility and troubleshooting (3.10).
10. Backups, export, moving, deletion (3.11, 3.15, 3.16).
11. (Reserved: assistant clause, added when the assistant ships; section 9.)
12. Support (3.12); availability (3.13).
13. Your responsibilities: lawful use, other people's data, family accounts, security of your
    credentials, compliance with Railway and third-party terms, no spam or abuse (mirror Railway AUP
    so a Railway violation is also a breach here).
14. Open source and source code availability.
15. Disclaimer of warranties (3.18), own heading, distinct type.
16. Limitation of liability (3.18), own heading, distinct type.
17. Indemnity: keep narrow (claims arising from the user's violation of law or third-party terms).
    Broad consumer indemnities are often unenforceable or look overreaching (lawyer question).
18. Disputes: governing law Georgia; venue the user's county or Grayson's county; small-claims
    carve-out; whether to use arbitration and a class-action waiver (lawyer question; consumer
    arbitration usually makes the business pay most arbitration fees, which is a real cost risk for
    a solo developer facing mass filings).
19. Changes to the terms: notice in app, re-acceptance for material changes, version shown.
20. Ending: user can stop at any time (delete or revoke); Seam can discontinue Seam Server with
    notice where practicable; what survives; export window.
21. Misc: entire agreement, severability, assignment (lets the terms move to an LLC), no waiver,
    notices, Consumer Review Fairness Act compliance (no gag clauses, background).

### 4.2 Seam Privacy Policy (outline)

Principle: Seam's developer processes very little; the user's server is the user's.

1. Who is responsible: Seam [LLC] for the app and the few Seam-run pieces. **The user is responsible
   for their own server**; Seam is not the operator. Railway processes data for the user under
   Railway's privacy policy and DPA.
2. Data on the device: Railway OAuth tokens (device secure storage), Matrix session, consent record.
3. Data on the user's server (not accessible to Seam's developer): messages, media, bridge sessions,
   backups, project token. Stated plainly with the E2EE point (3.9).
4. Data Seam's developer may receive:
   - Diagnostics the user chooses to send (C16).
   - (When the assistant ships: relay text, model provider, retention; section 9.)
   - Optional off-device watcher (server hostname, push endpoint; architecture 2.4), opt-in.
   - Template-queue questions (via Railway).
   - Kickback reporting from Railway: what Railway shares with template publishers (UNVERIFIED: check
     the template metrics docs `scratchpad/rw/templates_metrics.md` and Railway's publisher terms for
     whether publishers see user identities).
   - Website analytics if any.
5. Third parties: Railway, push gateway (`push.fluffychat.im`, operator and data sent: event IDs
   only with `event_id_only`, verify), Google Drive/OneDrive if chosen, the AI provider, GitHub
   (images, manifest, issue tracker), app stores.
6. No sale or sharing for advertising; no tracking SDKs (verify the FluffyChat fork has none).
7. Children: not for under 18 to set up; not directed to children under 13 (COPPA [S23]).
8. Retention and deletion (Play's account-deletion requirement [S18]: decide what "Seam account"
   means; probably the in-app Matrix account deactivation plus a web page explaining how to delete
   the Railway project).
9. Security; breach notification approach.
10. US state rights: CalOPPA requires a posted policy for any operator collecting PII from
    California residents regardless of size (background); CCPA thresholds (about $25M+ revenue, or
    100k+ consumers) are almost certainly not met at launch (background, UNVERIFIED current
    adjusted figures). The `privacy-us` skill can audit the final text.
11. Changes and contact.

### 4.3 What's enforceable for consumers

- **US generally:** as-is and consequential-damage exclusions are usually enforced in consumer
  software terms if conspicuous and properly accepted; "some states don't allow" language is
  standard (Railway uses it [S19]). Exclusions can't excuse fraud, gross negligence or wilful
  misconduct in most states (background). FTC Act section 5 and state UDAP laws (Georgia Fair
  Business Practices Act, O.C.G.A. 10-1-390 et seq., background) override fine print: the in-app
  claims ("you own it", "Seam can't see your messages", "doesn't add to your bill", cost estimates)
  must be true and substantiated.
- **Georgia specifically:** exculpatory and limitation clauses must be "explicit, prominent, clear
  and unambiguous"; courts look for their own paragraph and heading and distinct typeface [S16]. A
  2024 Georgia Supreme Court case (S23G0771) on a home inspector's consumer liability cap appears to
  have gone against enforcement; UNVERIFIED, holding not read. Lawyer question.
- **New Jersey** (TCCWNA) penalizes consumer terms that violate clearly established rights, and
  has scrutinized "some states" phrasing (background, verify). Counsel should check.
- **EU/EEA:** Unfair Contract Terms Directive 93/13 (terms excluding liability for death or
  injury, or inappropriately excluding consumer rights, are presumptively unfair, background); the
  Digital Content Directive applies where the trader supplies a digital service and the consumer pays
  a price or "provides or undertakes to provide personal data" [S27], imposes an update duty [S27]
  and makes contrary terms "not binding on the consumer" [S27]; GDPR applies to offering services
  to EU residents and would need an EU representative (background). WhatsApp in the EEA is a
  different contracting entity with different terms [S10].
- **UK:** Consumer Rights Act 2015 gives non-excludable rights for digital content and services with
  reasonable care and skill (background).
- **Recommendation:** launch US-only. Restrict Play and Microsoft Store availability for the server
  feature to the US (both stores support per-country availability), state the US-only scope in the
  terms, and revisit after counsel advises on EU/UK.

---

## 5. App-store policy check

### 5.1 Google Play

| Policy | Text | Effect on Seam |
|---|---|---|
| Device and Network Abuse [S28] | "We don't allow apps that interfere with, disrupt, damage, or access in an unauthorized manner ... servers, networks, application programming interfaces (APIs), or services"; common violation: "Apps that access or use a service or API in a manner that violates its terms of service." | **The main listing risk.** The bridges run on the user's server, not in the app, which helps, but the app's per-network login UI is the user-facing part of accessing those services. A disclaimer does not cure this; a prominent "this may violate WhatsApp's terms" in the store listing could even be cited as an admission. Keep the store listing about Matrix; keep network risk copy in-app. Beeper is listed on Play with WhatsApp and others [S29], which shows tolerance but no safe harbor. Option to reduce risk: the network catalog comes from the server (architecture: `GET /bridges` catalog from the image), so the store binary need not hard-code network brands. |
| Intellectual Property [S14] | "Don't use another party's trademarks, such as logos or brand names without permission"; confusion can lead to suspension. | No third-party names in title, icon or screenshots' prominent areas; initials badges, not logos; affiliation line in description. |
| Misrepresentation [S26] | Apps must not "misrepresent or conceal their ownership or primary purpose"; "Don't hide or misrepresent your identity or who owns the app." | Developer name and the kickback disclosure in the listing; accurate description of what's hosted where. |
| User Data / Prominent Disclosure [S18] | Disclosure "Must be within the app itself", "Cannot only be placed in a privacy policy or terms of service"; privacy policy link in Console and in app; account deletion in-app and outside the app. | The per-network C11 privacy line and the assistant C19 notice are in-app disclosures in this sense. Decide the account-deletion answer. Data safety form: data sent to the user's own server is a judgment call (lawyer or Play support question). |
| Payments [S30] | Play billing is required for apps "accepting payment for access to in-app features or services", examples include "cloud software and services"; apps "may not lead users to a payment method other than Google Play's billing system" including in "account creation or sign-up flows". US changes since Oct 29, 2025 allow external links/alternative billing under enrolled programs [S31]. | **Open question.** Seam takes no payment, the user pays Railway for Railway's compute on Railway's site, but the setup flow sends users to Railway's plan page and Seam is paid a share. Argument it's outside Play billing: payment is to an independent provider for its own service, like a cloud-console client. Argument it's inside: Seam's in-app feature requires it and Seam profits. Ask Play policy support or counsel; the US external-offers program [S31] is the fallback. |
| AI-Generated Content [S20] | Covers chatbots "in which interacting with the chatbot is a central feature"; requires in-app reporting. | Not relevant to v1 (assistant deferred). When it ships: probably out of scope (helper, not central); add "Report a response" anyway (section 9). |

### 5.2 Microsoft Store (Policies 7.20, updated 2026-09-15 [S9])

| Policy | Text | Effect |
|---|---|---|
| 10.1, 10.1.1 | Metadata must "accurately and clearly reflect the source, functionality, and features"; describe "any important limitations"; must not "mislead customers as to its ... relationship to other products". | Supports putting the limitation and affiliation lines in the listing. |
| 10.1.6 | "If your product uses, accesses, monetizes access to, or displays content from a third-party service, ensure that you are specifically permitted to do so under the service's terms of use." | Applies to **standalone storefronts** only, so not directly to Seam; but it shows Microsoft's stance. Low direct risk, note for reviewers. |
| 10.5 | Privacy policy required if the product "accesses, collects or transmits Personal Information"; consent rules for publishing PI to third parties, including people who are not customers. | Privacy policy URL; the bridged contacts' data point (they are not customers) is worth counsel's look. |
| 10.8.3 / 10.14 | Individual accounts "cannot require financial information for primary functionality" (financial info includes "API secret keys"); company accounts required for "any person acting in relation to their trade or profession" or if the publisher name reads as a business. | Railway OAuth is probably not "financial information", but earning kickbacks likely makes this trade activity: plan on a company account, which needs an entity. |
| 11.2 | Content must be original, licensed or "used as otherwise permitted by law". | Nominative use of network names; no logos. |

### 5.3 Telegram API terms (store-relevant) [S7]

- 2.2: users "must be aware of the fact that your app uses the Telegram API", featured prominently
  in store descriptions and any in-app intro.
- 2.3/2.4: no "Telegram" in the title unless "Unofficial", no official logo.
- 3.2: mention all monetization methods in store descriptions (covers the kickback).
- 4.2: non-compliance can end API access and Telegram "may also contact app stores".
- Open question: the bridge uses mautrix's or the user's own `api_id`; whose app is "your app" for
  these terms (lawyer or Telegram question).

---

## 6. Precedents

| Product | What they say | Quote and source |
|---|---|---|
| mautrix docs (the bridges Seam ships) | Per-network ban warnings, matter-of-fact | WhatsApp: "WhatsApp is known to ban accounts that are too suspicious. Just using the bridge shouldn't cause any bans, but getting banned is more likely when combining the bridge with other suspicious activity (running WhatsApp in an Android emulator, using VoIP numbers, using a newly created account, initiating DMs to non-contacts, etc)." Telegram: "Telegram is known to ban suspicious users, and a brand new account using a 3rd party client is considered suspicious." Discord: "Discord may ban users who are too suspicious." Meta: "Meta may decide your account has suspicious activity and block you until you do some tasks like completing a captcha". [S13] The upstream READMEs carry no warnings (checked 2026-11-26). |
| mautrix docs, encryption | Bridge decryption and host trust | "In unencrypted rooms, events are stored in plaintext in the homeserver database"; local hosting "to ensure your cloud provider can't see messages". [S17] |
| Element (ESS) | Contract clause on third-party dependence | "the use and availability of certain parts of the Service may be dependent on third-party product vendors and service providers, (ii) these third-party products and services may not operate in a reliable manner all of the time and they may impact on the way that the Service operates, and (iii) Element shall not be responsible for damages and losses due to the operation of these third-party products and services." (clause 5.5); bridges defined as "functionality allowing connectivity with third party services". [S32] Good model for the long clause in 3.9. |
| Beeper | Terms are thin on network risk; help pages reassure | Terms (last updated July 16, 2025) incorporate Automattic's terms and do not address bans or affiliation [S33]. Instagram help: "This is typically a security checkpoint, not an account ban" and "As long as you're using your account normally ... you'll be fine." [S34] Self-host docs: "Self-hosting bridges are not entitled to the usual level of customer support." [S35] **Don't copy the reassurance:** Beeper is a funded company that negotiates with platforms; Seam can't promise "you'll be fine". Beeper's 13+/16+ EEA age line is in its terms [S33]. Beeper also lost iMessage when Apple blocked it [S25]. |
| etke.cc (managed Matrix hosting) | Silent | Legal page is Portuguese company and consumer info only, no warranty, SLA or bridge text [S36]; bridges help page has no warnings [S37]. Shows the managed-hosting norm is minimal; not a model for Seam, which carries more risk with no contract-negotiated customers. |
| Railway | Model for third-party and as-is wording | "When you access third-party websites or use third-party services, you accept that there are risks in doing so, and that Railway is not responsible for such risks." Liability cap and "SOME STATES DO NOT ALLOW" language. [S19] |
| Telegram | Rules for unofficial clients | See 5.3 [S7]. |
| WhatsApp brand | Referential use | Use the name to describe "as long as it's clear that WhatsApp doesn't endorse or sponsor your project"; no logos without permission. [S15] (The referential-use permission on that page is framed for books and plays; for apps rely on nominative fair use, a lawyer question.) |

---

## 7. For the lawyer

### 7.1 Open questions

1. **Platform exposure:** Does offering per-network login UI and a template that runs unofficial
   clients expose Grayson to contract (inducement), CFAA, or DMCA 1201 claims from Meta, Google,
   Discord, LinkedIn or X? What should the cease-and-desist playbook be (Power Ventures)?
2. **Railway AUP:** Does the template violate Railway's "bots or scrapers that violate applicable
   terms of service" rule? Should Seam get Railway's written OK first? What happens to users if
   Railway removes the template?
3. **Play Payments:** Does sending users to Railway's paid plan, with a revenue share to Seam,
   require Play billing or enrollment in the US external-offers program?
4. **Entity and accounts:** LLC before launch? Single-member LLC in Georgia vs elsewhere; does it
   change Play/Microsoft account type (company account, D-U-N-S); does the kickback make this a
   business for tax purposes (it does, background: Schedule C or LLC)?
5. **Liability cap:** Flat figure or tied to kickbacks received? Georgia enforceability given the
   prominence rule and the 2024 Supreme Court case S23G0771 (confirm holding).
6. **Arbitration:** Use it, or courts with small-claims carve-out, given mass-arbitration fee risk?
7. **Data roles:** Is Seam a processor (or "service provider") for any user data, given the manager
   pulls Seam's manifest, the optional watcher, diagnostics and the assistant relay? Do the bridged
   contacts' messages create duties for Seam or only for the user?
8. **Consent evidence:** Is on-device plus user's-server consent recording, with versioned
   screenshots in the repo, enough, or should Seam keep its own acceptance receipts?
9. **Kickback disclosure wording:** Is "doesn't add to your bill" accurate and safe? Is in-flow
   placement enough under 16 CFR 255?
10. **Maintenance language:** Does publishing automatic updates create an implied duty to keep doing
    so, or liability for a bad update (supply chain), despite best-effort wording?
11. **Trademarks:** Nominative use of network names in UI and listing; and clearance of the name
    "Seam" itself (other tech companies use it, e.g. a smart-lock API company; UNVERIFIED conflict).
12. **AGPL:** Exact source-offer mechanics for the server image and the app; whether Seam's manager
    must be AGPL; whether user-modified servers trigger section 13 duties Seam should warn about.
13. **Export controls:** Confirm no notification or classification filing is needed for the app
    and server image under current EAR 742.15(b) and 740.17.
14. **Minors and family accounts:** 18+ owner rule; owner-created accounts for teens or children.
15. **Insurance:** Tech E&O and cyber cover for a solo developer; cost and whether it covers platform
    claims.

### 7.2 Minimum viable legal setup before the first paying user

- [ ] Written answer from Railway on whether bridge templates are permitted (headline 2).
- [ ] Form an LLC (or decide not to, with counsel); business bank account; assign app, domain,
      template, store accounts and GitHub org to it; terms name the LLC.
- [ ] Seam Server Terms and Privacy Policy, lawyer-reviewed, versioned, hosted on the website and
      bundled in the app.
- [ ] Clickwrap at setup step 1 (unticked box, 18+, terms and privacy links); per-network risk
      sheets; consent record as in 2.5.
- [ ] Fix the two inaccurate mockup statements (headline 5) and match access copy to the real scope.
- [ ] Kickback disclosure on the offer screen, billing screen, store listings and website.
- [ ] Store listings: no third-party marks in title or icon, affiliation line, Telegram API line,
      monetization line, privacy URL, Data safety form, US-only availability for the server feature.
- [ ] Settings > About > Legal page with terms, privacy, trademarks, how Seam earns money, licenses
      and exact-version source links for app and server image.
- [ ] Server > Help page with the troubleshooting line, `railway ssh` pointer and support channels.
- [ ] Cease-and-desist plan: who receives notices (an address in the terms), and the ability to drop
      a network from the catalog in one release.
- [ ] Confirm the factual claims the UI makes: "Seam never sees your card", "Seam keeps no copy",
      log redaction, cost estimate basis, "doesn't add to your bill".
- [ ] Insurance quote.

### 7.3 LLC: why it matters here

- Separates personal assets from business debts and contract claims, which matters most for the
  supply-chain risk (a bad update across every server) and platform claims. It does not shield
  Grayson from his own torts or anything he personally guarantees, and courts can disregard it if
  finances are mixed (background).
- Microsoft Store and likely Google Play want an organization account for trade activity [S9];
  that needs an entity.
- Georgia LLC formation and annual registration fees are modest (UNVERIFIED: check the Georgia
  Secretary of State's current fee schedule).

---

## 8. Sources

All fetched 2026-11-26 unless noted.

| Ref | Source | URL |
|---|---|---|
| S1 | Railway Acceptable Use Policy | https://railway.com/legal/acceptable-use |
| S2 | Railway docs, Trust and safety (local snapshot `scratchpad/rw/platform_trust-and-safety.md`) | https://docs.railway.com/platform/trust-and-safety |
| S3 | Railway docs, Template kickbacks (local snapshot `rw/templates_kickbacks.md`) | https://docs.railway.com/templates/kickbacks |
| S4 | Railway docs, Publish and share, "Publishing terms" | https://docs.railway.com/templates/publish-and-share.md |
| S5 | 16 CFR 255.5 (via Cornell LII; eCFR redirected to a bot wall) | https://www.law.cornell.edu/cfr/text/16/255.5 |
| S6 | FTC, Endorsement Guides: What People Are Asking | https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking |
| S7 | Telegram API Terms of Service | https://core.telegram.org/api/terms |
| S8 | Railway docs, Authorized apps (local snapshot `rw/integrations_oauth_authorized-apps.md`) | https://docs.railway.com/integrations/oauth/authorized-apps |
| S9 | Microsoft Store Policies v7.20 (ms.date 2026-09-14) | https://learn.microsoft.com/en-us/windows/apps/publish/store-policies |
| S10 | WhatsApp Terms of Service (non-EEA, effective Jan 4, 2021) | https://www.whatsapp.com/legal/terms-of-service |
| S11 | Signal Terms and Privacy | https://signal.org/legal/ |
| S12 | Discord Terms of Service (effective Dec 15, 2026, updated Nov 23, 2026) | https://discord.com/terms |
| S13 | mautrix docs (repo cloned, last commit Nov 23, 2026): `bridges/go/whatsapp/authentication.md`, `telegram/authentication.md`, `discord/authentication.md`, `meta/authentication.md` | https://github.com/mautrix/docs (rendered at https://docs.mau.fi/bridges/) |
| S14 | Google Play, Intellectual Property policy | https://support.google.com/googleplay/android-developer/answer/9888072 |
| S15 | Meta, WhatsApp brand resources | https://www.meta.com/brand/resources/whatsapp/whatsapp-brand/ |
| S16 | Georgia exculpatory-clause rule: Warren Averett v. Landcastle (Ga. Ct. App. 2019) and commentary (search results; secondary sources) | https://law.justia.com/cases/georgia/court-of-appeals/2019/a18a2117.html ; https://justice.org/resources/publications/professional-negligence-law-reporter/inconspicuous-contract-damages-provision-unenforceable ; 2024 case: https://cases.justia.com/georgia/supreme-court/2024-s23g0771.pdf (not read) |
| S17 | mautrix docs, End-to-bridge encryption | https://docs.mau.fi/bridges/general/end-to-bridge-encryption.html |
| S18 | Google Play, User Data policy | https://support.google.com/googleplay/android-developer/answer/10144311 |
| S19 | Railway Terms of Service (effective 2026-04-20) | https://railway.com/legal/terms |
| S20 | Google Play, AI-Generated Content policy | https://support.google.com/googleplay/android-developer/answer/13985936 |
| S21 | Railway docs, `railway ssh` | https://docs.railway.com/cli/ssh.md |
| S22 | Railway docs, Private Docker images (local snapshot `rw/templates_private-docker-images.md`) | https://docs.railway.com/templates/private-docker-images |
| S23 | FTC, COPPA Rule page | https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa |
| S24 | Encryption source-code notification change (search results: Baker McKenzie, WSGR, BIS) UNVERIFIED | https://www.wsgr.com/en/insights/us-department-of-commerces-bureau-of-industry-and-security-relaxes-several-classification-and-reporting-requirements-for-encryption-items.html ; https://www.bis.gov/node/6731 |
| S25 | MobileSyrup, Beeper disables iMessage after Mac bans (search result, not opened) | https://mobilesyrup.com/2024/01/29/beeper-disables-imessage-connections-following-mac-bans/ |
| S26 | Google Play, Misrepresentation policy | https://support.google.com/googleplay/android-developer/answer/9888689 |
| S27 | Directive (EU) 2019/770 (Digital Content Directive), Arts 3(1), 8(2), 22(1) | https://eur-lex.europa.eu/eli/dir/2019/770/oj/eng |
| S28 | Google Play, Device and Network Abuse policy | https://support.google.com/googleplay/android-developer/answer/9888379 |
| S29 | Beeper on Google Play (title only confirmed) | https://play.google.com/store/apps/details?id=com.beeper.android |
| S30 | Google Play, Payments policy | https://support.google.com/googleplay/android-developer/answer/9858738 |
| S31 | Google Play, US programs after the Epic injunction (search result summary; terms in flux after a March 2026 settlement) UNVERIFIED detail | https://support.google.com/googleplay/android-developer/answer/15582165 |
| S32 | Element Software and Services License Agreement (UK), PDF | https://static.element.io/legal/element-software-and-services-license-agreement-uk-1.pdf |
| S33 | Beeper Terms of Service (last updated July 16, 2025) | https://www.beeper.com/terms |
| S34 | Beeper help, Instagram | https://help.beeper.com/instagram |
| S35 | Beeper developers, self-hosting bridges | https://developers.beeper.com/bridges/self-hosting |
| S36 | etke.cc legal page | https://etke.cc/legal/ |
| S37 | etke.cc bridges help | https://etke.cc/help/bridges |

Background items (not fetched this session, verify before relying): Facebook v. Power Ventures
(9th Cir. 2016); New Kids on the Block v. News America (9th Cir. 1992); Toyota v. Tabari (9th Cir.
2010); Meyer v. Uber (2d Cir. 2017); Berman v. Freedom Financial (9th Cir. 2022); hiQ v. LinkedIn;
Van Buren v. US (2021); AGPL-3.0 sections 6, 13, 15, 16 (https://www.gnu.org/licenses/agpl-3.0.html);
Georgia FBPA O.C.G.A. 10-1-390; NJ TCCWNA; EU Directive 93/13; GDPR Arts 3(2), 27; UK Consumer Rights
Act 2015; CalOPPA; CCPA thresholds; Consumer Review Fairness Act; Google Messages, Slack, LinkedIn and
X terms.

---

## 9. When the assistant ships (deferred, not part of v1)

Grayson deferred the bridge-setup AI assistant to a later version (2026-11-26). Nothing in this
section applies to v1. When it ships, add the following to the placement map, terms and privacy
policy.

**Risk (R9):** model output can be wrong; the Seam-run relay "sees assistant conversation text
(bridge help output, error text)" and never credentials by design (architecture 2.4); a third-party
model provider also processes that text.

**Placement:** first use of the assistant, a tap-through sheet shown once and again if its text
changes, recorded in the consent record (2.5) as `assistant_ack`. A persistent "Report a response"
action in the chat (Play AI-Generated Content policy asks for in-app reporting where a chatbot is
"a central feature" [S20]; probably not central here, but it is cheap).

**Short copy (C19):** "The assistant helps set up networks. It never needs your passwords; never type
one here. What you type and your server's error messages go to Seam's relay and to [model provider]
to answer you. It can be wrong; check before you act." Buttons: "Start" / "Not now".

**Terms clause:** *Assistant.* The optional assistant uses a third-party AI model through a
Seam-operated relay. Text you enter and diagnostic information from your server that you choose to
share are sent to the relay and the model provider to generate responses [retention terms].
Responses are generated automatically and may be inaccurate. Do not enter passwords, verification
codes or other people's private messages. You are responsible for actions you take based on its
responses.

**Privacy policy:** add the relay and the model provider under "Data Seam's developer may receive"
and "Third parties", with retention periods.
