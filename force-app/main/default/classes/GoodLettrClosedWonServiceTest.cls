@IsTest
private class GoodLettrClosedWonServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Won Agency', BillingCity = 'Leeds');
        insert acc;
        Contact c = new Contact(LastName = 'Signer', Email = 'signer@example.com', AccountId = acc.Id);
        insert c;
        Product2 p = new Product2(Name = 'Test Product', ProductCode = 'TEST-CW', IsActive = true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 2, IsActive = true);
        insert pbe;
        Opportunity o = new Opportunity(Name = 'Won Opp', AccountId = acc.Id, StageName = 'Negotiation/Review',
            CloseDate = Date.newInstance(2027, 1, 1), Pricebook2Id = Test.getStandardPricebookId(), Number_of_Tenancies__c = 500);
        insert o;
        insert new OpportunityContactRole(OpportunityId = o.Id, ContactId = c.Id, IsPrimary = true);
        insert new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = pbe.Id, Quantity = 500, UnitPrice = 1.8,
            Billing_Frequency__c = 'Quarterly', Discount_Percent__c = 10);
    }

    @IsTest
    static void closedWonCreatesServiceContractAndOrder() {
        Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        update new Opportunity(Id = o.Id, StageName = 'Closed Won'); // flow -> invocable Apex
        Test.stopTest();

        ServiceContract sc = [SELECT Id, AccountId, ContactId, StartDate, EndDate, Term, SpecialTerms,
                                     (SELECT Quantity, UnitPrice, Billing_Frequency__c, Discount_Percent__c FROM ContractLineItems)
                              FROM ServiceContract WHERE Opportunity__c = :o.Id];
        // Salesforce may reset CloseDate when the Opportunity is closed; the contract starts on the actual CloseDate.
        Date closeDate = [SELECT CloseDate FROM Opportunity WHERE Id = :o.Id].CloseDate;
        Assert.areEqual(closeDate, sc.StartDate);
        Assert.areEqual(closeDate.addMonths(12).addDays(-1), sc.EndDate);
        Assert.areEqual(12, sc.Term);
        Assert.isNotNull(sc.ContactId);
        Assert.isTrue(sc.SpecialTerms.contains('COMMERCIAL TERMS'));
        Assert.areEqual(1, sc.ContractLineItems.size());
        Assert.areEqual(500, sc.ContractLineItems[0].Quantity);
        Assert.areEqual(1.8, sc.ContractLineItems[0].UnitPrice);
        Assert.areEqual('Quarterly', sc.ContractLineItems[0].Billing_Frequency__c);
        Assert.areEqual(10, sc.ContractLineItems[0].Discount_Percent__c);

        Order ord = [SELECT Status, Service_Contract__c, EffectiveDate, (SELECT Quantity, UnitPrice, Billing_Frequency__c FROM OrderItems)
                     FROM Order WHERE Opportunity__c = :o.Id];
        Assert.areEqual('Draft', ord.Status);
        Assert.areEqual(sc.Id, ord.Service_Contract__c);
        Assert.areEqual(1, ord.OrderItems.size());
        Assert.areEqual(1.8, ord.OrderItems[0].UnitPrice);
        Assert.areEqual('Quarterly', ord.OrderItems[0].Billing_Frequency__c);
    }

    @IsTest
    static void runningTwiceDoesNotDuplicate() {
        Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        update new Opportunity(Id = o.Id, StageName = 'Closed Won');
        GoodLettrClosedWonService.Request r = new GoodLettrClosedWonService.Request();
        r.opportunityId = o.Id;
        GoodLettrClosedWonService.createFromRequests(new List<GoodLettrClosedWonService.Request>{ r, null });
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :o.Id]);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE Opportunity__c = :o.Id]);
    }

    @IsTest
    static void otherStagesDoNothing() {
        Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];
        update new Opportunity(Id = o.Id, StageName = 'Closed Lost');
        Assert.areEqual(0, [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :o.Id]);
        GoodLettrClosedWonService.createServiceContractsAndOrders(new Set<Id>());
    }
}