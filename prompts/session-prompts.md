# GoodLettr – Session Prompts (2026-11-09)

Prompts given to Claude Code in this session, in order, verbatim.

## 1. Connect to org and create Web-to-Lead form

> Connect to GoodLettr org from my SF CLI . Create a Web to lead form involving the firstname , lastname , Name of the Agency, Email , Phone number , Number of Branches and Number of Tenancies.

Outcome: CLI was already connected to the `GoodLettr` org (default). Form created at `web-to-lead/goodlettr-web-to-lead.html` using Company (Name of the Agency), `Number_of_Branches__c` (00Nak00005ftxwX) and `Number_of_Tenancies__c` (00Nak00005fseb1). Verified with one test submission, which was then deleted.

## 2. Create test leads

> create some test leads for this web-to-lead form do not delete them

Outcome: 5 leads submitted through the Web-to-Lead endpoint and kept (emails `@example.com`):
00Qak000010QvgTEAS, 00Qak000010QvYPEA0, 00Qak000010QairEAC, 00Qak000010Qva1EAC, 00Qak000010QvbdEAC.

## 3. Lead fields for a head office / branch account hierarchy

> Now Given a scenario that I need to have multiple accounts(agencies) if account(agencies) is present at multiple location and a single one would be headquarter rest would be child of that what details I should additionaly capture on the lead to design the custom lead conversion flow
>
> Save all the prompts given in this session I will need it

Outcome: this file was created, and lead-capture recommendations for the hierarchy conversion flow were given in the chat.

## 4. Single-branch agencies

> There is also a chance that and single agency would only be created for this lead conversion as it has only got one branch
> Keep saving all of my prompts for this session for reference later

Outcome: the design was extended with a third case, Independent (single office). The picklist became Agency Structure = Independent / Head Office / Branch of existing agency. Independent converts to one standalone Account with no parent and no child Accounts, and can be promoted to a head office later. Validation rules and the conversion decision tree were given in the chat.

## 5. Use standard lead conversion plus a conditional "Create Child Agency" quick action

> Discard this approach we will go with standard lead conversion and if the rep needs to create child agencies he will have the option to create child agency from a quick action on the account record form page make this quick action conditional

Outcome: the custom conversion flow design (prompts 3–4) was dropped. Leads now go through standard lead conversion.

Visibility condition chosen: **only when the Account has no Parent Account** (top-level agencies only).

## 6. Go-ahead

> Go ahead

Outcome: deployed to the GoodLettr org:
- `Account.Is_Top_Level_Agency__c`: formula checkbox, `ISBLANK(ParentId)`
- `Account.Create_Child_Agency`: Create quick action (Account) with Parent Account set to the current record; fields Name, Phone, Website, Billing Address
- `Account_Record_Page`: Lightning record page with Dynamic Actions. Create Child Agency is visible only when `Is_Top_Level_Agency__c = true`. Activated as the org default for Account (desktop).
- `Agency_Hierarchy` permission set (read access to the formula field), assigned to snehabhatta2017@goodlettr.com
- Tested through the REST API: the child was created with Parent set and the flag was false; the HQ flag was true. Test Accounts deleted.

## 7. Question: why the formula field and permission set?

> Why do we need the additional formula field and the permission set we can have the check based on dynamic record from quick action based on the parent ID field

Outcome: neither is strictly needed. Validation-only deploys showed that `{!Record.ParentId}` is rejected for EQUAL and NE ("reference field"), and so is `{!Record.Parent.Id}`. `{!Record.Parent.Name}` EQUAL (blank) validates, so it can replace the formula field and permission set. Account sharing default is Public Read/Write, so the Parent Name is never hidden from a rep by sharing. Switching was offered; nothing was changed yet.

## 8. Decision: keep the formula field approach

> Okay if parent ID don't accept the checks of equal go with the formula field approach

Outcome: no change. The deployed design stays as it is: the `Is_Top_Level_Agency__c` formula field, a visibility rule of `{!Record.Is_Top_Level_Agency__c}` = true, and the `Agency_Hierarchy` permission set. Reps who need the button must be assigned the `Agency_Hierarchy` permission set.

## 9. Usage-type product without CPQ/RCA

> Now I want to create a usage type product in Salesforce named as Tenancy management Software where it is charged monthly based on the Number of tenants using the software for their agency without using CPQ or RCA

Price chosen: **$2.00 per tenant per month** (single-currency org, en_US).

Outcome: built with standard objects only:
- Picklist values: Quantity Unit of Measure **Tenant**; Product Family **Software** (StandardValueSet `Product2Family`)
- New Product2 fields: `Charge_Type__c` (One-Time / Recurring / Usage) and `Billing_Frequency__c` (Monthly / Quarterly / Annual), plus a "Pricing & Billing" section on the Product layout
- Permission set `Product_Billing_Fields`, assigned to snehabhatta2017@goodlettr.com
- Product **Tenancy Management Software** (01tak00000YQIAbAAP), code TMS-USG-MTH, Usage / Monthly / Tenant
- Price book entries at $2.00 in the Standard Price Book and in the active "Standard" price book
- Usage model: on an Opportunity, Quantity = number of tenants and Sales Price = $2.00, so Total Price = the monthly charge

