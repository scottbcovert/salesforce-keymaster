public class KeyMasterService {

    private static final String STATE_KEYWORD = 'STATE';
    private static final String USER_KEYWORD = 'Unknown';
    private static final String DEFAULT_PUSH_MESSAGE = 'Door ' + STATE_KEYWORD + ' by ' + USER_KEYWORD;
    private static final String LOCKED_STATE = 'Locked';
    private static final String LOCKED_COMMAND = 'close';
    private static final String UNLOCKED_STATE = 'Unlocked';
    private static final String UNLOCKED_COMMAND = 'open';
    private static final String DOOR_STATE_KEY = 'doorState';
    private static final String UNKNOWN_DOOR_STATE = 'unknown';
    private static final String ENDPOINT_KEYWORD = 'endpoint';
    private static final String PARTICLE_TOGGLE_LOCK_ENDPOINT = 'toggleLock';
    private static final String PARTICLE_DOOR_STATE_ENDPOINT = 'lockState';
    private static final String PARTICLE_API_CREDS_NAME = 'GateKeeper';
    private static final list<ParticleAPICreds__mdt> PARTICLE_API_CREDS = [SELECT DeviceId__c, AccessToken__c FROM ParticleAPICreds__mdt WHERE DeveloperName = :PARTICLE_API_CREDS_NAME LIMIT 1];
    private static final String PARTICLE_API_DEVICE_ID = (PARTICLE_API_CREDS.size() > 0) ? PARTICLE_API_CREDS[0].DeviceId__c : '';
    private static final String PARTICLE_API_ACCESS_TOKEN = (PARTICLE_API_CREDS.size() > 0) ? PARTICLE_API_CREDS[0].AccessToken__c : '';
    private static final String PARTICLE_API_URL = 'https://api.particle.io/v1/devices/'+ PARTICLE_API_DEVICE_ID +'/' + ENDPOINT_KEYWORD + '?access_token=' + PARTICLE_API_ACCESS_TOKEN;

    public static Map<String,String> getDoorState(String passphrase)
    {
        list<AccessToken__c> accessToken = [SELECT User__c, Contact__c FROM AccessToken__c WHERE Passphrase__c = :passphrase AND Expired__c = false LIMIT 1];
        if (accessToken.size() == 0) return new Map<String,String>{ DOOR_STATE_KEY => UNKNOWN_DOOR_STATE };
        return new Map<String,String>{ DOOR_STATE_KEY => KeyMasterService.sendDoorStateCallout() };
    }

    public static Boolean createLockEvent(String newState, String passphrase)
    {
        String parentObject;
        String parentId;
        list<SObject> parentObjectRecord;
        String stateChangedBy;
        list<AccessToken__c> accessToken = [SELECT User__c, Contact__c FROM AccessToken__c WHERE Passphrase__c = :passphrase AND Expired__c = false LIMIT 1];
        if (accessToken.size() == 0) return false;
        if (accessToken[0].User__c!=null) {
            parentObject = 'User';
            parentId = accessToken[0].User__c;
        } else if (accessToken[0].Contact__c!=null) {
            parentObject = 'Contact';
            parentId = accessToken[0].Contact__c;
        }
        if (parentObject == null) return false;
        parentObjectRecord = Database.query('SELECT Name FROM ' + parentObject + ' WHERE Id = \'' + parentId + '\'');
        if (parentObjectRecord.size()==0) return false;
        stateChangedBy = String.valueOf(parentObjectRecord[0].get('Name'));
        if (KeyMasterService.sendToggleStateCallout(newState, stateChangedBy) == 200) {
            sendToggleStatePushNotification(DEFAULT_PUSH_MESSAGE.replace(STATE_KEYWORD,newState.toLowerCase()).replace(USER_KEYWORD,stateChangedBy));
            insert (new LockEvent__c(NewState__c = newState, StateChangedBy__c = stateChangedBy));
            return true;
        }
        else {
            return false;
        }
    }

    public static void createAccessToken(Map<Id,User> newUsersMap, Map<Id,User> oldUsersMap) {
        List<User> newKeyMasterUsers = new List<User>();
        List<AccessToken__c> newAccessTokens = new List<AccessToken__c>();
        Datetime now = System.now();
        String formattedNow = now.formatGmt('yyyy-MM-dd')+'T'+ now.formatGmt('HH:mm:ss')+'.'+now.formatGMT('SSS')+'Z';
        String canonical;
        Blob keyBlob;
        String passphrase;
        for (User u : newUsersMap.values()) {
            if (u.KeyMasterAccess__c && (oldUsersMap == null || !(oldUsersMap.get(u.Id).KeyMasterAccess__c)) ) {
                newKeyMasterUsers.add(u);
            }
        }
        for (User u : newKeyMasterUsers) {
            canonical = u.Id + formattedNow;
            keyBlob = Crypto.generateDigest('MD5', Blob.valueOf(canonical));
            passphrase = EncodingUtil.base64Encode(keyBlob);
            if(passphrase.length() > 255) {
                passphrase = passphrase.substring(0, 254);
            }
            newAccessTokens.add((new AccessToken__c(
                    User__c = u.Id,
                    Expiration__c = now.addDays(7),
                    Passphrase__c = passphrase
            )));
        }
        if (newAccessTokens.size() > 0) {
            insert newAccessTokens;
        }
    }

    private static Integer sendToggleStateCallout(String newState, String stateChangedBy)
    {
        String stateCommand = (newState == LOCKED_STATE) ? LOCKED_COMMAND : UNLOCKED_COMMAND;
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();
        req.setEndpoint(PARTICLE_API_URL.replace(ENDPOINT_KEYWORD,PARTICLE_TOGGLE_LOCK_ENDPOINT));
        req.setMethod('POST');
        req.setCompressed(false);
        req.setBody('params='+stateCommand);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        try {
            res = http.send(req);
        } catch(System.CalloutException e) {
            System.debug('Callout error: '+ e.getMessage());
            return 0;
        }
        return res.getStatusCode();
    }

    private static String sendDoorStateCallout()
    {
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();
        String result;
        String doorState;
        req.setEndpoint(PARTICLE_API_URL.replace(ENDPOINT_KEYWORD,PARTICLE_DOOR_STATE_ENDPOINT));
        req.setMethod('GET');
        req.setCompressed(false);
        try {
            res = http.send(req);
        } catch(System.CalloutException e) {
            System.debug('Callout error: '+ e.getMessage());
            return UNKNOWN_DOOR_STATE;
        }
        result = String.valueOf(((Map<String,Object>)JSON.deserializeUntyped(res.getBody())).get('result'));
        if (result==UNLOCKED_COMMAND) {
            doorState = UNLOCKED_STATE.toLowerCase();
        } else if (result==LOCKED_COMMAND) {
            doorState = LOCKED_STATE.toLowerCase();
        } else {
            doorState = UNKNOWN_DOOR_STATE;
        }
        return doorState;
    }

    private static void sendToggleStatePushNotification(String message)
    {
        Messaging.PushNotification msg = new Messaging.PushNotification();
        Map<String, Object> payload = Messaging.PushNotificationPayload.apple(message, 'default', null, null);
        msg.setPayload(payload);
        Map<Id,User> keyMasterUsers = new Map<Id,User>([SELECT Id, FirstName, LastName FROM User WHERE KeyMasterAccess__c = true]);
        msg.send('KeyMaster', (Set<String>)JSON.deserialize(JSON.serialize(keyMasterUsers.keySet()), Set<String>.class));
    }
}