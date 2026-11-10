@IsTest
private class GoodLettrTextCleanerTest {

    @IsTest
    static void cleanReplacesLineBreaksAndTabs() {
        Assert.areEqual('a b c d', GoodLettrTextCleaner.clean('a\r\nb\nc\td'));
        Assert.isNull(GoodLettrTextCleaner.clean(null));

        GoodLettrTextCleaner.Request req = new GoodLettrTextCleaner.Request();
        req.enquiryNotes = 'line one\nline two';
        req.conversationNotes = null;
        List<GoodLettrTextCleaner.Result> res = GoodLettrTextCleaner.removeLineBreaks(new List<GoodLettrTextCleaner.Request>{ req, null });
        Assert.areEqual('line one line two', res[0].enquiryNotes);
        Assert.isNull(res[0].conversationNotes);
        Assert.isNull(res[1].enquiryNotes);
    }

    @IsTest
    static void leadScoringMatchesPhrasesNextToLineBreaks() {
        // Runs the Lead - Calculate Lead Score flow with the deployed Lead Score Rule metadata.
        Lead l = new Lead(LastName = 'Scoring Test', Company = 'Test Agency', Email = 'test@agency-example.co.uk',
                          Conversation_Notes__c = 'Call notes:\ndemo booked\r\nspoke with the director\n');
        insert l;
        Lead r = [SELECT Lead_Score__c, Lead_Score_Reason__c FROM Lead WHERE Id = :l.Id];
        Assert.isTrue(r.Lead_Score_Reason__c.contains('demo'), r.Lead_Score_Reason__c);
        Assert.isTrue(r.Lead_Score_Reason__c.contains('director'), r.Lead_Score_Reason__c);
        Assert.isTrue(r.Lead_Score__c > 0);
    }
}