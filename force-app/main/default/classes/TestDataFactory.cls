@IsTest
public class TestDataFactory {

    public static Vehicle__c createVehicle(String vehicleNumber) {
        Vehicle__c v = new Vehicle__c(Name = vehicleNumber, Vehicle_Number__c = vehicleNumber);
        insert v;
        return v;
    }

    public static Delivery__c delivery(String number, Id accountId, Id vehicleId, String status) {
        return new Delivery__c(
            Name = number,
            Delivery_Number__c = number,
            Account__c = accountId,
            Vehicle__c = vehicleId,
            Status__c = status,
            Expected_Date__c = Date.today().addDays(1),
            Destination__c = 'Test City'
        );
    }

    public static Incident__c createIncident(String externalId, String severity) {
        Incident__c i = new Incident__c(
            Name = externalId,
            Incident_External_Id__c = externalId,
            Type__c = 'Delay',
            Severity__c = severity,
            Processing_Status__c = 'Processed'
        );
        insert i;
        return i;
    }

    public static String payload(String incidentId, String vehicleNumber, String severity) {
        return JSON.serialize(new Map<String, Object>{
            'incidentId' => incidentId,
            'vehicleNumber' => vehicleNumber,
            'type' => 'Breakdown',
            'severity' => severity,
            'description' => 'Engine failure on highway',
            'reportedAt' => '2026-11-02T10:05:00Z'
        });
    }

    /** Calls the REST endpoint exactly as an external system would. */
    public static RestResponse post(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/fleet/incidents';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        IncidentRestService.createIncident();
        return RestContext.response;
    }

    public static Map<String, Object> bodyOf(RestResponse res) {
        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }
}
