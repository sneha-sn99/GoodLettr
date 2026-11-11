# GoodLettr
## Solution built:- 

1. Lead Source picklist values modified keeping only the required things Web, Phone and Referral from an existing customer.

2. Changed the Account tab's label to Agencies.

3. Changed the Lead Status picklist values to Open and Working, and added Disqualified so reps can disqualify a lead when the agency drops off.

4. Created fields on the Lead: Number of Branches, Number of Tenancies and Enquiry Notes, so we can capture these details from the website form. Also created Conversation Notes for what the rep learns on calls. Enquiry Notes and Conversation Notes are both used for lead scoring.

5. Connected Claude Code with VS Code and linked the Salesforce org for the build. The detailed prompts are shared in a separate file.

6. Created a Web-to-Lead form with First Name, Last Name, Name of the Agency, Email, Phone, Number of Branches, Number of Tenancies and Enquiry Details. Made Last Name, Agency, Email, Phone and Enquiry Details mandatory. (File: `web-to-lead/goodlettr-web-to-lead.html`.)

7. Created test leads through the form to check every field comes through correctly.

8. Created an Account Status field with Draft, Active and Inactive. New agencies start as Draft.

9. Mapped the Lead fields for conversion: Number of Branches → Account and Number of Tenancies → Opportunity. (Branches describe the agency; tenancies drive the deal value.)

10. Add a custom quick action "Add branches" in one single flow with details of agency and contacts.

11. Created the product Tenancy Management Software as a usage product at £2 per tenancy per month.

12. Created a Flow on Opportunity Product to calculate the price automatically.

13. Created a Generate Contract PDF quick action that creates a contract with the commercial terms, and a Send Contract Email quick action that emails it to the agency. The sent PDF is saved to the Opportunity's Files.

14. Created a Flow to move the Opportunity stage automatically: contract PDF generated → Proposal/Price Quote; contract emailed → Negotiation/Review.

15. On Closed Won, a Flow (with Apex) sets the Agency's status to Active, and creates a Service Contract (12 months) and a Draft Order, with the lines copied from the Opportunity. It never creates duplicates if a deal is re-closed.

16. Built lead scoring because the Developer org has no Einstein Lead Scoring:
    - Scoring rules (phrases and points) stored in Custom Metadata, so sales ops can change them without code;
    - a Flow checks the Enquiry Notes and Conversation Notes against the rules and gives a Lead Score;
    - field history is on for the score and reason, so reps can see if a score changed and why. Both fields are read-only.

17. Added a small Apex helper to remove line breaks from the notes before scoring. (Flow can't handle line breaks.)

18. Made Name and Email mandatory on the Contact layout, and Name and Phone mandatory on the Agency layout, and confirmed these map across during lead conversion.

19. Created a report Open Pipeline by Stage for Sales Managers to view open Opportunities.

20. Added Order statuses Billed and Billing Processed. Created a Send Invoice quick action that emails an invoice PDF to the customer and moves the Order to Billed. Billing Processed is set once payment is received (in future, by the finance system).

21. Created a report Billed Orders – Amount Owed by Branch, which groups billed Orders by agency/branch to show the total amount each branch owes.

22. Created an Is Primary checkbox on Contact and a Make Primary quick action. Only one contact per agency group is primary, held on the head office. If a rep makes a branch contact primary, a pop-up asks them to confirm, because the primary contact is held at the top account.

23. Created test agencies across the UK, some single-branch and some with branches, with Opportunities in the pipeline and Closed Won, so the reports have data.

---

Complete Prompts have been provided in a git repo. 

