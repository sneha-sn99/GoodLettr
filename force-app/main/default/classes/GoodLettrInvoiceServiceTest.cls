@IsTest
private class GoodLettrInvoiceServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Invoice Agency', Phone = '0113 496 0000', BillingCity = 'Leeds');
        insert acc;
        Contact c = new Contact(FirstName = 'Bill', LastName = 'Payer', Email = 'bill.payer@example.com', AccountId = acc.Id);
        insert c;
        Product2 p = new Product2(Name = 'Invoice Product', ProductCode = 'TEST-INV', IsActive = true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 2, IsActive = true);
        insert pbe;
        Order o = new Order(Name = 'Invoice Order', AccountId = acc.Id, BillToContactId = c.Id, Status = 'Draft',
                            EffectiveDate = Date.today(), Pricebook2Id = Test.getStandardPricebookId());
        insert o;
        insert new OrderItem(OrderId = o.Id, PricebookEntryId = pbe.Id, Quantity = 100, UnitPrice = 6, Billing_Frequency__c = 'Quarterly');
        Order noContact = new Order(Name = 'No Contact Order', AccountId = acc.Id, Status = 'Draft',
                                    EffectiveDate = Date.today(), Pricebook2Id = Test.getStandardPricebookId());
        insert noContact;
    }

    static Order ord(String name) {
        return [SELECT Id FROM Order WHERE Name = :name];
    }

    @IsTest
    static void contextAndPdfController() {
        Order o = ord('Invoice Order');
        GoodLettrInvoiceService.InvoiceContext ctx = GoodLettrInvoiceService.getInvoiceContext(o.Id);
        Assert.isTrue(ctx.canSend, 'Blocked: ' + ctx.blockedReason);
        Assert.areEqual(600, ctx.amount);
        Assert.isTrue(ctx.invoiceNumber.startsWith('INV-'));
        Assert.areEqual('bill.payer@example.com', ctx.billToEmail);

        Test.setCurrentPage(Page.GoodLettrInvoice);
        GoodLettrInvoiceController ctrl = new GoodLettrInvoiceController(new ApexPages.StandardController(o));
        Assert.areEqual(1, ctrl.lines.size());
        Assert.areEqual('Quarterly', ctrl.billingFrequency);
        Assert.areEqual(ctrl.periodStart.addMonths(3).addDays(-1), ctrl.periodEnd);
        Assert.areEqual(ctrl.invoiceDate.addDays(30), ctrl.dueDate);
        Assert.isNotNull(ctrl.legalName);
        Assert.isNotNull(ctrl.registeredAddress);
        Assert.isNotNull(ctrl.companyNumber);
        Assert.areEqual(1, GoodLettrInvoiceService.monthsIn('Monthly'));
        Assert.areEqual(12, GoodLettrInvoiceService.monthsIn('Annual'));
    }

    @IsTest
    static void sendInvoiceBillsOrderAndSavesFile() {
        Order o = ord('Invoice Order');
        Test.startTest();
        Id docId = GoodLettrInvoiceService.sendInvoice(o.Id, new List<String>{ 'finance@example.com', '' }, 'Invoice', 'Body');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();
        Assert.areEqual(1, emails);
        Order after = [SELECT Status, Invoice_Number__c, Invoice_Date__c, Invoice_Due_Date__c FROM Order WHERE Id = :o.Id];
        Assert.areEqual('Billed', after.Status);
        Assert.isTrue(after.Invoice_Number__c.startsWith('INV-'));
        Assert.areEqual(Date.today(), after.Invoice_Date__c);
        Assert.areEqual(Date.today().addDays(30), after.Invoice_Due_Date__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :o.Id AND ContentDocumentId = :docId]);

        // Already billed -> blocked
        GoodLettrInvoiceService.InvoiceContext ctx = GoodLettrInvoiceService.getInvoiceContext(o.Id);
        Assert.isFalse(ctx.canSend);
        try {
            GoodLettrInvoiceService.sendInvoice(o.Id, null, 'Again', 'Body');
            Assert.fail('Expected already-billed error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('already'));
        }
    }

    @IsTest
    static void blockedWithoutContactProductsOrSubject() {
        Order noContact = ord('No Contact Order');
        GoodLettrInvoiceService.InvoiceContext ctx = GoodLettrInvoiceService.getInvoiceContext(noContact.Id);
        Assert.isFalse(ctx.canSend);
        Assert.isTrue(ctx.blockedReason.contains('no products'));
        try {
            GoodLettrInvoiceService.sendInvoice(ord('Invoice Order').Id, null, '', 'Body');
            Assert.fail('Expected subject error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('subject'));
        }
        Order o = ord('Invoice Order');
        update new Order(Id = o.Id, BillToContactId = null);
        Assert.isTrue(GoodLettrInvoiceService.getInvoiceContext(o.Id).blockedReason.contains('Bill To Contact'));
        try {
            GoodLettrInvoiceService.getInvoiceContext('801000000000000AAA');
            Assert.fail('Expected not found');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
    }
}