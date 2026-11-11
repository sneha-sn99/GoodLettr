/**
 * Controller extension for the GoodLettrContract Visualforce page (rendered as PDF).
 * Loads the Opportunity, its agency (Account), the agency contact and the product lines
 * that make up the commercial schedule.
 */
public with sharing class GoodLettrContractController {
    public Opportunity opp { get; private set; }
    public Contact agencyContact { get; private set; }
    public List<OpportunityLineItem> lines { get; private set; }
    public Decimal totalPerPeriod { get; private set; }
    public Date contractDate { get; private set; }
    public String contractReference { get; private set; }

    public GoodLettrContractController(ApexPages.StandardController stdController) {
        Id oppId = stdController.getId();
        contractDate = Date.today();
        opp = [
            SELECT Id, Name, CloseDate, Amount, Number_of_Tenancies__c,
                   Account.Name, Account.BillingStreet, Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.BillingCountry, Account.Phone,
                   Account.Number_of_Branches__c
            FROM Opportunity
            WHERE Id = :oppId
        ];
        lines = [
            SELECT Id, Product2.Name, Product2.Description, Product2.QuantityUnitOfMeasure,
                   Product2.Charge_Type__c, Quantity, ListPrice, UnitPrice, TotalPrice,
                   Billing_Frequency__c, Discount_Percent__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :oppId
            ORDER BY SortOrder, CreatedDate
        ];
        totalPerPeriod = 0;
        for (OpportunityLineItem li : lines) {
            totalPerPeriod += li.TotalPrice == null ? 0 : li.TotalPrice;
        }
        List<Contact> contacts = GoodLettrContractService.getAgencyContacts(opp.Id, opp.AccountId);
        agencyContact = contacts.isEmpty() ? null : contacts[0];
        contractReference = 'GL-' + String.valueOf(opp.Id).right(8).toUpperCase() + '-' + Datetime.now().format('yyyyMMdd');
    }

    public String legalName { get { return System.Label.GoodLettr_Legal_Name; } }
    public String registeredAddress { get { return System.Label.GoodLettr_Registered_Address; } }
    public String companyNumber { get { return System.Label.GoodLettr_Company_Number; } }

    public Boolean hasLines { get { return lines != null && !lines.isEmpty(); } }
}