## 10. Lead conversion field mapping

> I want the two fields created on lead one the Number of agencies to be copied to account
> and second the number of tenants process to Opportunity
> Modify the mapping fields for leads so that this is handled during lead conversion

Interpretation: "Number of agencies" = Lead `Number_of_Branches__c`; "number of tenants" = Lead `Number_of_Tenancies__c`.

Outcome:
- New fields: `Account.Number_of_Branches__c` Number(3,0) and `Opportunity.Number_of_Tenancies__c` Number(10,0), both added to their page layouts
- Permission set `Lead_Conversion_Fields`, assigned to snehabhatta2017@goodlettr.com
- LeadConvertSettings deployed with the mappings Lead.Number_of_Branches__c → Account.Number_of_Branches__c and Lead.Number_of_Tenancies__c → Opportunity.Number_of_Tenancies__c (the org had no custom mappings before)
- Tested with an Apex convert: 6 branches went to the Account and 3100 tenancies to the Opportunity. Test Lead, Account, Contact and Opportunity deleted.

## 11. Explain the usage product setup

> Share the details of how you did set up the usage product

Outcome: a step-by-step explanation of the setup from prompt 9 (design, metadata, records, commands and limitations) was given in the chat.

## 12. Flow to calculate the Opportunity Product total

> Can you add a flow trigger automation to calculate the total price for that Opportunity when I add this product to Opportunity for this product the charge would be recurring and based on billing frequency and the number of tenancies processed which can be the quantity field the charge would be done

Outcome:
- New field `OpportunityLineItem.Billing_Frequency__c` (Monthly / Quarterly / Annual), added to the Opportunity Product layout and to the `Product_Billing_Fields` permission set
- Before-save record-triggered flow `OLI_Tenancy_Usage_Pricing` (create and update), which applies only to product code TMS-USG-MTH:
  - On create, Quantity = Opportunity.Number_of_Tenancies__c
  - Billing Frequency defaults from the Product, otherwise Monthly
  - Sales Price = $2.00 × months in the period (1/3/12); Total = Quantity × Sales Price
  - Salesforce rejects changes to Sales Price and Total Price in the same save, so the flow branches: create sets Total and clears Sales Price; a Sales Price edit resets Sales Price; any other update sets Total
- Tested with 1,250 tenancies: Monthly $2,500, Quarterly $7,500, Annual $30,000. Quantity edits recalculate the total, and manual Sales Price edits are reset. Test Opportunities deleted.
- Moved the LeadConvertSettings file from force-app to `mdapi/leadConvertSettings/`, because the CLI can't read it in source format. Deploy it with `sf project deploy start --metadata-dir mdapi/leadConvertSettings`.

## 13. Keep Charge Type = Usage; add a discount % on the Opportunity Product

> No it should be usage add a discount percentage field on Opportunity Line Item too if not already there so that if reps want they can discount it

Outcome:
- Product Charge Type left as **Usage** (unchanged)
- The org has no standard Discount field on Opportunity Product, so I created `OpportunityLineItem.Discount_Percent__c` (Percent 5,2) with the validation rule `Discount_Percent_Range` (0–100%). Added to the layout and to the `Product_Billing_Fields` permission set.
- Flow `OLI_Tenancy_Usage_Pricing` updated: net price per tenant per period = $2.00 × months × (1 − Discount/100); Total = Quantity × net price. Sales Price shows the net price; List Price stays $2.00. Note: in flows a Percent field holds 10% as 10 (validation formulas see 0.10).
- Tested with 1,250 tenancies: Monthly 10% → $2,250; Annual 25% → $22,500; a Sales Price edit is reset to the net price; no discount → $2,500; 150% is rejected. Test Opportunities deleted.

## 14. Remove the discount validation rule; note future approvals

> No need to add a validation rule, add in the prompt section note
> That in future we can have a approval rules setup for these discounts based on threshold values

Outcome: the validation rule `OpportunityLineItem.Discount_Percent_Range` was deleted from the org and from the local project. Discount % is now unrestricted.

> **📝 Note (future enhancement): Discount approval rules.**
> Set up approvals on Opportunity Product `Discount_Percent__c` using threshold values (for example ≤10% auto-approved, 10–25% sales manager, >25% sales director). Options without CPQ/Advanced Approvals: a standard Approval Process on Opportunity driven by a roll-up or flow-maintained "Max Line Discount %" field, or Flow Approval Orchestration. Locking the Opportunity or its line items while approval is pending also needs designing.

## 15. Generate Contract PDF and Send Contract Email actions

> Create a generate pdf Quick action which can be used to generate a contract with commercial terms which can be send by GoodLettr to the agencies
> Add a send email button too once the email is sent with the attachment it should be attached to the Opportunities files section

