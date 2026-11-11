# GoodLettr – Salesforce Take-Home Assessment

**Candidate:** Sneha Bhattacharjee
**Role:** Business Systems Analyst
**Org:** GoodLettr Developer Edition (a reviewer user will be created on request)

This README covers what I built, how to review it, my assumptions, design decisions, shortcuts, and how and where I used AI. The full AI prompt log is in the [`prompts/`](prompts/) folder.

---

## 1. Overview

GoodLettr's growing sales team needed one place to track a letting agency from first enquiry to paying customer, and to keep track of what each customer owes.

| Task | What I built |
|---|---|
| **1. Enquiry → active, billable customer** | Web-to-Lead form, rule-based lead scoring, standard lead conversion, agency hierarchy (head office + branches, each branch with its own contact), one primary contact per agency, usage-based pricing (£ per tenancy per month), contract PDF and email, automatic Opportunity stages, and on Closed Won: Account set to **Active**, Service Contract and Order created |
| **2. Branch report of tenancies and amount owed** | Order invoicing (**Send Invoice** emails a £ invoice PDF and moves the Order to **Billed**), payment status (**Billing Processed**), and the report **Billed Orders – Amount Owed by Branch** |
| **3. Lead scoring** | 147 configurable scoring rules in Custom Metadata, evaluated by a Flow against the enquiry and call notes, producing a **Lead Score (0–100)** and a **Lead Score Reason**, with field history so reps can see how and why a score changed |

---

## 2. How to review it (demo path)

Demo data includes several agency groups, for example **Northern Keys Lettings Group** (branches in Leeds and Liverpool), **Harbourside Lettings**, **Peak View Property Management** and **Thameside Residential**.

1. **Enquiry:** open `web-to-lead/goodlettr-web-to-lead.html` in a browser and submit it. A Lead is created with Lead Source = Web.
2. **Scoring:** open the Lead. **Lead Score** and **Lead Score Reason** are calculated automatically. Add text to **Conversation Notes** and save to see the score update; the change appears in **Lead History**.
3. **Qualify:** move the Lead along its Path (Open → Working), or mark it Disqualified if the agency drops off.
4. **Convert:** convert the Lead. An Account (agency), Contact and Opportunity are created. Number of Branches maps to the Account and Number of Tenancies to the Opportunity. The Account starts as **Draft**, is flagged **Is Primary Account**, and its contact becomes the **primary contact**.
5. **Branches:** on a head-office Account, click **Add Branches**. Add each branch (name, phone, address, and a contact with name and email), then **Finish**. All branches and contacts are created together, and Number of Branches updates automatically. **View Account Hierarchy** shows the group.
6. **Primary contact:** on any Contact, click **Make Primary**. For a branch contact, a confirmation explains that the primary contact is held at agency level.
7. **Pricing:** on the Opportunity, add **Tenancy Management Software**. Quantity, price and total are calculated from tenancies, billing frequency (Monthly / Quarterly / Annual) and Discount %.
8. **Contract:** click **Generate Contract PDF** (stage → Proposal/Price Quote), then **Send Contract Email** (stage → Negotiation/Review). The sent PDF is saved to the Opportunity's Files.
9. **Close:** set the Opportunity to **Closed Won**. The Account becomes **Active**, and a 12-month **Service Contract** and a **Draft Order** are created with lines copied from the Opportunity.
10. **Invoice:** on the Order, click **Send Invoice**. The invoice PDF is emailed and saved, and the Order moves to **Billed**.
11. **Report:** open **Reports → Billing → Billed Orders – Amount Owed by Branch** to see the amount owed per branch.

---

## 3. Data model

