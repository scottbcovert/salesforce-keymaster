public class LockEventHandler {

    private static final String STATE_KEYWORD = 'STATE';
    private static final String USER_KEYWORD = 'USER';
    private static final String DEFAULT_PUSH_MESSAGE = 'Door ' + STATE_KEYWORD + ' by ' + USER_KEYWORD;
    private static final String LOCKED_STATE = 'Locked';
    private static final String LOCKED_COMMAND = 'close';
    private static final String UNLOCKED_STATE = 'Unlocked';
    private static final String UNLOCKED_COMMAND = 'open';
    private static final String PARTICLE_API_CREDS_NAME = 'GateKeeper';
    private static final list<ParticleAPICreds__mdt> PARTICLE_API_CREDS = [SELECT DeviceId__c, AccessToken__c FROM ParticleAPICreds__mdt WHERE DeveloperName = :PARTICLE_API_CREDS_NAME LIMIT 1];
    private static final String PARTICLE_API_DEVICE_ID = (PARTICLE_API_CREDS.size() > 0) ? PARTICLE_API_CREDS[0].DeviceId__c : '';
    private static final String PARTICLE_API_ACCESS_TOKEN = (PARTICLE_API_CREDS.size() > 0) ? PARTICLE_API_CREDS[0].AccessToken__c : '';
    private static final String PARTICLE_API_URL = 'https://api.particle.io/v1/devices/'+ PARTICLE_API_DEVICE_ID +'/toggleLock?access_token=' + PARTICLE_API_ACCESS_TOKEN;
    
    public static void toggleState(List<LockEvent__c> lockEvents)
    {
        LockEvent__c finalEvent;
        String runningUserName = (UserInfo.getFirstName()!=null && UserInfo.getFirstName()!='') ? UserInfo.getFirstName() + ' ' + UserInfo.getLastName() : UserInfo.getLastName();
        for (LockEvent__c event : lockEvents)
        {
            event.StateChangedBy__c = (event.StateChangedBy__c == null) ? runningUserName : event.StateChangedBy__c;
            finalEvent = event;
        }
        if (finalEvent.NewState__c!=null) sendToggleStateCallout(finalEvent.NewState__c, finalEvent.StateChangedBy__c);
    }
    
    @future(callout=true)
    private static void sendToggleStateCallout(String newState, String submittedBy)
    {
        String stateCommand = (newState == LOCKED_STATE) ? LOCKED_COMMAND : UNLOCKED_COMMAND;
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();        
        req.setEndpoint(PARTICLE_API_URL);
        req.setMethod('POST');
        req.setCompressed(false);
        req.setBody('params='+stateCommand);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');          
        try {
            res = http.send(req);
            sendToggleStatePushNotification(DEFAULT_PUSH_MESSAGE.replace(STATE_KEYWORD,newState.toLowerCase()).replace(USER_KEYWORD,submittedBy));
        } catch(System.CalloutException e) {
            System.debug('Callout error: '+ e);
        }
        System.debug(res.getBody());        
    }
    
    private static void sendToggleStatePushNotification(String message)
    {
        Messaging.PushNotification msg = new Messaging.PushNotification();
        Map<String, Object> payload = Messaging.PushNotificationPayload.apple(message, 'default', null, null);
        msg.setPayload(payload);
        Map<Id,User> keyMasterUsers = new Map<Id,User>([SELECT Id, FirstName, LastName FROM User WHERE LastName = 'Covert']);
        msg.send('KeyMaster', (Set<String>)JSON.deserialize(JSON.serialize(keyMasterUsers.keySet()), Set<String>.class));
    }
}