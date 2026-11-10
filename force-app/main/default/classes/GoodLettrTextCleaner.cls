/**
 * Invocable helper for the "Lead - Calculate Lead Score" flow.
 * Flow formulas cannot reference line-break characters, so phrases next to a line break in the notes
 * would not be matched. This action replaces line breaks, tabs and non-breaking spaces with plain spaces.
 * All scoring rules and logic stay in the flow and the Lead Score Rule custom metadata.
 */
public with sharing class GoodLettrTextCleaner {

    public class Request {
        @InvocableVariable(label='Enquiry Notes')
        public String enquiryNotes;
        @InvocableVariable(label='Conversation Notes')
        public String conversationNotes;
    }

    public class Result {
        @InvocableVariable(label='Enquiry Notes (cleaned)')
        public String enquiryNotes;
        @InvocableVariable(label='Conversation Notes (cleaned)')
        public String conversationNotes;
    }

    @InvocableMethod(
        label='Remove Line Breaks'
        description='Replaces line breaks, tabs and non-breaking spaces in the notes with spaces, for phrase matching in lead scoring.'
        category='GoodLettr'
    )
    public static List<Result> removeLineBreaks(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.enquiryNotes = clean(r?.enquiryNotes);
            res.conversationNotes = clean(r?.conversationNotes);
            results.add(res);
        }
        return results;
    }

    public static String clean(String text) {
        if (text == null) {
            return null;
        }
        return text.replaceAll('[\\r\\n\\t\\u00A0\\u2028\\u2029]+', ' ');
    }
}