/**
 * Server logic for the Order quick action "Send Invoice".
 * Until a billing system is integrated: renders the invoice PDF, emails it to the Order's bill-to contact,
 * saves it to the Order's Files, logs the email on the Order, and moves the Order to "Billed"
 * (with Invoice Number, Invoice Date and Invoice Due Date).
 * "Billing Processed" is set later by the financial system when payment is received.
 */
public with sharing class GoodLettrInvoiceService {

    public static final Integer PAYMENT_TERMS_DAYS = 30;
    public static final Set<String> INVOICEABLE_STATUSES = new Set<String>{ 'Draft', 'Activated' };

    public class InvoiceContext {
        @AuraEnabled public Boolean canSend;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String billToName;
        @AuraEnabled public String billToEmail;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String defaultSubject;
        @AuraEnabled public String defaultBody;
    }

    public static String invoiceNumberFor(Order o) {
        return String.isNotBlank(o.Invoice_Number__c) ? o.Invoice_Number__c : 'INV-' + o.OrderNumber;
    }

    public static Integer monthsIn(String frequency) {
        return frequency == 'Annual' ? 12 : frequency == 'Quarterly' ? 3 : 1;
    }

    @AuraEnabled
    public static InvoiceContext getInvoiceContext(Id orderId) {
        Order o = loadOrder(orderId);
        Integer lineCount = [SELECT COUNT() FROM OrderItem WHERE OrderId = :orderId];
        InvoiceContext ctx = new InvoiceContext();
        ctx.orderNumber = o.OrderNumber;
        ctx.status = o.Status;
        ctx.accountName = o.Account?.Name;
        ctx.billToName = o.BillToContact?.Name;
        ctx.billToEmail = o.BillToContact?.Email;
        ctx.amount = o.TotalAmount;
        ctx.invoiceNumber = invoiceNumberFor(o);
        ctx.dueDate = Date.today().addDays(PAYMENT_TERMS_DAYS);
        ctx.blockedReason = blockedReason(o, lineCount);
        ctx.canSend = ctx.blockedReason == null;
        String agency = String.isBlank(ctx.accountName) ? 'your agency' : ctx.accountName;
        ctx.defaultSubject = 'GoodLettr invoice ' + ctx.invoiceNumber + ' - ' + agency;
        ctx.defaultBody =
            'Hello' + (String.isBlank(o.BillToContact?.FirstName) ? '' : ' ' + o.BillToContact.FirstName) + ',\n\n' +
            'Please find attached invoice ' + ctx.invoiceNumber + ' for your GoodLettr Tenancy Management Software subscription.\n\n' +
            'Amount due: £' + (o.TotalAmount == null ? '0.00' : String.valueOf(o.TotalAmount.setScale(2))) +
            '\nDue date: ' + Datetime.newInstance(ctx.dueDate, Time.newInstance(0, 0, 0, 0)).format('d MMMM yyyy') + '\n\n' +
            'Thank you for your business.\n\nKind regards,\n' + UserInfo.getName() + '\nGoodLettr';
        return ctx;
    }

    /** Sends the invoice and moves the Order to Billed. Returns the ContentDocumentId of the invoice saved to Files. */
    @AuraEnabled
    public static Id sendInvoice(Id orderId, List<String> ccAddresses, String subject, String body) {
        Order o = loadOrder(orderId);
        Integer lineCount = [SELECT COUNT() FROM OrderItem WHERE OrderId = :orderId];
        String reason = blockedReason(o, lineCount);
        if (reason != null) {
            throw auraError(reason);
        }
        if (String.isBlank(subject)) {
            throw auraError('Enter an email subject.');
        }
        String invoiceNumber = invoiceNumberFor(o);
        Blob pdf;
        try {
            pdf = renderPdf(orderId);
        } catch (Exception e) {
            throw auraError('Could not generate the invoice PDF: ' + e.getMessage());
        }
        String fileTitle = 'GoodLettr Invoice ' + invoiceNumber + ' - ' + (o.Account?.Name == null ? o.OrderNumber : o.Account.Name);

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(fileTitle + '.pdf');
        att.setContentType('application/pdf');
        att.setBody(pdf);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(o.BillToContactId);
        mail.setWhatId(orderId);
        mail.setSaveAsActivity(true);
        mail.setSenderDisplayName('GoodLettr');
        mail.setSubject(subject);
        mail.setPlainTextBody(body == null ? '' : body);
        List<String> cc = new List<String>();
        if (ccAddresses != null) {
            for (String a : ccAddresses) {
                if (String.isNotBlank(a)) cc.add(a.trim());
            }
        }
        if (!cc.isEmpty()) mail.setCcAddresses(cc);
        mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw auraError('The invoice was not sent: ' + e.getMessage());
        }

        ContentVersion cv = new ContentVersion(Title = fileTitle, PathOnClient = fileTitle + '.pdf', VersionData = pdf, FirstPublishLocationId = orderId);
        insert cv;
        Date today = Date.today();
        update new Order(
            Id = orderId,
            Status = 'Billed',
            Invoice_Number__c = invoiceNumber,
            Invoice_Date__c = today,
            Invoice_Due_Date__c = today.addDays(PAYMENT_TERMS_DAYS)
        );
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    // ---- helpers

    private static String blockedReason(Order o, Integer lineCount) {
        if (!INVOICEABLE_STATUSES.contains(o.Status)) {
            return 'This Order is already "' + o.Status + '". Only Draft or Activated Orders can be invoiced.';
        }
        if (lineCount == 0) {
            return 'This Order has no products to invoice.';
        }
        if (o.BillToContactId == null || String.isBlank(o.BillToContact?.Email)) {
            return 'Set a Bill To Contact with an email address on the Order before sending the invoice.';
        }
        return null;
    }

    @TestVisible
    private static Blob renderPdf(Id orderId) {
        PageReference page = Page.GoodLettrInvoice;
        page.getParameters().put('id', orderId);
        if (Test.isRunningTest()) {
            return Blob.valueOf('Test invoice PDF');
        }
        return page.getContentAsPDF();
    }

    private static Order loadOrder(Id orderId) {
        List<Order> orders = [
            SELECT Id, OrderNumber, Status, TotalAmount, Invoice_Number__c, Account.Name, BillToContactId,
                   BillToContact.Name, BillToContact.FirstName, BillToContact.Email
            FROM Order WHERE Id = :orderId
        ];
        if (orders.isEmpty()) {
            throw auraError('Order not found or not accessible.');
        }
        return orders[0];
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}