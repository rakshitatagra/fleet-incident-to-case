/**
 * All SOQL for the incident flow lives here (user-mode, so object/field security is enforced).
 */
public with sharing class IncidentSelector {

    public static Vehicle__c findVehicle(String vehicleNumber) {
        List<Vehicle__c> vehicles = [
            SELECT Id, Name, Vehicle_Number__c
            FROM Vehicle__c
            WHERE Vehicle_Number__c = :vehicleNumber
            WITH USER_MODE
            LIMIT 1
        ];
        return vehicles.isEmpty() ? null : vehicles[0];
    }

    /** Deliveries that are still relevant to customers: anything not Delivered or Cancelled. */
    public static List<Delivery__c> activeDeliveries(Id vehicleId) {
        return [
            SELECT Id, Name, Delivery_Number__c, Account__c, Status__c, Expected_Date__c, Destination__c
            FROM Delivery__c
            WHERE Vehicle__c = :vehicleId
              AND Status__c NOT IN ('Delivered', 'Cancelled')
            WITH USER_MODE
            ORDER BY Delivery_Number__c
            LIMIT 10000
        ];
    }

    public static Set<String> existingCaseKeys(Set<String> keys) {
        Set<String> found = new Set<String>();
        if (keys.isEmpty()) {
            return found;
        }
        for (Case c : [
            SELECT Case_Key__c
            FROM Case
            WHERE Case_Key__c IN :keys
            WITH USER_MODE
        ]) {
            found.add(c.Case_Key__c);
        }
        return found;
    }

    /**
     * Returns the queue's Id only if it exists AND is allowed to own Cases.
     * Returns null otherwise, so callers can safely fall back to the default owner.
     */
    public static Id caseQueueId(String queueDeveloperName) {
        List<QueueSobject> rows = [
            SELECT QueueId
            FROM QueueSobject
            WHERE SobjectType = 'Case'
              AND Queue.DeveloperName = :queueDeveloperName
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].QueueId;
    }
}