| Object | Type | Purpose |
|---|---|---|
| **Lead** | Standard | An enquiry, before we know whether the agency will buy. Custom fields: Number of Branches, Number of Tenancies, Enquiry Notes, Conversation Notes, Lead Score, Lead Score Reason |
| **Lead_Score_Rule__mdt** | Custom Metadata | Scoring rules (phrase, points, category, field, score-once, disqualify, active) |
| **Account** | Standard | The agency. Head office = top-level Account; each branch = child Account (standard **Parent Account**). Custom fields: Status (Draft / Active / Inactive), Number of Branches, Branch Email, Primary Contact, Is Primary Account, Is Top-Level Agency |
| **Contact** | Standard | A point of contact. **Is Primary** marks the agency's main contact |
| **Opportunity** | Standard | The deal, once commercial terms are being discussed. Custom fields: Number of Tenancies, Contract Generated On, Contract Sent On |
| **Product / Price Book Entry** | Standard | **Tenancy Management Software**, a usage product at **£2.00 per tenancy per month** |
| **Opportunity Product** | Standard | Quantity = tenancies; Billing Frequency; Discount % |
| **Service Contract + Contract Line Items** | Standard | The agreed commercial terms after signing (12-month term) |
| **Order + Order Products** | Standard | What is billed. Statuses: Draft → Billed → Billing Processed. Invoice Number, Invoice Date, Due Date, Payment Received On |

---

## 4. Automation and components

