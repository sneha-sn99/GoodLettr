@IsTest
private class GoodLettrPrimaryContactServiceTest {

    @IsTest
    static void firstContactOnTopAccountBecomesPrimaryOnly() {
        Account top = new Account(Name = 'Top Agency', Phone = '0113 496 0000');
        insert top;
        Account branch = new Account(Name = 'Top Agency - Branch', Phone = '0113 496 0001', ParentId = top.Id);
        insert branch;

        Contact first = new Contact(LastName = 'First', Email = 'first@example.com', AccountId = top.Id);
        insert first;
        Contact second = new Contact(LastName = 'Second', Email = 'second@example.com', AccountId = top.Id);
        insert second;
        Contact branchContact = new Contact(LastName = 'Branch', Email = 'branch@example.com', AccountId = branch.Id);
        insert branchContact;

        Assert.isTrue([SELECT Is_Primary__c FROM Contact WHERE Id = :first.Id].Is_Primary__c, 'Only contact on top account is primary');
        Assert.isFalse([SELECT Is_Primary__c FROM Contact WHERE Id = :second.Id].Is_Primary__c, 'Second contact is not auto-primary');
        Assert.isFalse([SELECT Is_Primary__c FROM Contact WHERE Id = :branchContact.Id].Is_Primary__c, 'Branch contacts are never auto-primary');
        Assert.areEqual(first.Id, [SELECT Primary_Contact__c FROM Account WHERE Id = :top.Id].Primary_Contact__c);
    }

    @IsTest
    static void makePrimaryOnTopAndBranchKeepsOnePerGroup() {
        Account top = new Account(Name = 'Group HQ', Phone = '0161 496 0000');
        insert top;
        Account branch = new Account(Name = 'Group - Leeds', Phone = '0113 496 0002', ParentId = top.Id);
        insert branch;
        Contact hq1 = new Contact(LastName = 'HQ One', AccountId = top.Id);
        insert hq1;
        Contact hq2 = new Contact(LastName = 'HQ Two', AccountId = top.Id);
        insert hq2;
        Contact leeds = new Contact(LastName = 'Leeds Manager', AccountId = branch.Id);
        insert leeds;

        // Top-account contact
        GoodLettrPrimaryContactService.PrimaryContext ctx = GoodLettrPrimaryContactService.getContext(hq2.Id);
        Assert.isFalse(ctx.isChildAccount);
        Assert.isFalse(ctx.isAlreadyPrimary);
        Assert.areEqual('HQ One', ctx.currentPrimaryName);
        Assert.areEqual('HQ One', GoodLettrPrimaryContactService.makePrimary(hq2.Id));
        Assert.isTrue(GoodLettrPrimaryContactService.getContext(hq2.Id).isAlreadyPrimary);

        // Branch contact -> becomes the group's primary, held on the top account
        ctx = GoodLettrPrimaryContactService.getContext(leeds.Id);
        Assert.isTrue(ctx.isChildAccount);
        Assert.areEqual('Group HQ', ctx.topAccountName);
        Assert.areEqual('HQ Two', ctx.currentPrimaryName);
        Assert.areEqual('HQ Two', GoodLettrPrimaryContactService.makePrimary(leeds.Id));

        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Is_Primary__c = true AND AccountId IN (:top.Id, :branch.Id)]);
        Contact movedLeeds = [SELECT Is_Primary__c, AccountId FROM Contact WHERE Id = :leeds.Id];
        Assert.isTrue(movedLeeds.Is_Primary__c);
        Assert.areEqual(top.Id, movedLeeds.AccountId, 'Branch contact made primary moves to the top account');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE AccountId = :branch.Id], 'No longer on the branch');
        Assert.isFalse(GoodLettrPrimaryContactService.getContext(leeds.Id).isChildAccount);
        Assert.isTrue(GoodLettrPrimaryContactService.getContext(leeds.Id).isAlreadyPrimary);
        Assert.areEqual(leeds.Id, [SELECT Primary_Contact__c FROM Account WHERE Id = :top.Id].Primary_Contact__c);
        Assert.areEqual(new Set<Id>{ top.Id, branch.Id }, GoodLettrPrimaryContactService.hierarchyAccountIds(top.Id));
    }

    @IsTest
    static void errors() {
        Contact orphan = new Contact(LastName = 'No Account');
        insert orphan;
        try {
            GoodLettrPrimaryContactService.getContext(orphan.Id);
            Assert.fail('Expected no-account error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not linked'));
        }
        try {
            GoodLettrPrimaryContactService.makePrimary(orphan.Id);
            Assert.fail('Expected error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not linked'));
        }
        try {
            GoodLettrPrimaryContactService.getContext('003000000000000AAA');
            Assert.fail('Expected not found');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
    }
}