/**
 * Controller extension for the GoodLettrInvoice Visualforce page (rendered as PDF).
 * Invoice number = INV-<OrderNumber>; invoice date = the stored Invoice Date or today; due = +30 days.
 * The billing period covers one period of the line's billing frequency from the Order start date.
 * No VAT is applied for now.
 */
public with sharing class GoodLettrInvoiceController {
    public Order ord { get; private set; }
    public List<OrderItem> lines { get; private set; }
    public String invoiceNumber { get; private set; }
    public Date invoiceDate { get; private set; }
    public Date dueDate { get; private set; }
    public Date periodStart { get; private set; }
    public Date periodEnd { get; private set; }
    public String billingFrequency { get; private set; }

    public GoodLettrInvoiceController(ApexPages.StandardController std) {
        Id orderId = std.getId();
        ord = [
            SELECT Id, OrderNumber, Name, Status, EffectiveDate, EndDate, TotalAmount, Invoice_Number__c, Invoice_Date__c,
                   Invoice_Due_Date__c, Account.Name, BillingStreet, BillingCity, BillingPostalCode, BillingCountry,
                   BillToContact.Name, BillToContact.Email, Opportunity__r.Name, Service_Contract__r.Name
            FROM Order WHERE Id = :orderId
        ];
        lines = [
            SELECT Product2.Name, Quantity, ListPrice, UnitPrice, TotalPrice, Billing_Frequency__c, Discount_Percent__c
            FROM OrderItem WHERE OrderId = :orderId ORDER BY CreatedDate
        ];
        invoiceNumber = GoodLettrInvoiceService.invoiceNumberFor(ord);
        invoiceDate = ord.Invoice_Date__c != null ? ord.Invoice_Date__c : Date.today();
        dueDate = ord.Invoice_Due_Date__c != null ? ord.Invoice_Due_Date__c : invoiceDate.addDays(GoodLettrInvoiceService.PAYMENT_TERMS_DAYS);
        billingFrequency = lines.isEmpty() || String.isBlank(lines[0].Billing_Frequency__c) ? 'Monthly' : lines[0].Billing_Frequency__c;
        periodStart = ord.EffectiveDate;
        periodEnd = periodStart == null ? null : periodStart.addMonths(GoodLettrInvoiceService.monthsIn(billingFrequency)).addDays(-1);
    }

    public String legalName { get { return System.Label.GoodLettr_Legal_Name; } }
    public String registeredAddress { get { return System.Label.GoodLettr_Registered_Address; } }
    public String companyNumber { get { return System.Label.GoodLettr_Company_Number; } }
}