Outcome (deployed to GoodLettr):
- Visualforce page `GoodLettrContract` (renderAs pdf, A4, 2 pages): parties, order details (branches, tenancies, initial term), schedule of charges (charge type, billing frequency, tenancies, rate, discount, charge per period, total excluding VAT), 11 draft commercial terms (usage charges, billing in arrears, 30-day payment, VAT, discount for initial term only, 12-month auto-renewal with 60 days' notice, price changes, late payment, UK GDPR, termination, England & Wales law), and signature blocks. **The terms are a draft for legal review.**
- Custom Labels `GoodLettr_Legal_Name`, `GoodLettr_Registered_Address`, `GoodLettr_Company_Number`. The address and company number are placeholders to update in Setup → Custom Labels.
- Apex: `GoodLettrContractController` (page controller), `GoodLettrContractService` (getSendContext / saveContractToFiles / sendContract), `GoodLettrContractServiceTest` (5 tests pass; coverage 91% / 100%)
- LWC screen quick actions on Opportunity, added to the front of the Opportunity Layout action list:
  - **Generate Contract PDF** (`goodlettrContractPreview`): inline preview, Open in New Tab, Save to Files (saved as "(Draft)")
  - **Send Contract Email** (`goodlettrSendContract`): choose an agency contact (Opportunity contact roles with primary first, then Account contacts with an email), CC, subject and body pre-filled; the PDF is attached; the email is logged on the Opportunity; after sending, the sent PDF is saved to the Opportunity's Files as "(Sent yyyy-MM-dd HH:mm)"
- Permission set `GoodLettr_Contracts` (Apex class and VF page access), assigned to snehabhatta2017@goodlettr.com
- End-to-end test on demo records (kept for trying the buttons): Account "ZZ Demo Lettings Agency", Contact demo.director@example.com, Opportunity 006ak00000iLxOkAAK (1,250 tenancies, Quarterly, 10% discount → $6,750). Draft and Sent PDFs are in Files; EmailMessage logged as Sent with the attachment.
- Note: getContentAsPDF cannot see uncommitted records in the same transaction, so the PDF is only rendered for saved Opportunities. This is normal in the UI.

## 16. Move the Opportunity stage automatically on contract generate/send

> Automated flow to update the stage of Opportunity so that when the Generate contract PDF button is pressed the stage moves to Proposal/Price Quote and when the email is sent the stage moves to Negotiation/Review

Outcome (deployed to GoodLettr):
- New read-only Opportunity fields `Contract_Generated_On__c` and `Contract_Sent_On__c` (Date/Time), added to the Opportunity layout and to the `GoodLettr_Contracts` permission set
- Apex `GoodLettrContractService.markContractGenerated` is called when the Generate Contract PDF action opens. `sendContract` stamps Contract_Sent_On__c after a successful send.
- Before-save flow `Opportunity_Contract_Stage_Automation`:
  - Contract Sent On changed → **Negotiation/Review**
  - Contract Generated On changed → **Proposal/Price Quote** (not if already at Proposal or Negotiation)
  - Closed Opportunities are never changed
- Apex tests: 7 of 7 pass, including tests that the stage moves forward but never backwards and never reopens closed deals
- Live test on the demo Opportunity: Prospecting → Proposal/Price Quote (generate) → Negotiation/Review (send)

## 17. Account status values

> On the account status value have the value as Draft Active and Inactive

Decisions: create a **new** field rather than repurpose `Active__c` (Yes/No, left unchanged); default = **Draft**.

Outcome:
- New restricted picklist `Account.Account_Status__c` (label "Status"): Draft (default) / Active / Inactive. Added to the Account layout and to the `Agency_Hierarchy` permission set (edit).
- Tested: Accounts created through the API, through lead conversion and through the Create Child Agency quick action all defaulted to Draft. Test records deleted.
- The demo Account "ZZ Demo Lettings Agency" was created before the field existed, so its Status is blank.

## 18. On Closed Won, create a Service Contract and an Order

> Currently the Opportunity would be moved to 'Closed Won' manually as we don't have docusign or any other esign app so once we have recieved the sign document rep will manually change the Opportunity to closed won and after that a Service Contract record should be created with the details of the terms with the contract lines copied from Opportunity lines and Order should be created with Order lines

Outcome (deployed to GoodLettr):
- After-save flow `Opportunity_Closed_Won_Service_Contract_and_Order`: runs when StageName changes to Closed Won and calls the invocable Apex `GoodLettrClosedWonService` ("Create Service Contract and Order", category GoodLettr). The Apex is bulk-safe and skips Opportunities that already have a Service Contract, so no duplicates are created.
- **Service Contract**: name "GoodLettr Service Contract - <Agency>", Account, primary contact role, StartDate = Close Date, Term 12 months, EndDate = start + 12 months − 1 day, price book, billing address, and SpecialTerms = commercial terms summary plus a per-line breakdown. **Contract Line Items** copy Quantity, net UnitPrice, Billing Frequency and Discount % (the standard Discount is left blank so the discount isn't applied twice).
- **Order** (Draft): name "GoodLettr Order - <Agency>", linked to the Opportunity and the Service Contract, with the same dates, bill-to contact and billing address. **Order Products** are copied the same way.
- New fields: `ServiceContract.Opportunity__c`; `Order.Opportunity__c` and `Order.Service_Contract__c`; `Billing_Frequency__c` and `Discount_Percent__c` on ContractLineItem and OrderItem. All added to layouts and to the `GoodLettr_Contracts` permission set. Service Contracts and Orders related lists added to the Opportunity layout.
- Tests: `GoodLettrClosedWonServiceTest` (3 tests, 100% coverage), all 10 tests pass. Salesforce resets CloseDate to today when an Opportunity is closed, so contracts start on the day the deal is won.
- Live test: demo Opportunity → Closed Won created Service Contract (2026-11-09 → 2027-11-08, Active) with 1 line and Order 00000100 (Draft, $6,750) with 1 item.

## 19. Add Enquiry Notes to the Web-to-Lead form

> added a new field Enquiry Notes on lead object expose this as a Enquiry details field in the web to lead form

Outcome: added an optional **Enquiry Details** textarea to `web-to-lead/goodlettr-web-to-lead.html`. It posts to `Enquiry_Notes__c` (Text Area 255, field ID 00Nak00005fzeso), with maxlength 255 and a placeholder hint. Tested with a Web-to-Lead submission: the text arrived in Enquiry Notes. Test lead deleted. Enquiry Notes is not mapped on lead conversion.

## 20. Custom lead scoring: which phrases to look for

> Currently we are in a developer Org where we don't have Einstein lead scoring I have added two fields Enquiry notes and the Conversation Notes and a lead score field if we are doing custom lead scoring suggest me phrases that I would be looking for to assign the lead score

## 21. Build lead scoring: metadata rules, a flow, score history and a reason field; required form fields

> A metaddata approach is configurable for scoring so we should go for it
> Instead of apex scorer can we do it in a flow
> Enable change history on lead score and  add a reason field for lead score we should enable change history on that too so that rep can see if a lead score changed and if it changed why it changed
>
> In the form that we generarted we need to make the Enquiry Notes, Last Name,Email, Company ,Phone mandatory on the form

Outcome (deployed to GoodLettr):
- **Custom Metadata Type `Lead_Score_Rule__mdt`**: Phrase, Points, Category, Rule Type (Phrase / Tenancies At Least / Branches At Least / Email Domain / Phone Provided), Applies To (Both / Enquiry Notes / Conversation Notes), Threshold, Score Once per Category, Disqualify, Active. **147 rule records** loaded from the suggestions in prompt 20. Edit them in Setup → Custom Metadata Types → Lead Score Rule → Manage Records; no deployment needed.
- **Flow `Lead_Calculate_Lead_Score`** (before-save, Lead create and update, no Apex): gets the active rules sorted by points (highest first) and loops through them. Phrases match as whole words (lower-cased, punctuation removed). A phrase directly after not/no/dont/never/isnt/arent/wont/without is ignored. Conversation Notes matches get ×1.5 and are tagged "(call)". Score Once per Category keeps only the best match in a category. A Disqualify rule sets the score to 0. The score is clamped to 0–100.
- **New field `Lead_Score_Reason__c`** (Text 255, so history shows old and new values), e.g. "Score 100: +20 contract ends; +20 ready to switch; …". Lead Score is read-only on the layout, with Reason next to it. Lead History related list added.
- **Field history**: enabled history tracking on the Lead object (was off), and tracking on Lead Score and Lead Score Reason. Verified that LeadHistory shows old → new for both.
- Permission set `Lead_Scoring` (read Score and Reason), assigned to snehabhatta2017@goodlettr.com
- **Web-to-Lead form**: Last Name, Email, Company, **Phone** and **Enquiry Details** are required (First Name was already required). This is enforced in the browser only.
- Tests passed: hot lead (100, capped), negation ignored, "trial" not matched inside "industrial", gmail −5, unsubscribe → 0, Conversation weighting ×1.5, history recorded. Test leads deleted.
- **Known limitation**: flow formulas can't refer to line-break characters (tried "\n" escapes, text templates and UNICHAR: none work in flows), so a phrase right next to a line break in the notes is not matched. Proposed fix: a tiny invocable Apex "clean text" helper. Awaiting the user's decision.

## 22. Fix line breaks with an Apex helper

> Okay let's go with the apex to remove the line break

Outcome (deployed to GoodLettr):
- Apex `GoodLettrTextCleaner`: invocable action "Remove Line Breaks" (category GoodLettr). It replaces \r \n \t, non-breaking spaces and Unicode line/paragraph separators with spaces in Enquiry Notes and Conversation Notes. That's all it does; the scoring logic stays in the flow and metadata. Test class `GoodLettrTextCleanerTest`: 2 tests, 100% coverage, including an end-to-end test of scoring across line breaks.
- Flow `Lead_Calculate_Lead_Score` moved from **before-save to after-save**, because before-save flows can't call Apex actions. The steps are: Remove Line Breaks → get rules → loop and score → if the score or reason changed, Update Lead Score. Updating only on change stops the flow re-triggering itself and avoids no-change history entries.
- Live test: multi-line notes now score (68: ready to switch, demo, director, all "(call)"). Other scenarios unchanged (hot 100, negated 0, industrial 5, unsubscribe 0, call update → 88). LeadHistory has one entry per real change; an unrelated edit adds none. Test leads deleted.

## 23. Test agencies: standalone accounts and parent/child groups with Opportunities

> Create some test parent account(agency) record which are stand alone and they have suppose 3 Opportunities One in closed won two in Negotiating
> Create some more  test parent accounts(agency) with child accounts(agencies) with different locations in UK and child accounts having Opportunities in pipe line and closer won statuses

Outcome: created (Description = "GoodLettr test data"; contact emails @example.com; Ofcom drama phone numbers):
- **3 standalone agencies**: Harbourside Lettings (Bristol), Peak View Property Management (Buxton), Thameside Residential (Reading). Each has 3 Opportunities: 1 Closed Won ("Year 1 Subscription") and 2 Negotiation/Review.
- **3 agency groups**, each a head office plus 3 child branches:
  - Northern Keys Lettings Group (Manchester): Leeds, Sheffield, Liverpool
  - Capital & County Residential (London): Brighton, Oxford, Cambridge
  - Celtic Lettings Group (Cardiff): Edinburgh, Glasgow, Belfast
  - Child Opportunities across Prospecting, Qualification, Needs Analysis, Value Proposition, Id. Decision Makers, Proposal/Price Quote, Negotiation/Review and Closed Won
- 15 Accounts, 15 Contacts (primary contact role on each Opportunity), 22 Opportunities each with a Tenancy Management Software line (pricing flow: Quantity = tenancies, price per billing period, discount)
- 7 Closed Won deals were closed the way a rep would close them, so automation created **7 Service Contracts (with lines) and 7 Draft Orders** (00000101–00000107)
- Account Status: Active for agencies with a won deal, and for the head office of any group with a won branch; Draft otherwise

## 24. Export prompts and design decisions to Word

> Export the prompts before this and the design decision taken in a word file

Outcome: Word document `docs/GoodLettr_Prompt_Log_and_Design_Decisions.docx` (A4). It contains a summary; the prompt log (prompts 1–23, quoted exactly, each with its outcome); design decisions in 8 areas with rationale and alternatives; a list of components built; and open items and future enhancements.

## 25. Save the Word document to Downloads

> Save the document in downloads

Outcome: copied to `~/Downloads/GoodLettr_Prompt_Log_and_Design_Decisions.docx`. The project copy in `docs/` is kept.

## 26. Change the price to pounds

> Change the price to pounds

Outcome:
- Org currency checked: **USD**, single-currency (`UserInfo.getDefaultCurrency()`). Price kept at 2.00, so it becomes **£2.00** once the currency is GBP. Single-currency amounts are relabelled, not converted.
- Code deployed (10 of 10 tests pass): the contract PDF shows **£** explicitly (`£{0,number,#,##0.00}`), whatever the user's locale; the Service Contract Special Terms show £ on rates and state "Prices are in GBP (£)". Checked by rendering a PDF (£2.00 / £6,750.00); the test file was deleted.
- **Pending (manual, Setup UI only):** Setup → Company Information → Edit → **Currency Locale = English (United Kingdom) - GBP**. The Currency Locale can't be changed through the Metadata API or the CLI.

## 27. Required fields on the Contact and Account layouts; confirm lead conversion mapping

> Make name and ermail address mandatory on the layout of contact and makre name address and phone  number mandatory for the account layout and confirm if these are mapped during lead conversion

Outcome:
- Changed only Contact Layout and Account Layout: no active users are on the Custom Sales, Marketing or Support profiles, which have their own layouts.
- **Contact Layout:** Name (already required) and **Email** now required.
- **Account Layout:** Name (already required) and **Phone** now required. **Billing Address could not be made required**: Salesforce rejects it ("Field:BillingAddress must not be Required"), because compound address fields can't be required on a layout.
- **Create Child Agency quick action:** Phone and Billing Address set to Required. Through the API, Phone is enforced ("Required fields are missing: [Phone]") but the address is not.
- **Lead conversion mapping (standard, not configurable) confirmed with real conversions:** Lead First/Last Name → Contact Name; Email → Contact Email; Phone → Account Phone and Contact Phone; Company → Account Name; Address → Account Billing Address and Contact Mailing Address; Number of Branches → Account (custom mapping).
- Page layout requirements are **not** enforced during lead conversion: a lead with no address converted successfully. The Web-to-Lead form doesn't capture an address. Test records deleted.
- Decision: **leave the address optional**. No validation rule, and no address fields on the form.

## 28. Open-pipeline report for Sales Managers

> Create a pipe line report for open opportunities for Sales Managers to view

Outcome (deployed to GoodLettr):
- Public group **Sales Managers** (`Sales_Managers`). Members are the roles (without subordinates) SVP Sales & Marketing, VP North American Sales, VP International Sales, Director Direct Sales and Director Channel Sales. The org had no Sales Manager role or group; individual users can be added in Setup → Public Groups.
- Report folder **Sales Pipeline**, shared **View** with the Sales Managers group
- Report **Open Pipeline by Stage** (00Oak00000UN4fxEAD): Opportunity report type, summary format, filtered to open deals (Closed = False), grouped by Stage, with a horizontal bar chart of Amount by Stage. Columns: Opportunity, Account, Owner, Amount (sum), Probability, Expected Revenue (sum), Close Date, Number of Tenancies (sum), Next Step, Contract Sent On, Age.
- Checked through the Analytics API: 15 open deals, £54,304.20 Amount, £44,000.68 Expected Revenue, 4,930 tenancies (the 7 Closed Won deals are excluded).
- Note: Amount is the charge **per billing period** (monthly, quarterly or annual mixed). An annualised value field would make pipeline totals comparable.

## 29. Order billing statuses, Send Invoice action, and an amounts-owed report

> Add a status called billed on the order object and moved the order status to Billed
> generally there will be a billing system to be integrated for now add a quick action called send invoice to the customer once the customer is invoiced the order moves to status billed.
> Next move some of our orders to billed.
> Add another status on order object as Billing processed this would come from Financial system once the amount is recieved from the custmer
> We will then create a report to show Orders which are in billed status grouped by account to show the total amount owed by that branch

> **Status check / decisions:** No need for VAT for now, Yes send invoice should work on draft orders

Outcome (deployed to GoodLettr):
- **Order statuses** added: **Billed** and **Billing Processed**, both in the Activated category. The existing values are Draft and Activated.
- **Order fields:** Invoice Number (external ID, INV-<OrderNumber>), Invoice Date, Invoice Due Date (+30 days), and Payment Received On (for the financial system). Read-only on the Order layout.
- **Send Invoice** quick action on Order (LWC `goodlettrSendInvoice`, Apex `GoodLettrInvoiceService`, PDF `GoodLettrInvoice` + `GoodLettrInvoiceController`). **No VAT** (user decision). Works on **Draft** and Activated Orders (user decision). It needs order products and a Bill To Contact with an email, and blocks Orders already Billed or Billing Processed. It emails the £ invoice PDF to the bill-to contact (logged on the Order), saves the PDF to the Order's Files, and moves the Order to **Billed** with the invoice number and dates.
- Order layout: added an action list (Send Invoice, Edit, Delete, Clone, Post, New Task, Log a Call, New Event). Permission set `GoodLettr_Contracts` extended (invoice classes, page, Order field read access).
- Tests: `GoodLettrInvoiceServiceTest` (3 tests), 13 of 13 passing including the existing classes; coverage 95% service, 100% controller.
- **Orders moved to Billed** with the real Send Invoice logic (5 emails with PDFs sent to @example.com contacts, 5 files saved): 00000101 Harbourside, 00000103 Thameside, 00000104 Leeds, 00000105 Liverpool, 00000107 Edinburgh. Then **00000107 was set to Billing Processed** (Payment Received On = today) to simulate the financial system. 00000100, 00000102 and 00000106 are still Draft.
- **Report** "Billed Orders - Amount Owed by Branch" in a new **Billing** folder (view access for the Sales Managers group): Status = Billed, grouped by Account, sum of Order Amount, bar chart, columns Order Number, Parent Account, Invoice Number, Invoice Date, Due Date, Status, Amount. Current result: 4 Orders, **£8,155 owed** (Harbourside £640, Leeds £960, Liverpool £3,477, Thameside £3,078). Edinburgh is excluded because it's Billing Processed.
- Fixed a spacing glitch in the invoice PDF ("to08 Feb", "by10 December"); invoices already sent keep it.
- **Integration contract for the financial system:** update the Order (match on `Invoice_Number__c`, an external ID) with `Status = 'Billing Processed'` and `Payment_Received_On__c`.

## 30. Primary contact checkbox and Make Primary action

> Create a check box field is primary on Contact and a quick action called make primary on the Contact record page
> We would make that contact primary if the rep clicks on that button and show a toast message
> The other contact if it is primary will be unchecked, If there is one contact on account it is primary for that account if that is  the top account.
> IF somebodey marks a contact primary for a child account we would show a pop up that currently this contact is primary for the top account do you want to make this contact primary for the Top account as no contact should be primary for a contact of a child account

Interpretation: one primary contact per **agency group** (top account plus its branches), held on the top account. Branch contacts can become the group's primary only after confirming.

Outcome (deployed to GoodLettr):
- Fields: `Contact.Is_Primary__c` (checkbox, read-only on the Contact layout) and `Account.Primary_Contact__c` (lookup on the top account, read-only on the Account layout)
- Apex `GoodLettrPrimaryContactService`: getContext / makePrimary (unchecks any other primary in the group, checks this contact, sets the top account's Primary Contact), assignDefaultPrimary, and hierarchy helpers. Runs without sharing so the single-primary rule always applies.
- Trigger `ContactPrimaryTrigger` (after insert): the **only** contact on a **top-level** account becomes primary if the group has none. This also covers lead conversion. Branch contacts are never auto-primary.
- **Make Primary** quick action on Contact (headless LWC `goodlettrMakePrimary`, first in the Contact layout's action list). Top-account contact: immediate, with a success toast naming the previous primary that was unchecked. Branch contact: **LightningConfirm pop-up** ("<current> is currently the primary contact for <Top>. Primary contacts are held at the top account, not at branch level. Do you want to make <contact> (<branch>) the primary contact for <Top>?"), then a toast. Already primary: info toast.
- Permission set `Agency_Hierarchy` extended (service class, read access on both fields)
- Tests: `GoodLettrPrimaryContactServiceTest` (3 tests). All 18 GoodLettr tests pass; coverage 98% service, 100% trigger.
- Backfill: 7 top accounts with a single contact got a primary (Capital & County → Oliver Pemberton, Celtic → Rhys Llewellyn, Harbourside → Grace Whitfield, Northern Keys → Daniel Hargreaves, Peak View → Tom Ashworth, Thameside → Priya Kapoor, ZZ Demo → Demo Director). Branch contacts are not primary.

## 31. Options for making it easier to add child accounts (discussion)

> Now lets think about different approaches about making life easier for reps to add child accounts
> Should we have a multi screen flow on the create chile accounts
> where we caputure details of each account with the location and then once the the user is done they can click on finish or like add more child accounts

Outcome: options compared in the chat (no build yet). Recommendation: a screen-flow quick action using the Flow **Repeater** component (all branches on one screen), plus a review screen, created in one transaction. It replaces the single-record Create Child Agency action.

## 32. Build Add Branches: name, email and address per branch; converted child-agency contacts never primary

> No neeed for branch manager as during lead converion a contact would be created but if the lead is converted for a child agency then that contact doesnot be  ome primary
> We need teh branch email name and address and there name

Decisions: no branch manager contact in the flow. Per branch: **name, email, address** (plus optional phone). Defaults applied: Add Branches **replaces** Create Child Agency on the Account page, and Number of Branches is **automatic** (branches + head office).

Outcome (deployed to GoodLettr):
- New field `Account.Branch_Email__c` (Email), on the Account layout and in the `Agency_Hierarchy` permission set. This org enforces field-level security on Apex DML, so the permission set is required.
- **Screen flow `Add_Branches`** plus the Account quick action **Add Branches** (shown on head offices only, using the existing Is Top-Level visibility rule; it replaces Create Child Agency on the Account Record Page, and the old action still exists as metadata). Steps: check it's a head office → **Repeater** screen (Branch name, Branch email, Branch phone, Street, City/town, Postcode, Country defaulting to United Kingdom; "+ Add Item" for more) → validate → error screen (Back only) or review screen (summary plus duplicate warnings) → create all → done screen.
- Repeater metadata lessons learned: `storeOutputAutomatically` and `inputsOnNextNavToAssocScrn` are not supported on the Repeater itself; loop over `Branches.AllItems`; a visibility rule can't use "Is Blank" on a text variable (use a formula instead); a screen can't have both allowBack and allowFinish set to false.
- Apex `GoodLettrBranchService` (invocable, validate or create): checks name, email format, street/city/postcode, and that the parent is a head office. Warns on duplicate names or postcodes against existing branches and within the list. Creates everything in one insert (all or nothing) with Parent = head office, Status Draft, Number of Branches 1, and postcode in upper case.
- Trigger `AccountBranchCountTrigger`: the head office's Number of Branches = branches + 1, recalculated whenever a branch is added, deleted, restored or moved to another parent.
- Confirmed by a test: a lead converted onto an existing **child agency** creates a contact that is **not** primary, and the head-office primary is unchanged.
- Tests: `GoodLettrBranchServiceTest` (3 tests). All 21 GoodLettr tests pass; 100% coverage on the new class and trigger.
- Live REST test of the action: validate → create 2 branches → head office Number of Branches = 3 → duplicate warnings when re-entered. Test records deleted. The flow screens themselves still need a click-through in the browser.

## 33. Make the Account Active when an Opportunity is Closed Won

> Can we make the account active using a flow once the opportunity is closed won

Outcome (deployed to GoodLettr): added to the existing Closed Won flow `Opportunity_Closed_Won_Service_Contract_and_Order`, after the Service Contract and Order step:
- **Activate Agency**: the Opportunity's Account Status → **Active** (from Draft or Inactive)
- **Activate Head Office**: if the Account has a parent and the head office is still **Draft**, it becomes Active. An **Inactive** head office is left alone.
- Live test: branch and Draft HQ → both Active; Inactive standalone → Active; branch under an Inactive HQ → branch Active, HQ still Inactive. Service Contracts were still created (3). Test records deleted. 12 of 12 related Apex tests pass.

## 34. Branch win activates the top account; Is Primary Account flag on top accounts

> No if a branch deal makes account active, then make the Top account active too and Introduce a flag on the account is primary account to signify that the account is primary only for the top account
> This should also work for lead conversion if only a single account is created no top account exists then flag should automatically gets checked

Outcome (deployed to GoodLettr):
- Closed Won flow: **Activate Top Account** now sets the parent (top) account to Active whatever its status (Draft or Inactive). The agency on the deal also becomes Active.
- New field `Account.Is_Primary_Account__c` (checkbox, read-only on the layout, read access in `Agency_Hierarchy`). It is set by `AccountBranchCountTrigger` (now also before insert/update): **true when the account has no parent**, false for branches. This covers lead conversion (a single new account → checked), Add Branches (branches unchecked), manual creation, and moving an account under or away from a parent.
- Tests: new test for top/branch/reparent/lead conversion. All 22 GoodLettr tests pass; trigger coverage 100%.
- Backfill: all existing accounts updated; flag matches ParentId on every account (0 mismatches).
- Live test: a branch win under an **Inactive** HQ now makes the HQ **Active**. Test records deleted.
- Note: `Is_Top_Level_Agency__c` (formula, used for action visibility) means the same thing; it could later be retired in favour of `Is_Primary_Account__c`.

## 35. Phone and Email required on the Lead layout

> make phone number and email mandatory on the lead layout

Outcome: **Lead Layout** (used by 43 profiles, including both admins) now has Phone and Email set to **Required**; deployed. The Sales, Marketing and Support Lead layouts have no active users. No open leads are missing a phone or email. Layout requirements apply to on-screen edits only: Web-to-Lead and the API aren't affected (the web form already requires both).

## 36. Rework Add Branches: Add more branches / Finish buttons, a contact per branch, JSON held until Finish

> Currently while adding a branch there is no option to add more branches it's just has a previous button
> Have a field like name for this branch wihich is account name then the phone number
> Then a contact person name for that branch and an email capture for that person with the account location details which is already there but there should be button like add more branches and finish if it is done once finished we should have the accounts and the contacts created untill the clicks on finish nothing gets created
> You can store the details in a json and then create at the end

Why the change: a standard flow screen only has Next/Previous/Finish buttons, so it can't offer "Add more branches" and "Finish" together. Add Branches was rebuilt as an LWC screen quick action.

Outcome (deployed to GoodLettr):
- **LWC `goodlettrAddBranches`** (Account quick action **Add Branches**, same visibility on head offices only). Per branch: **Branch name** (the Account name), **Branch phone**, **Contact first/last name**, **Contact email**, **Street, City/town, Postcode, Country** (defaults to United Kingdom).
  - **Add more branches**: validates the form, adds the branch to an on-screen list (edit and remove icons), and clears the form. Branches are held in the browser as a JSON array; **nothing is saved**.
  - **Finish**: includes a filled-in form automatically, sends the JSON to Apex `checkBranches` (errors, or a duplicate-warning confirmation), then `createBranches`.
  - **Cancel** with unsaved branches asks before discarding them.
- Apex `GoodLettrBranchService` rewritten: `getHeadOffice`, `checkBranches(parentId, json)`, `createBranches(parentId, json)` (one Savepoint transaction: insert branch Accounts with Parent, Status Draft and upper-case postcode, then a Contact per branch with email, phone and mailing address; any failure rolls everything back). Duplicate warnings cover branch name, postcode and an existing contact email. `recountBranches` is unchanged.
- The old Repeater flow `Add_Branches` and its flow-based quick action were **deleted** (a quick action's type can't be changed; the flow version was removed with a Tooling API delete).
- Tests: `GoodLettrBranchServiceTest` (4 tests, including rollback when a contact insert fails). All 22 GoodLettr tests pass; 100% coverage on the service.
- Live test: check saved nothing → create made 2 branches and 2 contacts; contacts are not primary; branches are not primary accounts; HQ Number of Branches = 3. Test records deleted.
- **Found in the live test:** Salesforce's standard (alert-only) **duplicate rules** blocked branch inserts, because branch names start with the head office name (for example "X" and "X - Leeds"). Fix: `Database.DMLOptions.DuplicateRuleHeader.allowSave = true` on the account and contact inserts. GoodLettr's own duplicate warnings are confirmed by the rep first, and rules set to Block still block. Tests now use realistic branch names. 22 of 22 tests pass. The live re-run created 2 branches and 2 contacts, HQ Number of Branches = 3; cleaned up.

## 37. A branch contact made primary moves to the top account

> Once a branch contact is made primary that contact should move to the top account and removed from the branch

Outcome (deployed to GoodLettr):
- `GoodLettrPrimaryContactService.makePrimary`: when the contact is on a branch, the same update that sets Is Primary also sets **AccountId = top account**, so the contact moves to the head office and is no longer on the branch. The previous primary is unchecked and the top account's Primary Contact is set, as before.
- Make Primary pop-up now says "<contact> will be moved from <branch> to <top account>", and the success toast confirms the move. The record page refreshes.
- Test updated (moved to top, 0 contacts left on the branch, then reported as already primary). All 22 GoodLettr tests pass.
- Live test: Sophie@Leeds → primary and moved to the HQ, Daniel unchecked, HQ Primary Contact = Sophie, 0 contacts left on the branch. Test records deleted.
- Note: existing Opportunity contact roles, Orders (Bill To) and Service Contracts that reference the contact are unaffected by the move.
