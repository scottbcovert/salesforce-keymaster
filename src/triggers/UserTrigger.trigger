trigger UserTrigger on User (after insert, after update) {
    KeyMasterService.createAccessToken(Trigger.newMap,(Trigger.isUpdate) ? Trigger.oldMap : null);
}