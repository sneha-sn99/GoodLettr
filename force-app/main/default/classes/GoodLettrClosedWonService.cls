/**
 * Invoked by the "Opportunity Closed Won - Service Contract and Order" flow when an Opportunity moves to Closed Won
 * (reps do this manually once the signed contract is received).
 *
 * For each Opportunity it creates:
 *  - a Service Contract with the commercial terms, plus Contract Line Items copied from the Opportunity Products
 *  - a Draft Order linked to the Opportunity and the Service Contract, plus Order Products copied from the Opportunity Products
 *
 * Idempotent: Opportunities that already have a Service Contract (Opportunity__c) are skipped.
 * Runs without sharing because it is system automation triggered by the stage change.
 */
public without sharing class GoodLettrClosedWonService {

    public static final Integer INITIAL_TERM_MONTHS = 12;

    public class Request {
        @InvocableVariable(label='Opportunity ID' required=true)
        public Id opportunityId;
    }

    @InvocableMethod(
        label='Create Service Contract and Order'
        description='Creates a Service Contract (with contract lines) and a Draft Order (with order products) from a Closed Won Opportunity.'
        category='GoodLettr'
    )
    public static void createFromRequests(List<Request> requests) {
        Set<Id> oppIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.opportunityId != null) {
                oppIds.add(r.opportunityId);
            }
        }
        createServiceContractsAndOrders(oppIds);
    }

    public static void createServiceContractsAndOrders(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }
        // Skip Opportunities that already have a Service Contract (e.g. reopened and closed again).
        for (ServiceContract sc : [SELECT Opportunity__c FROM ServiceContract WHERE Opportunity__c IN :oppIds]) {
            oppIds.remove(sc.Opportunity__c);
        }
        if (oppIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, AccountId, Account.Name, Account.BillingStreet, Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.BillingCountry, CloseDate, Pricebook2Id, Number_of_Tenancies__c,
                   (SELECT Id, PricebookEntryId, Product2.Name, Quantity, UnitPrice, ListPrice, Description,
                           Billing_Frequency__c, Discount_Percent__c
                    FROM OpportunityLineItems ORDER BY SortOrder, CreatedDate),
                   (SELECT ContactId FROM OpportunityContactRoles ORDER BY IsPrimary DESC, CreatedDate LIMIT 1)
            FROM Opportunity
            WHERE Id IN :oppIds
        ]);

        // 1. Service Contracts
        Map<Id, ServiceContract> contractByOpp = new Map<Id, ServiceContract>();
        for (Opportunity o : opps.values()) {
            Date startDate = o.CloseDate != null ? o.CloseDate : Date.today();
            Id contactId = o.OpportunityContactRoles.isEmpty() ? null : o.OpportunityContactRoles[0].ContactId;
            contractByOpp.put(o.Id, new ServiceContract(
                Name = truncate('GoodLettr Service Contract - ' + agencyName(o), 255),
                Opportunity__c = o.Id,
                AccountId = o.AccountId,
                ContactId = contactId,
                StartDate = startDate,
                Term = INITIAL_TERM_MONTHS,
                EndDate = startDate.addMonths(INITIAL_TERM_MONTHS).addDays(-1),
                Pricebook2Id = o.Pricebook2Id,
                BillingStreet = o.Account?.BillingStreet,
                BillingCity = o.Account?.BillingCity,
                BillingState = o.Account?.BillingState,
                BillingPostalCode = o.Account?.BillingPostalCode,
                BillingCountry = o.Account?.BillingCountry,
                Description = 'Created automatically from Opportunity "' + o.Name + '" when it was marked Closed Won (signed contract received).',
                SpecialTerms = commercialTerms(o)
            ));
        }
        insert contractByOpp.values();

        // 2. Contract Line Items
        List<ContractLineItem> contractLines = new List<ContractLineItem>();
        for (Opportunity o : opps.values()) {
            ServiceContract sc = contractByOpp.get(o.Id);
            for (OpportunityLineItem li : o.OpportunityLineItems) {
                contractLines.add(new ContractLineItem(
                    ServiceContractId = sc.Id,
                    PricebookEntryId = li.PricebookEntryId,
                    Quantity = li.Quantity,
                    UnitPrice = li.UnitPrice,
                    StartDate = sc.StartDate,
                    EndDate = sc.EndDate,
                    Description = li.Description,
                    Billing_Frequency__c = li.Billing_Frequency__c,
                    Discount_Percent__c = li.Discount_Percent__c
                ));
            }
        }
        insert contractLines;

        // 3. Orders (Draft)
        Map<Id, Order> orderByOpp = new Map<Id, Order>();
        for (Opportunity o : opps.values()) {
            ServiceContract sc = contractByOpp.get(o.Id);
            orderByOpp.put(o.Id, new Order(
                Name = truncate('GoodLettr Order - ' + agencyName(o), 80),
                AccountId = o.AccountId,
                Opportunity__c = o.Id,
                Service_Contract__c = sc.Id,
                Pricebook2Id = o.Pricebook2Id,
                EffectiveDate = sc.StartDate,
                EndDate = sc.EndDate,
                Status = 'Draft',
                BillToContactId = sc.ContactId,
                BillingStreet = sc.BillingStreet,
                BillingCity = sc.BillingCity,
                BillingState = sc.BillingState,
                BillingPostalCode = sc.BillingPostalCode,
                BillingCountry = sc.BillingCountry,
                Description = 'Created automatically from Opportunity "' + o.Name + '" (Closed Won).'
            ));
        }
        insert orderByOpp.values();

        // 4. Order Products
        List<OrderItem> orderLines = new List<OrderItem>();
        for (Opportunity o : opps.values()) {
            Order ord = orderByOpp.get(o.Id);
            for (OpportunityLineItem li : o.OpportunityLineItems) {
                orderLines.add(new OrderItem(
                    OrderId = ord.Id,
                    PricebookEntryId = li.PricebookEntryId,
                    Quantity = li.Quantity,
                    UnitPrice = li.UnitPrice,
                    ServiceDate = ord.EffectiveDate,
                    EndDate = ord.EndDate,
                    Description = li.Description,
                    Billing_Frequency__c = li.Billing_Frequency__c,
                    Discount_Percent__c = li.Discount_Percent__c
                ));
            }
        }
        insert orderLines;
    }

    /** Plain-text summary of the commercial terms, matching the GoodLettr contract PDF. */
    @TestVisible
    private static String commercialTerms(Opportunity o) {
        List<String> lines = new List<String>{
            'COMMERCIAL TERMS (as agreed in the signed GoodLettr Software Services Agreement)',
            'Initial term: ' + INITIAL_TERM_MONTHS + ' months from the commencement date; renews automatically for successive 12-month periods unless either party gives at least 60 days\' written notice.',
            'Charging basis: usage-based, per tenancy managed through the software in each billing period x rate per tenancy per month x months in the billing period, less any agreed discount.',
            'Billing: invoiced in arrears at the end of each billing period. Payment terms: 30 days from invoice date. Prices are in GBP (£) and exclude VAT.',
            'Discounts apply for the initial term only unless agreed otherwise in writing. Rate changes on renewal with 60 days\' notice.',
            'Late payment: access may be suspended 14 days after written notice of non-payment. Governing law: England and Wales.',
            '',
            'SERVICES'
        };
        if (o.Number_of_Tenancies__c != null) {
            lines.add('Estimated tenancies: ' + o.Number_of_Tenancies__c.format());
        }
        for (OpportunityLineItem li : o.OpportunityLineItems) {
            lines.add('- ' + li.Product2.Name
                + ' | Billing: ' + (String.isBlank(li.Billing_Frequency__c) ? 'Monthly' : li.Billing_Frequency__c)
                + ' | Quantity: ' + (li.Quantity == null ? '0' : li.Quantity.format())
                + ' | List rate: ' + (li.ListPrice == null ? '-' : '£' + String.valueOf(li.ListPrice.setScale(2))) + ' per unit per month'
                + ' | Discount: ' + (li.Discount_Percent__c == null ? '0' : li.Discount_Percent__c.format()) + '%'
                + ' | Net price per unit per period: ' + (li.UnitPrice == null ? '-' : '£' + String.valueOf(li.UnitPrice.setScale(2))));
        }
        return truncate(String.join(lines, '\n'), 4000);
    }

    private static String agencyName(Opportunity o) {
        return o.Account?.Name != null ? o.Account.Name : o.Name;
    }

    private static String truncate(String s, Integer max) {
        return s == null || s.length() <= max ? s : s.left(max);
    }
}