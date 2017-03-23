trigger LockEventTrigger on LockEvent__c (before insert) {
	LockEventHandler.toggleState(Trigger.new);
}