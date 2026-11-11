/** Makes the only contact on a top-level agency its group's primary contact (see GoodLettrPrimaryContactService). */
trigger ContactPrimaryTrigger on Contact (after insert) {
    GoodLettrPrimaryContactService.assignDefaultPrimary(Trigger.new);
}