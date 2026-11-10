/**
 * Add Branches (Account quick action, LWC goodlettrAddBranches).
 * The screen keeps the branches as JSON in the browser; nothing is saved until Finish.
 * On Finish, createBranches() validates again and creates every branch Account and its contact person
 * in one transaction (all or nothing): Parent = head office, Status Draft; contacts are never primary
 * (ContactPrimaryTrigger only auto-assigns primary on top-level accounts).
 * Number of Branches and Is Primary Account are maintained by AccountBranchCountTrigger.
 */
public without sharing class GoodLettrBranchService {

    private static final Pattern EMAIL = Pattern.compile('^[A-Za-z0-9._%+\'-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');

    /** One branch as entered on the screen (JSON element). */
    public class BranchInput {
        public String name;
        public String phone;
        public String contactFirstName;
        public String contactLastName;
        public String contactEmail;
        public String street;
        public String city;
        public String postcode;
        public String country;
    }

    public class HeadOffice {
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isHeadOffice;
        @AuraEnabled public Integer existingBranches;
    }

    public class CheckResult {
        @AuraEnabled public Boolean hasErrors = false;
        @AuraEnabled public List<String> errors = new List<String>();
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    @AuraEnabled
    public static HeadOffice getHeadOffice(Id accountId) {
        Account a = [SELECT Id, Name, ParentId FROM Account WHERE Id = :accountId];
        HeadOffice h = new HeadOffice();
        h.name = a.Name;
        h.isHeadOffice = a.ParentId == null;
        h.existingBranches = [SELECT COUNT() FROM Account WHERE ParentId = :accountId];
        return h;
    }

    /** Validates the branches (JSON) without saving anything. */
    @AuraEnabled
    public static CheckResult checkBranches(Id parentId, String branchesJson) {
        return check(parentId, parse(branchesJson));
    }

    /** Creates all branches and their contacts in one transaction. Returns a confirmation message. */
    @AuraEnabled
    public static String createBranches(Id parentId, String branchesJson) {
        List<BranchInput> branches = parse(branchesJson);
        CheckResult res = check(parentId, branches);
        if (res.hasErrors) {
            throw auraError(String.join(res.errors, ' '));
        }
        // Branch names usually start with the head office name, which trips the standard (alert-only) duplicate
        // rules. The rep has already confirmed GoodLettr's own duplicate warnings, so allow the save; rules set to Block still block.
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.OptAllOrNone = true;
        Savepoint sp = Database.setSavepoint();
        try {
            List<Account> accounts = new List<Account>();
            for (BranchInput b : branches) {
                accounts.add(new Account(
                    Name = b.name.trim(),
                    ParentId = parentId,
                    Phone = b.phone.trim(),
                    BillingStreet = b.street.trim(),
                    BillingCity = b.city.trim(),
                    BillingPostalCode = b.postcode.trim().toUpperCase(),
                    BillingCountry = String.isBlank(b.country) ? 'United Kingdom' : b.country.trim(),
                    Account_Status__c = 'Draft',
                    Number_of_Branches__c = 1
                ));
            }
            Database.insert(accounts, dml);
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < branches.size(); i++) {
                BranchInput b = branches[i];
                Account a = accounts[i];
                contacts.add(new Contact(
                    FirstName = String.isBlank(b.contactFirstName) ? null : b.contactFirstName.trim(),
                    LastName = b.contactLastName.trim(),
                    Email = b.contactEmail.trim(),
                    Phone = a.Phone,
                    AccountId = a.Id,
                    MailingStreet = a.BillingStreet,
                    MailingCity = a.BillingCity,
                    MailingPostalCode = a.BillingPostalCode,
                    MailingCountry = a.BillingCountry
                ));
            }
            Database.insert(contacts, dml);
            String headOffice = [SELECT Name FROM Account WHERE Id = :parentId].Name;
            return accounts.size() + ' branch' + (accounts.size() == 1 ? '' : 'es') + ' and ' + contacts.size()
                + ' contact' + (contacts.size() == 1 ? '' : 's') + ' added to ' + headOffice + '.';
        } catch (Exception e) {
            Database.rollback(sp);
            throw auraError('Nothing was created: ' + e.getMessage());
        }
    }

    // ---- validation

    public static CheckResult check(Id parentId, List<BranchInput> branches) {
        CheckResult res = new CheckResult();
        Account parent = [SELECT Id, Name, ParentId FROM Account WHERE Id = :parentId];
        if (parent.ParentId != null) {
            res.errors.add('Branches can only be added to a head office (top-level agency). ' + parent.Name + ' is itself a branch.');
        }
        if (branches.isEmpty()) {
            res.errors.add('Add at least one branch.');
        }

        Set<String> existingNames = new Set<String>();
        Map<String, String> existingPostcodes = new Map<String, String>();
        for (Account c : [SELECT Name, BillingPostalCode FROM Account WHERE ParentId = :parentId]) {
            existingNames.add(norm(c.Name));
            if (String.isNotBlank(c.BillingPostalCode)) existingPostcodes.put(normPostcode(c.BillingPostalCode), c.Name);
        }
        Set<String> emails = new Set<String>();
        for (BranchInput b : branches) {
            if (String.isNotBlank(b.contactEmail)) emails.add(b.contactEmail.trim().toLowerCase());
        }
        Map<String, String> existingEmails = new Map<String, String>();
        for (Contact c : [SELECT Email, Name, Account.Name FROM Contact WHERE Email IN :emails]) {
            existingEmails.put(c.Email.toLowerCase(), c.Name + (c.Account == null ? '' : ' (' + c.Account.Name + ')'));
        }

        Set<String> batchNames = new Set<String>();
        Map<String, String> batchPostcodes = new Map<String, String>();
        Integer i = 0;
        for (BranchInput b : branches) {
            i++;
            String label = 'Branch ' + i + (String.isBlank(b.name) ? '' : ' (' + b.name.trim() + ')');
            if (String.isBlank(b.name)) res.errors.add(label + ': enter the branch name.');
            if (String.isBlank(b.phone)) res.errors.add(label + ': enter the branch phone number.');
            if (String.isBlank(b.contactLastName)) res.errors.add(label + ': enter the contact person\'s last name.');
            if (String.isBlank(b.contactEmail)) res.errors.add(label + ': enter the contact person\'s email.');
            else if (!EMAIL.matcher(b.contactEmail.trim()).matches()) res.errors.add(label + ': "' + b.contactEmail + '" is not a valid email address.');
            if (String.isBlank(b.street) || String.isBlank(b.city) || String.isBlank(b.postcode)) {
                res.errors.add(label + ': enter the street, city and postcode.');
            }
            if (String.isNotBlank(b.name)) {
                String n = norm(b.name);
                if (existingNames.contains(n)) res.warnings.add(label + ': a branch with this name already exists under ' + parent.Name + '.');
                if (batchNames.contains(n)) res.warnings.add(label + ': this branch name is entered more than once.');
                batchNames.add(n);
            }
            if (String.isNotBlank(b.postcode)) {
                String pc = normPostcode(b.postcode);
                if (existingPostcodes.containsKey(pc)) res.warnings.add(label + ': postcode ' + b.postcode + ' is already used by branch ' + existingPostcodes.get(pc) + '.');
                if (batchPostcodes.containsKey(pc)) res.warnings.add(label + ': same postcode as ' + batchPostcodes.get(pc) + '.');
                batchPostcodes.put(pc, String.isBlank(b.name) ? 'another branch' : b.name.trim());
            }
            if (String.isNotBlank(b.contactEmail) && existingEmails.containsKey(b.contactEmail.trim().toLowerCase())) {
                res.warnings.add(label + ': ' + b.contactEmail + ' already belongs to contact ' + existingEmails.get(b.contactEmail.trim().toLowerCase()) + '.');
            }
        }
        res.hasErrors = !res.errors.isEmpty();
        return res;
    }

    /** Keeps Number of Branches on head offices = branches + 1 (the head office itself). */
    public static void recountBranches(Set<Id> parentIds) {
        parentIds.remove(null);
        if (parentIds.isEmpty()) return;
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Id p : parentIds) counts.put(p, 0);
        for (AggregateResult ar : [SELECT ParentId p, COUNT(Id) n FROM Account WHERE ParentId IN :parentIds GROUP BY ParentId]) {
            counts.put((Id) ar.get('p'), (Integer) ar.get('n'));
        }
        List<Account> updates = new List<Account>();
        for (Account a : [SELECT Id, Number_of_Branches__c FROM Account WHERE Id IN :parentIds]) {
            Integer total = counts.get(a.Id) + 1;
            if (a.Number_of_Branches__c != total) updates.add(new Account(Id = a.Id, Number_of_Branches__c = total));
        }
        update updates;
    }

    // ---- helpers

    private static List<BranchInput> parse(String branchesJson) {
        if (String.isBlank(branchesJson)) return new List<BranchInput>();
        try {
            return (List<BranchInput>) JSON.deserialize(branchesJson, List<BranchInput>.class);
        } catch (Exception e) {
            throw auraError('The branch details could not be read: ' + e.getMessage());
        }
    }
    private static String norm(String s) { return s == null ? '' : s.trim().toLowerCase().replaceAll('\\s+', ' '); }
    private static String normPostcode(String s) { return s == null ? '' : s.replaceAll('\\s', '').toUpperCase(); }
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}