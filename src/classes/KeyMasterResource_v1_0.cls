@RestResource(urlMapping='/v1.0/keymaster')
global with sharing class KeyMasterResource_v1_0
{
    @HttpGet
    global static void GetDoorState()
    {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        Map<String,Object> responseMap = new Map<String,Object>();
        try
        {
            responseMap.put('data',KeyMasterService.getDoorState(req.params.get('passphrase')));
        }
        catch(Exception ex){
            responseMap.put('data',null);
        }
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf( JSON.serializePretty(responseMap) );
    }

    @HttpPost
    global static void ToggleLock()
    {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        Map<String,Object> responseMap = new Map<String,Object>();
        try
        {
            responseMap.put('isSuccess',KeyMasterService.createLockEvent(req.params.get('newState'),req.params.get('passphrase')));
        }
        catch(Exception ex){
            responseMap.put('isSuccess',false);
        }
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf( JSON.serializePretty(responseMap) );
    }
}