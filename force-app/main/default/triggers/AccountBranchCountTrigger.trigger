/**
 * Account automation:
 * - before insert/update: Is Primary Account = true when the account has no parent (top account), false for branches.
 * - after insert/update/delete/undelete: Number of Branches on the head office = number of branch accounts + 1.
 */
trigger AccountBranchCountTrigger on Account (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        for (Account a : Trigger.new) {
            a.Is_Primary_Account__c = (a.ParentId == null);
        }
        return;
    }
    Set<Id> parentIds = new Set<Id>();
    if (Trigger.isDelete) {
        for (Account a : Trigger.old) parentIds.add(a.ParentId);
    } else {
        for (Account a : Trigger.new) {
            if (Trigger.isUpdate) {
                Account old = Trigger.oldMap.get(a.Id);
                if (old.ParentId == a.ParentId) continue;
                parentIds.add(old.ParentId);
            }
            parentIds.add(a.ParentId);
        }
    }
    GoodLettrBranchService.recountBranches(parentIds);
}