| Component | Type | What it does |
|---|---|---|
| `goodlettr-web-to-lead.html` | Web-to-Lead form | Captures name, agency, email, phone, branches, tenancies and enquiry details |
| `Lead_Calculate_Lead_Score` | Record-triggered Flow (after save) | Scores each Lead from the rules: whole-word matching, negation handling ("not ready to switch" doesn't count), call notes weighted ×1.5, one match per category, disqualifiers, score kept between 0 and 100; updates only when the result changes |
| `GoodLettrTextCleaner` | Invocable Apex | Removes line breaks from the notes before scoring (Flow can't handle them) |
| Lead conversion mapping | `mdapi/leadConvertSettings` | Number of Branches → Account; Number of Tenancies → Opportunity |
| **Add Branches** | Quick action (LWC `goodlettrAddBranches` + Apex `GoodLettrBranchService`) | Adds several branches, each with a contact, in one all-or-nothing save, with validation and duplicate warnings. Only shown on head-office Accounts |
| `AccountBranchCountTrigger` | Apex trigger | Keeps Number of Branches and Is Primary Account correct when branches are added, removed or moved |
| **Make Primary** | Quick action (LWC `goodlettrMakePrimary` + Apex `GoodLettrPrimaryContactService`) | One primary contact per agency group, held on the head office |
| `ContactPrimaryTrigger` | Apex trigger | The first contact on a head-office Account becomes primary automatically (including after lead conversion); branch contacts never do |
| `OLI_Tenancy_Usage_Pricing` | Record-triggered Flow (before save) | Quantity = tenancies; price = £2.00 × months in the billing period × (1 − Discount %) |
| **Generate Contract PDF / Send Contract Email** | Quick actions (LWC + Visualforce `GoodLettrContract` + Apex) | Contract with commercial terms; emails it to a contact and saves the sent PDF to Files |
| `Opportunity_Contract_Stage_Automation` | Record-triggered Flow (before save) | PDF generated → Proposal/Price Quote; contract sent → Negotiation/Review; never moves a deal backwards |
| `Opportunity_Closed_Won_Service_Contract_and_Order` + `GoodLettrClosedWonService` | Flow (after save) + invocable Apex | On Closed Won: Account (and branches) → **Active**; creates the Service Contract and Order with their lines; never creates duplicates |
| **Send Invoice** | Quick action (LWC `goodlettrSendInvoice` + Visualforce `GoodLettrInvoice` + Apex `GoodLettrInvoiceService`) | Emails the invoice PDF, saves it to Files, sets Invoice Number/Date/Due Date and moves the Order to **Billed** |
| **Billed Orders – Amount Owed by Branch** | Report (Billing folder) | Billed Orders grouped by agency/branch with total amount owed |
| **Open Pipeline by Stage** | Report (Sales Pipeline folder) | Open Opportunities by stage for sales managers |
| Permission sets | `Agency_Hierarchy`, `GoodLettr_Contracts`, `Lead_Scoring`, `Lead_Conversion_Fields`, `Product_Billing_Fields` | Access to the custom fields, actions, Apex and pages. Assign all of them to review the full solution |
| Apex tests | One test class per service | All tests pass |

---

## 5. Assumptions

- **When to convert:** a Lead is converted when commercial terms start being discussed, as described in the brief. Before that, it stays a Lead (Open → Working), or is marked Disqualified if the agency drops off.
- **Primary branch:** the **head office (top-level Account) is the primary branch**. The agency's main contact is the primary contact held on the head office. If a branch contact is made primary, they become the main contact for the whole agency.
- **Single-branch agencies** are one Account with no child Accounts. They can become a head office later by adding branches.
- **Every branch has its own point of contact**, created with the branch in Add Branches.
- **Active customer:** an agency becomes **Active** when its Opportunity is Closed Won (terms agreed and signed). New Accounts start as **Draft**.
- **Pricing:** a flat **£2.00 per tenancy per month**, billed monthly, quarterly or annually, with an optional discount. Prices exclude VAT; VAT is out of scope for now.
- **Contract signing** happens outside Salesforce (no e-signature tool in the org), so the rep sets Closed Won manually once the signed contract is returned.
- **Tenancies billed:** invoices use the number of tenancies on the Order, which comes from the Opportunity. In production this would be the actual number of tenancies processed in the billing period, supplied by the GoodLettr platform.
- **Finance system:** Send Invoice stands in for a billing system. In production, the finance system would set **Billing Processed** and **Payment Received On** by matching the Order's Invoice Number (an external ID).
- **Currency:** GBP, single currency.

---

## 6. Key design decisions and trade-offs

| Decision | Why | Trade-off / alternative considered |
|---|---|---|
| **Standard lead conversion** plus a separate **Add Branches** action | Simpler for reps and keeps standard Salesforce behaviour; branches are added only when needed | A custom conversion flow with a branch child object could capture branches up front, but adds complexity and custom code |
| **Account hierarchy (Parent Account)** for head office and branches | Standard, needs no setup, and gives the built-in hierarchy view | Roll-ups across a hierarchy need automation (handled by `AccountBranchCountTrigger`) |
| **One primary contact per agency group, held on the head office** | Matches "the primary branch's contact is the main contact for the agency" | Branch contacts can still be promoted, with a confirmation |
| **Is Top-Level Agency formula** controls where Add Branches appears | Salesforce doesn't allow a visibility rule on Parent ID; a Parent Name check only works while Account sharing is public | One extra formula field and permission set access |
| **Usage pricing without CPQ** | The brief needs a simple per-tenancy charge; CPQ / Revenue Cloud would be excessive | Billing frequency and discount are handled by a Flow |
| **Lead scoring with Flow + Custom Metadata** (not Apex, not Einstein) | Declarative and configurable: sales ops can change phrases and points without a deployment. Einstein Lead Scoring needs historical conversion data, which a new org doesn't have, and can't read free text | Keyword rules can miss natural wording (see Known limitations). Apex is used only for cleaning line breaks |
| **Score reason + field history** | Reps can see *why* a lead scored as it did, and how it changed after a call | The reason field is short text so history can track it; very long reasons are truncated |
| **Net price copied to contract and order lines** | Prevents the discount being applied twice | The discount is kept in a separate field for reference |
| **All-or-nothing saves and no duplicates** (Add Branches, Closed Won) | Data stays consistent if anything fails or a deal is re-closed | Closing a deal fails if the Service Contract or Order can't be created |
| **Apex only where Flow can't cope** | Declarative first; code is used for PDFs, email with attachments, cross-hierarchy counts, multi-record creation and line-break cleaning | More components to maintain than a Flow-only design |

---

## 7. Shortcuts and known limitations

| Area | Shortcut / limitation | What I'd do in production |
|---|---|---|
| Contract signing | Closed Won is set manually | Integrate an e-signature tool to move the stage automatically |
| Billing | Send Invoice simulates the billing system; one Order is created per contract, so only its first billing period can be invoiced | Integrate the finance system and create an Order or usage record per billing period |
| Tenancies processed | Invoices use the tenancy quantity on the Order, not actual usage | Receive actual tenancies processed per branch per period from the GoodLettr platform |
| Amount-owed report | Shows amounts owed per branch, not the tenancy count and rate on each line | Add tenancy count and rate columns (Orders with Order Products) |
| Lead scoring | Keyword rules can miss natural phrasing (for example "in a renewal process with our current vendor") and produce a score and reason but no suggested next step | Hybrid scoring: keep rules for structured data (tenancies, branches) and add a Prompt Builder / Agentforce prompt that reads the free text and returns a rating, reason and suggested next step, with rep override |
| Enquiry sources | The web form sets Lead Source = Web; phone and referral enquiries are entered manually | Add Phone and Referral sources and a **Referred By** link to the existing customer |
| Disqualified leads | No reason captured when a lead is disqualified | Add a required Disqualified Reason for reporting |
| Discounts | Discount % has no limit or approval | Threshold-based approval process (for example over 10% to a manager, over 25% to a director) |
| Web form | No reCAPTCHA; the thank-you page is a placeholder | Enable reCAPTCHA and set the real return page |
| Pipeline report | Amount mixes monthly, quarterly and annual billing periods | Add an annual contract value field for comparable totals |
| Old action | `Create Child Agency` remains in the metadata but is replaced on the page by Add Branches | Remove it |

---

## 8. How and where I used AI

**Tools**
- **Claude Code** (in VS Code, connected to the Salesforce CLI) to build the solution in the org.
- **Claude** (chat) to understand the brief, review the build against the requirements and plan improvements.

**What AI did**
- Generated and deployed metadata: fields, layouts, permission sets, flows, quick actions, reports, the web form, Apex classes and tests, LWCs and Visualforce pages, and test data.
- Proposed options and explained platform constraints (for example that Flow can't handle line breaks, or that visibility rules can't check Parent ID).
- Produced the design-decisions document in `docs/`.

**What I did**
- Defined the requirements for each step and made the design decisions. For example, I:
  - **rejected** a custom lead-conversion flow in favour of standard conversion plus a conditional branch action;
  - **challenged** the extra formula field and permission set, then kept the formula once we confirmed the alternative depended on public sharing;
  - chose **usage** pricing over recurring, and added Discount %;
  - chose **Flow + Custom Metadata** for scoring instead of an Apex scorer, and asked for the reason field and history;
  - chose a **new Status field** rather than repurposing an existing one;
  - defined the primary-contact rules, the branch details to capture, and the invoicing statuses.
- Tested each feature in the org and checked the results.

**What I'd do differently:** give the AI the full brief at the start and check the build against it after each step, rather than working feature by feature. That would have caught gaps such as actual tenancy usage and referral tracking earlier.

---

## 9. AI prompts

All prompts are included, unedited:

| File | Contents |
|---|---|
| `prompts/claude-code-export.txt` | Full export of the Claude Code session(s) |
| `prompts/session-prompts.md` | My prompts to Claude Code, in order, with the outcome of each |
| `prompts/claude-chat-prompts.md` | My prompts to Claude (chat) about the exercise |
| `docs/GoodLettr_Prompt_Log_and_Design_Decisions.docx` | Summary of prompts and design decisions (generated during the build; the export above is the complete record) |

---

## 10. Repository structure and deployment

```
force-app/main/default/   Salesforce metadata (objects, flows, Apex, LWC, pages, layouts, reports, permission sets)
mdapi/leadConvertSettings Lead conversion field mapping (deployed separately)
web-to-lead/              Web-to-Lead form
prompts/                  AI prompt logs
docs/                     Design decisions document
```

Deploy:

```bash
sf project deploy start -o <org-alias>
sf project deploy start --metadata-dir mdapi/leadConvertSettings -o <org-alias>
```

Then assign the five permission sets to the users who need them.
