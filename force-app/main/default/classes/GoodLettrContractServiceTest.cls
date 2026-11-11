@IsTest
private class GoodLettrContractServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Lettings Agency', BillingCity = 'London', Number_of_Branches__c = 3);
        insert acc;
        insert new Contact(FirstName = 'Ava', LastName = 'Agent', Email = 'ava.agent@example.com', AccountId = acc.Id);
        insert new Contact(FirstName = 'No', LastName = 'Email', AccountId = acc.Id);

        Product2 p = new Product2(Name = 'Test Usage Product', ProductCode = 'TEST-USG', IsActive = true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 2, IsActive = true
        );
        insert pbe;
        Opportunity opp = new Opportunity(
            Name = 'Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId(), Number_of_Tenancies__c = 100
        );
        insert opp;
        insert new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = pbe.Id, Quantity = 100, UnitPrice = 2);
    }

    static Opportunity opp() {
        return [SELECT Id, AccountId FROM Opportunity LIMIT 1];
    }

    @IsTest
    static void controllerLoadsContractData() {
        Opportunity o = opp();
        Test.setCurrentPage(Page.GoodLettrContract);
        GoodLettrContractController ctrl = new GoodLettrContractController(new ApexPages.StandardController(o));
        Assert.areEqual(1, ctrl.lines.size());
        Assert.areEqual(200, ctrl.totalPerPeriod);
        Assert.isTrue(ctrl.hasLines);
        Assert.isNotNull(ctrl.agencyContact, 'Contact with an email is chosen');
        Assert.isTrue(ctrl.contractReference.startsWith('GL-'));
        Assert.isNotNull(ctrl.legalName);
        Assert.isNotNull(ctrl.registeredAddress);
        Assert.isNotNull(ctrl.companyNumber);
    }

    @IsTest
    static void sendContextListsOnlyContactsWithEmail() {
        GoodLettrContractService.SendContext ctx = GoodLettrContractService.getSendContext(opp().Id);
        Assert.areEqual(1, ctx.recipients.size());
        Assert.areEqual('ava.agent@example.com', ctx.recipients[0].email);
        Assert.isTrue(ctx.hasLines);
        Assert.isTrue(ctx.defaultSubject.contains('Test Lettings Agency'));
    }

    @IsTest
    static void saveToFilesCreatesLinkedFile() {
        Opportunity o = opp();
        Test.startTest();
        Id docId = GoodLettrContractService.saveContractToFiles(o.Id);
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :o.Id AND ContentDocumentId = :docId]);
    }

    @IsTest
    static void sendContractEmailsAndSavesFile() {
        Opportunity o = opp();
        Contact c = [SELECT Id FROM Contact WHERE Email != null LIMIT 1];
        Test.startTest();
        Id docId = GoodLettrContractService.sendContract(o.Id, c.Id, new List<String>{ 'cc@example.com', ' ' }, 'Subject', 'Body');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();
        Assert.areEqual(1, emails, 'One email sent');
        ContentDocument doc = [SELECT Title FROM ContentDocument WHERE Id = :docId];
        Assert.isTrue(doc.Title.contains('(Sent'), 'Sent copy saved to Files');
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :o.Id]);
        Opportunity after = [SELECT StageName, Contract_Sent_On__c FROM Opportunity WHERE Id = :o.Id];
        Assert.isNotNull(after.Contract_Sent_On__c);
        Assert.areEqual('Negotiation/Review', after.StageName, 'Sending moves the stage to Negotiation/Review');
    }

    @IsTest
    static void generateMovesStageToProposal() {
        Opportunity o = opp();
        Test.startTest();
        GoodLettrContractService.markContractGenerated(o.Id);
        Test.stopTest();
        Opportunity after = [SELECT StageName, Contract_Generated_On__c FROM Opportunity WHERE Id = :o.Id];
        Assert.isNotNull(after.Contract_Generated_On__c);
        Assert.areEqual('Proposal/Price Quote', after.StageName);
    }

    @IsTest
    static void generateDoesNotMoveStageBackwardsOrReopen() {
        Opportunity o = opp();
        update new Opportunity(Id = o.Id, StageName = 'Negotiation/Review');
        GoodLettrContractService.markContractGenerated(o.Id);
        Assert.areEqual('Negotiation/Review', [SELECT StageName FROM Opportunity WHERE Id = :o.Id].StageName);

        update new Opportunity(Id = o.Id, StageName = 'Closed Won');
        GoodLettrContractService.markContractGenerated(o.Id);
        update new Opportunity(Id = o.Id, Contract_Sent_On__c = Datetime.now());
        Assert.areEqual('Closed Won', [SELECT StageName FROM Opportunity WHERE Id = :o.Id].StageName);
    }

    @IsTest
    static void sendContractValidatesInputs() {
        Opportunity o = opp();
        Contact c = [SELECT Id FROM Contact WHERE Email != null LIMIT 1];
        try {
            GoodLettrContractService.sendContract(o.Id, null, null, 'S', 'B');
            Assert.fail('Expected missing contact error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('contact'));
        }
        try {
            GoodLettrContractService.sendContract(o.Id, c.Id, null, '', 'B');
            Assert.fail('Expected missing subject error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('subject'));
        }
        try {
            GoodLettrContractService.getSendContext('006000000000000AAA');
            Assert.fail('Expected not found error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
    }
}