/**
 * Primary contact per agency group (the top account plus its branch accounts).
 * - Only one contact in the whole group can have Is_Primary__c = true.
 * - The top account's Primary_Contact__c points to that contact (which may belong to a branch).
 * - Make Primary (quick action) on a branch contact asks for confirmation first, because the primary
 *   is held at the top-account level, never at branch level. Once confirmed, the contact is MOVED to the
 *   top account (AccountId = top account), so it is no longer on the branch.
 * - When the only contact on a top-level account is created and the group has no primary yet, it becomes primary.
 * Runs without sharing so the single-primary rule is always enforced across the group.
 */
public without sharing class GoodLettrPrimaryContactService {

    public class PrimaryContext {
        @AuraEnabled public String contactName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id topAccountId;
        @AuraEnabled public String topAccountName;
        @AuraEnabled public Boolean isChildAccount;
        @AuraEnabled public Boolean isAlreadyPrimary;
        @AuraEnabled public String currentPrimaryName;
        @AuraEnabled public String currentPrimaryAccountName;
    }

    @AuraEnabled
    public static PrimaryContext getContext(Id contactId) {
        Contact c = loadContact(contactId);
        Id topId = topAccountId(c.AccountId);
        Account top = [SELECT Id, Name FROM Account WHERE Id = :topId];
        Contact current = currentPrimary(hierarchyAccountIds(topId));
        PrimaryContext ctx = new PrimaryContext();
        ctx.contactName = c.Name;
        ctx.accountName = c.Account.Name;
        ctx.topAccountId = top.Id;
        ctx.topAccountName = top.Name;
        ctx.isChildAccount = c.AccountId != topId;
        ctx.isAlreadyPrimary = current != null && current.Id == c.Id;
        ctx.currentPrimaryName = current?.Name;
        ctx.currentPrimaryAccountName = current?.Account?.Name;
        return ctx;
    }

    /** Makes the contact the primary for its agency group. Returns the name of the previous primary (or null). */
    @AuraEnabled
    public static String makePrimary(Id contactId) {
        try {
            Contact c = loadContact(contactId);
            Id topId = topAccountId(c.AccountId);
            Set<Id> groupIds = hierarchyAccountIds(topId);
            List<Contact> updates = new List<Contact>();
            String previous;
            for (Contact other : [SELECT Id, Name FROM Contact WHERE AccountId IN :groupIds AND Is_Primary__c = true AND Id != :contactId]) {
                previous = other.Name;
                updates.add(new Contact(Id = other.Id, Is_Primary__c = false));
            }
            Contact primary = new Contact(Id = c.Id, Is_Primary__c = true);
            if (c.AccountId != topId) {
                primary.AccountId = topId; // branch contact moves to the top account
            }
            if (!c.Is_Primary__c || c.AccountId != topId) {
                updates.add(primary);
            }
            update updates;
            update new Account(Id = topId, Primary_Contact__c = c.Id);
            return previous;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError('Could not make this contact primary: ' + e.getMessage());
        }
    }

    /** After insert: the only contact on a top-level account becomes primary if its group has no primary yet. */
    public static void assignDefaultPrimary(List<Contact> newContacts) {
        Set<Id> accountIds = new Set<Id>();
        for (Contact c : newContacts) {
            if (c.AccountId != null && !c.Is_Primary__c) accountIds.add(c.AccountId);
        }
        if (accountIds.isEmpty()) return;

        Map<Id, Account> topLevel = new Map<Id, Account>([SELECT Id FROM Account WHERE Id IN :accountIds AND ParentId = null]);
        if (topLevel.isEmpty()) return;

        Map<Id, Integer> contactCount = new Map<Id, Integer>();
        for (AggregateResult ar : [SELECT AccountId acc, COUNT(Id) n FROM Contact WHERE AccountId IN :topLevel.keySet() GROUP BY AccountId]) {
            contactCount.put((Id) ar.get('acc'), (Integer) ar.get('n'));
        }
        // Groups that already have a primary (top account or any branch)
        Set<Id> hasPrimary = new Set<Id>();
        for (Contact p : [SELECT AccountId, Account.ParentId FROM Contact WHERE Is_Primary__c = true
                          AND (AccountId IN :topLevel.keySet() OR Account.ParentId IN :topLevel.keySet())]) {
            hasPrimary.add(p.Account.ParentId != null ? p.Account.ParentId : p.AccountId);
        }

        List<Contact> contactUpdates = new List<Contact>();
        List<Account> accountUpdates = new List<Account>();
        for (Contact c : newContacts) {
            if (topLevel.containsKey(c.AccountId) && contactCount.get(c.AccountId) == 1 && !hasPrimary.contains(c.AccountId)) {
                contactUpdates.add(new Contact(Id = c.Id, Is_Primary__c = true));
                accountUpdates.add(new Account(Id = c.AccountId, Primary_Contact__c = c.Id));
                hasPrimary.add(c.AccountId);
            }
        }
        update contactUpdates;
        update accountUpdates;
    }

    // ---- helpers

    /** Walks up ParentId (max 5 levels) to the top account. */
    public static Id topAccountId(Id accountId) {
        if (accountId == null) {
            throw auraError('This contact is not linked to an agency (Account).');
        }
        Account a = [SELECT Id, ParentId, Parent.ParentId, Parent.Parent.ParentId, Parent.Parent.Parent.ParentId,
                            Parent.Parent.Parent.Parent.ParentId FROM Account WHERE Id = :accountId];
        List<Id> chain = new List<Id>{ a.Id, a.ParentId, a.Parent?.ParentId, a.Parent?.Parent?.ParentId,
                                       a.Parent?.Parent?.Parent?.ParentId, a.Parent?.Parent?.Parent?.Parent?.ParentId };
        Id top = a.Id;
        for (Id i : chain) {
            if (i != null) top = i;
        }
        return top;
    }

    /** The top account and all branches below it (up to 5 levels). */
    public static Set<Id> hierarchyAccountIds(Id topId) {
        Set<Id> ids = new Set<Id>{ topId };
        Set<Id> frontier = new Set<Id>{ topId };
        for (Integer level = 0; level < 5 && !frontier.isEmpty(); level++) {
            Set<Id> next = new Map<Id, Account>([SELECT Id FROM Account WHERE ParentId IN :frontier]).keySet().clone();
            next.removeAll(ids);
            ids.addAll(next);
            frontier = next;
        }
        return ids;
    }

    private static Contact currentPrimary(Set<Id> groupIds) {
        List<Contact> ps = [SELECT Id, Name, Account.Name FROM Contact WHERE AccountId IN :groupIds AND Is_Primary__c = true ORDER BY LastModifiedDate DESC LIMIT 1];
        return ps.isEmpty() ? null : ps[0];
    }

    private static Contact loadContact(Id contactId) {
        List<Contact> cs = [SELECT Id, Name, AccountId, Account.Name, Is_Primary__c FROM Contact WHERE Id = :contactId];
        if (cs.isEmpty()) {
            throw auraError('Contact not found.');
        }
        return cs[0];
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}