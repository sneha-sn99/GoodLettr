@IsTest
private class GoodLettrBranchServiceTest {

    static Map<String, Object> branch(String name, String phone, String first, String last, String email, String street, String city, String pc) {
        return new Map<String, Object>{ 'name' => name, 'phone' => phone, 'contactFirstName' => first, 'contactLastName' => last,
            'contactEmail' => email, 'street' => street, 'city' => city, 'postcode' => pc };
    }

    @IsTest
    static void finishCreatesBranchesAndContactsInOneGo() {
        Account hq = new Account(Name = 'Northern Keys Lettings Group', Phone = '0161 496 0000');
        insert hq;
        Contact hqContact = new Contact(LastName = 'HQ Person', Email = 'hq@example.com', AccountId = hq.Id);
        insert hqContact;
        String json = JSON.serialize(new List<Object>{
            branch('Northern Keys Lettings Group - Leeds', '0113 496 0001', 'Sophie', 'Brennan', 'sophie@example.com', '8 Park Row', 'Leeds', 'ls1 5hd'),
            branch('Northern Keys Lettings Group - York', '01904 960 002', null, 'Patel', 'patel@example.com', '2 Stonegate', 'York', 'YO1 8AW')
        });

        GoodLettrBranchService.HeadOffice h = GoodLettrBranchService.getHeadOffice(hq.Id);
        Assert.isTrue(h.isHeadOffice);
        Assert.areEqual(0, h.existingBranches);
        GoodLettrBranchService.CheckResult c = GoodLettrBranchService.checkBranches(hq.Id, json);
        Assert.isFalse(c.hasErrors, String.join(c.errors, ' '));
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE ParentId = :hq.Id], 'Checking saves nothing');

        String msg = GoodLettrBranchService.createBranches(hq.Id, json);
        Assert.isTrue(msg.contains('2 branches and 2 contacts'), msg);
        Account leeds = [SELECT Id, ParentId, Phone, BillingPostalCode, BillingCountry, Account_Status__c, Is_Primary_Account__c,
                                (SELECT FirstName, LastName, Email, Is_Primary__c, MailingCity FROM Contacts)
                         FROM Account WHERE Name = 'Northern Keys Lettings Group - Leeds'];
        Assert.areEqual(hq.Id, leeds.ParentId);
        Assert.areEqual('LS1 5HD', leeds.BillingPostalCode);
        Assert.areEqual('United Kingdom', leeds.BillingCountry);
        Assert.areEqual('Draft', leeds.Account_Status__c);
        Assert.isFalse(leeds.Is_Primary_Account__c);
        Assert.areEqual(1, leeds.Contacts.size());
        Assert.areEqual('sophie@example.com', leeds.Contacts[0].Email);
        Assert.isFalse(leeds.Contacts[0].Is_Primary__c, 'Branch contacts are never primary');
        Assert.isTrue([SELECT Is_Primary__c FROM Contact WHERE Id = :hqContact.Id].Is_Primary__c);
        Assert.areEqual(3, [SELECT Number_of_Branches__c FROM Account WHERE Id = :hq.Id].Number_of_Branches__c);

        // Same again -> duplicate warnings (name, postcode, contact email)
        GoodLettrBranchService.CheckResult d = GoodLettrBranchService.checkBranches(hq.Id, json);
        Assert.isFalse(d.hasErrors);
        String w = String.join(d.warnings, ' ');
        Assert.isTrue(w.contains('already exists') && w.contains('already used') && w.contains('already belongs'), w);

        // Recount on delete / reparent; primary-account flag
        delete leeds;
        Assert.areEqual(2, [SELECT Number_of_Branches__c FROM Account WHERE Id = :hq.Id].Number_of_Branches__c);
        Account york = [SELECT Id FROM Account WHERE Name = 'Northern Keys Lettings Group - York'];
        update new Account(Id = york.Id, ParentId = null);
        Assert.areEqual(1, [SELECT Number_of_Branches__c FROM Account WHERE Id = :hq.Id].Number_of_Branches__c);
        Assert.isTrue([SELECT Is_Primary_Account__c FROM Account WHERE Id = :york.Id].Is_Primary_Account__c);
    }

    @IsTest
    static void errorsBlockCreationAndNothingIsSaved() {
        Account hq = new Account(Name = 'HQ Two', Phone = '0113 496 0000');
        insert hq;
        Account child = new Account(Name = 'HQ Two - Branch', Phone = '0113 496 0001', ParentId = hq.Id);
        insert child;
        String bad = JSON.serialize(new List<Object>{
            branch('', '', null, '', 'not-an-email', '', 'Leeds', ''),
            branch('Dup', '1', null, 'A', 'a@example.com', '1 St', 'Leeds', 'LS1 1AA'),
            branch('Dup', '2', null, 'B', 'b@example.com', '2 St', 'Leeds', 'LS1 1AA')
        });
        GoodLettrBranchService.CheckResult r = GoodLettrBranchService.checkBranches(hq.Id, bad);
        Assert.isTrue(r.hasErrors);
        String e = String.join(r.errors, ' ');
        Assert.isTrue(e.contains('branch name') && e.contains('phone') && e.contains('last name') && e.contains('not a valid email') && e.contains('street, city and postcode'), e);
        Assert.isTrue(String.join(r.warnings, ' ').contains('more than once'));
        try {
            GoodLettrBranchService.createBranches(hq.Id, bad);
            Assert.fail('Expected errors');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('branch name'));
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE ParentId = :hq.Id], 'Nothing created');

        Assert.isFalse(GoodLettrBranchService.getHeadOffice(child.Id).isHeadOffice);
        Assert.isTrue(GoodLettrBranchService.checkBranches(child.Id, '[]').errors[0].contains('head office'));
        try {
            GoodLettrBranchService.checkBranches(hq.Id, '{not json');
            Assert.fail('Expected parse error');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().contains('could not be read'));
        }
    }

    @IsTest
    static void failureRollsBackAccountsToo() {
        Account hq = new Account(Name = 'HQ Rollback', Phone = '0161 496 0003');
        insert hq;
        // Last name longer than 80 chars passes validation but fails on insert -> everything rolled back
        String tooLong = 'X'.repeat(90);
        String json = JSON.serialize(new List<Object>{ branch('HQ Rollback - Leeds', '0113 496 0005', null, tooLong, 'x@example.com', '1 Row', 'Leeds', 'LS1 1AA') });
        try {
            GoodLettrBranchService.createBranches(hq.Id, json);
            Assert.fail('Expected failure');
        } catch (AuraHandledException ex) {
            Assert.isTrue(ex.getMessage().startsWith('Nothing was created'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE ParentId = :hq.Id], 'Branch account rolled back with the contact');
    }

    @IsTest
    static void leadConvertedOntoChildAgencyContactIsNotPrimary() {
        Account hq = new Account(Name = 'Conv HQ', Phone = '0161 496 0001');
        insert hq;
        Contact hqContact = new Contact(LastName = 'HQ Person', AccountId = hq.Id);
        insert hqContact;
        Account child = new Account(Name = 'Conv HQ - Leeds', Phone = '0113 496 0003', ParentId = hq.Id);
        insert child;
        Lead l = new Lead(LastName = 'Branch Lead', Company = 'Conv HQ - Leeds', Email = 'branch.lead@example.com', Phone = '0113 496 0009');
        insert l;
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setAccountId(child.Id);
        lc.setDoNotCreateOpportunity(true);
        lc.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.LeadConvertResult res = Database.convertLead(lc);
        Assert.isFalse([SELECT Is_Primary__c FROM Contact WHERE Id = :res.getContactId()].Is_Primary__c);
        Assert.isTrue([SELECT Is_Primary__c FROM Contact WHERE Id = :hqContact.Id].Is_Primary__c);

        // New single account from lead conversion -> primary account flag
        Lead l2 = new Lead(LastName = 'Flag Lead', Company = 'Flag New Agency', Email = 'flag.lead@example.com', Phone = '0161 496 0010');
        insert l2;
        Database.LeadConvert lc2 = new Database.LeadConvert();
        lc2.setLeadId(l2.Id);
        lc2.setDoNotCreateOpportunity(true);
        lc2.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Assert.isTrue([SELECT Is_Primary_Account__c FROM Account WHERE Id = :Database.convertLead(lc2).getAccountId()].Is_Primary_Account__c);
    }
}