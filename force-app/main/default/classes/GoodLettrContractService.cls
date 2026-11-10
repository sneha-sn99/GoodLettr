/**
 * Server logic for the Opportunity quick actions "Generate Contract PDF" and "Send Contract Email".
 * - Renders the GoodLettrContract Visualforce page as a PDF
 * - Saves the PDF to the Opportunity's Files
 * - Emails the PDF to an agency contact, logs the email on the Opportunity, then saves the sent PDF to Files
 */
public with sharing class GoodLettrContractService {

    public class Recipient {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String email;
    }

    public class SendContext {
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean hasLines;
        @AuraEnabled public List<Recipient> recipients;
        @AuraEnabled public String defaultSubject;
        @AuraEnabled public String defaultBody;
    }

    /** Contacts with an email: Opportunity contact roles first (primary first), then the Account's contacts. */
    public static List<Contact> getAgencyContacts(Id oppId, Id accountId) {
        Map<Id, Contact> ordered = new Map<Id, Contact>();
        for (OpportunityContactRole r : [
            SELECT Contact.Id, Contact.Name, Contact.Email, Contact.Title, Contact.MailingStreet,
                   Contact.MailingCity, Contact.MailingPostalCode
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId AND Contact.Email != null
            ORDER BY IsPrimary DESC, CreatedDate
        ]) {
            ordered.put(r.Contact.Id, r.Contact);
        }
        if (accountId != null) {
            for (Contact c : [
                SELECT Id, Name, Email, Title, MailingStreet, MailingCity, MailingPostalCode
                FROM Contact
                WHERE AccountId = :accountId AND Email != null
                ORDER BY CreatedDate
                LIMIT 50
            ]) {
                if (!ordered.containsKey(c.Id)) {
                    ordered.put(c.Id, c);
                }
            }
        }
        return ordered.values();
    }

    @AuraEnabled
    public static SendContext getSendContext(Id opportunityId) {
        Opportunity opp = loadOpportunity(opportunityId);
        SendContext ctx = new SendContext();
        ctx.opportunityName = opp.Name;
        ctx.accountName = opp.Account?.Name;
        ctx.hasLines = [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opportunityId] > 0;
        ctx.recipients = new List<Recipient>();
        for (Contact c : getAgencyContacts(opp.Id, opp.AccountId)) {
            Recipient r = new Recipient();
            r.id = c.Id;
            r.email = c.Email;
            r.label = c.Name + ' <' + c.Email + '>' + (String.isBlank(c.Title) ? '' : ' - ' + c.Title);
            ctx.recipients.add(r);
        }
        String agency = String.isBlank(ctx.accountName) ? 'your agency' : ctx.accountName;
        ctx.defaultSubject = 'GoodLettr Tenancy Management Software - Contract for ' + agency;
        ctx.defaultBody =
            'Hello,\n\n' +
            'Thank you for choosing GoodLettr. Please find attached the contract for ' + agency +
            ', setting out the services and commercial terms we discussed.\n\n' +
            'Please review it and sign and return it at your convenience. ' +
            'If you have any questions, just reply to this email.\n\n' +
            'Kind regards,\n' + UserInfo.getName() + '\nGoodLettr';
        return ctx;
    }

    /**
     * Called when the Generate Contract PDF action is opened. Stamps Contract_Generated_On__c; the
     * "Opportunity Contract Stage Automation" flow then moves the stage to Proposal/Price Quote.
     */
    @AuraEnabled
    public static void markContractGenerated(Id opportunityId) {
        try {
            update new Opportunity(Id = opportunityId, Contract_Generated_On__c = Datetime.now());
        } catch (Exception e) {
            throw auraError('Could not update the Opportunity: ' + e.getMessage());
        }
    }

    /** Generates the contract PDF and saves it to the Opportunity's Files. Returns the ContentDocumentId. */
    @AuraEnabled
    public static Id saveContractToFiles(Id opportunityId) {
        try {
            Opportunity opp = loadOpportunity(opportunityId);
            Blob pdf = renderPdf(opportunityId);
            return saveFile(opp, pdf, false);
        } catch (Exception e) {
            throw auraError('Could not save the contract: ' + e.getMessage());
        }
    }

    /**
     * Generates the contract PDF, emails it to the chosen agency contact (plus optional CC addresses),
     * logs the email against the Opportunity, and then saves the sent PDF to the Opportunity's Files.
     * Returns the ContentDocumentId of the saved file.
     */
    @AuraEnabled
    public static Id sendContract(Id opportunityId, Id contactId, List<String> ccAddresses, String subject, String body) {
        if (contactId == null) {
            throw auraError('Choose an agency contact to send the contract to.');
        }
        if (String.isBlank(subject)) {
            throw auraError('Enter an email subject.');
        }
        Opportunity opp = loadOpportunity(opportunityId);
        Blob pdf;
        try {
            pdf = renderPdf(opportunityId);
        } catch (Exception e) {
            throw auraError('Could not generate the contract PDF: ' + e.getMessage());
        }

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(fileName(opp) + '.pdf');
        att.setContentType('application/pdf');
        att.setBody(pdf);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(contactId);
        mail.setWhatId(opportunityId);
        mail.setSaveAsActivity(true);
        mail.setSenderDisplayName('GoodLettr');
        mail.setSubject(subject);
        mail.setPlainTextBody(body == null ? '' : body);
        List<String> cc = new List<String>();
        if (ccAddresses != null) {
            for (String a : ccAddresses) {
                if (String.isNotBlank(a)) {
                    cc.add(a.trim());
                }
            }
        }
        if (!cc.isEmpty()) {
            mail.setCcAddresses(cc);
        }
        mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw auraError('The email was not sent: ' + e.getMessage());
        }
        // Email sent: keep a copy of exactly what was sent in the Opportunity's Files, then stamp
        // Contract_Sent_On__c so the stage flow moves the Opportunity to Negotiation/Review.
        Id docId = saveFile(opp, pdf, true);
        update new Opportunity(Id = opportunityId, Contract_Sent_On__c = Datetime.now());
        return docId;
    }

    // ---- helpers ----

    @TestVisible
    private static Blob renderPdf(Id opportunityId) {
        PageReference page = Page.GoodLettrContract;
        page.getParameters().put('id', opportunityId);
        if (Test.isRunningTest()) {
            return Blob.valueOf('Test contract PDF');
        }
        return page.getContentAsPDF();
    }

    private static Id saveFile(Opportunity opp, Blob pdf, Boolean sent) {
        String title = fileName(opp) + (sent ? ' (Sent ' + Datetime.now().format('yyyy-MM-dd HH:mm') + ')' : ' (Draft)');
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = pdf,
            FirstPublishLocationId = opp.Id
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    private static String fileName(Opportunity opp) {
        String agency = opp.Account?.Name != null ? opp.Account.Name : opp.Name;
        return 'GoodLettr Contract - ' + agency + ' - ' + Datetime.now().format('yyyy-MM-dd');
    }

    private static Opportunity loadOpportunity(Id opportunityId) {
        List<Opportunity> opps = [SELECT Id, Name, AccountId, Account.Name FROM Opportunity WHERE Id = :opportunityId];
        if (opps.isEmpty()) {
            throw auraError('Opportunity not found or not accessible.');
        }
        return opps[0];
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}