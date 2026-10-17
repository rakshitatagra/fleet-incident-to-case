/**
 * Business logic: save the incident (idempotent), find affected deliveries, create one Case per delivery.
 *
 * Idempotency:
 *  - Incident__c is upserted on Incident_External_Id__c, so a re-sent event updates, never duplicates.
 *  - Cases are keyed by Case_Key__c = incidentId + '-' + deliveryNumber. Existing keys are skipped
 *    (never overwritten), so a Case an agent already worked or closed is not reset by a re-send.
 *  - A failed or partial run can simply be re-sent: only the missing Cases are created.
 */
public with sharing class IncidentService {

    public static final String SUPPORT_QUEUE = 'Fleet_Support_Queue';

    public class Result {
        public Integer statusCode = 200;
        public String status;
        public String incidentId;
        public Integer casesCreated = 0;
        public Integer casesAlreadyExisting = 0;
        public Integer deliveriesSkipped = 0;
        public String message;
    }

    private static final Map<String, Integer> DEADLINE_MINUTES = new Map<String, Integer>{
        'Critical' => 60,
        'High' => 240,
        'Medium' => 480,
        'Low' => 1440
    };
    private static final Map<String, String> PRIORITY_BY_SEVERITY = new Map<String, String>{
        'Critical' => 'High',
        'High' => 'High',
        'Medium' => 'Medium',
        'Low' => 'Low'
    };

    public static Result process(IncidentRequest req) {
        Result res = new Result();
        res.incidentId = req.incidentId;

        Vehicle__c vehicle = IncidentSelector.findVehicle(req.vehicleNumber);
        Boolean unknownVehicle = (vehicle == null);

        Incident__c incident = new Incident__c(
            Name = req.incidentId,
            Incident_External_Id__c = req.incidentId,
            Type__c = req.type,
            Severity__c = req.severity,
            Description__c = req.description,
            Reported_At__c = req.reportedAtParsed,
            Vehicle_Number_Raw__c = req.vehicleNumber,
            Vehicle__c = unknownVehicle ? null : vehicle.Id,
            Processing_Status__c = unknownVehicle ? 'Failed' : 'Received',
            Error_Message__c = unknownVehicle ? 'Unknown vehicle: ' + req.vehicleNumber : null
        );

        // 1. Save the incident, even if it can't be processed, so failures are visible in Salesforce.
        List<Database.UpsertResult> upsertResults = Database.upsert(
            new List<Incident__c>{ incident },
            Incident__c.Incident_External_Id__c,
            false,
            AccessLevel.USER_MODE
        );
        Database.UpsertResult ur = upsertResults[0];
        if (!ur.isSuccess()) {
            Database.Error err = ur.getErrors()[0];
            if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                // Two identical requests raced each other; the other one won. Safe to retry.
                res.statusCode = 409;
                res.status = 'Conflict';
                res.message = 'The same incident is being processed by another request. Retry shortly.';
            } else {
                res.statusCode = 500;
                res.status = 'Error';
                res.message = 'Could not save incident: ' + err.getMessage();
            }
            return res;
        }

        if (unknownVehicle) {
            res.statusCode = 404;
            res.status = 'Failed';
            res.message = 'Unknown vehicle: ' + req.vehicleNumber
                + '. Incident saved with status Failed; re-send it once the vehicle exists.';
            return res;
        }

        // 2. Find affected deliveries.
        List<Delivery__c> deliveries = IncidentSelector.activeDeliveries(vehicle.Id);
        if (deliveries.isEmpty()) {
            finalizeIncident(incident.Id, 'No Active Deliveries', 0, null);
            res.status = 'No Active Deliveries';
            res.message = 'Incident saved. Vehicle has no active deliveries, so no Cases were created.';
            return res;
        }

        // 3. Work out which deliveries need a Case.
        Map<String, Delivery__c> deliveryByKey = new Map<String, Delivery__c>();
        List<String> skipped = new List<String>();
        for (Delivery__c d : deliveries) {
            if (d.Account__c == null) {
                skipped.add(d.Delivery_Number__c);
                continue;
            }
            deliveryByKey.put(req.incidentId + '-' + d.Delivery_Number__c, d);
        }
        res.deliveriesSkipped = skipped.size();

        Set<String> existingKeys = IncidentSelector.existingCaseKeys(deliveryByKey.keySet());
        res.casesAlreadyExisting = existingKeys.size();

        Id ownerId = IncidentSelector.caseQueueId(SUPPORT_QUEUE);
        List<Case> toInsert = new List<Case>();
        for (String key : deliveryByKey.keySet()) {
            if (!existingKeys.contains(key)) {
                toInsert.add(buildCase(incident, vehicle, deliveryByKey.get(key), key, ownerId));
            }
        }

        // 4. Create the missing Cases; one bad record must not block the others.
        List<String> errors = new List<String>();
        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(toInsert, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                if (sr.isSuccess()) {
                    res.casesCreated++;
                } else {
                    Database.Error err = sr.getErrors()[0];
                    if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                        res.casesAlreadyExisting++; // created by a racing request
                    } else {
                        errors.add(toInsert[i].Case_Key__c + ': ' + err.getMessage());
                    }
                }
            }
        }

        // 5. Record the outcome on the incident.
        Integer totalCases = res.casesCreated + res.casesAlreadyExisting;
        String note = skipped.isEmpty()
            ? null
            : 'Skipped deliveries with no customer account: ' + String.join(skipped, ', ');

        if (!errors.isEmpty()) {
            String errorText = ('Some Cases failed: ' + String.join(errors, ' | ')).left(2000);
            finalizeIncident(incident.Id, 'Failed', totalCases, errorText);
            res.statusCode = 500;
            res.status = 'Failed';
            res.message = 'Partially processed. Safe to re-send: only the missing Cases will be created. ' + errorText;
            return res;
        }

        finalizeIncident(incident.Id, 'Processed', totalCases, note);
        res.status = 'Processed';
        res.message = note;
        return res;
    }

    private static void finalizeIncident(Id incidentId, String status, Integer totalCases, String message) {
        Database.update(
            new List<Incident__c>{
                new Incident__c(
                    Id = incidentId,
                    Processing_Status__c = status,
                    Total_Cases__c = totalCases,
                    Error_Message__c = message
                )
            },
            false,
            AccessLevel.USER_MODE
        );
    }

    private static Case buildCase(Incident__c incident, Vehicle__c vehicle, Delivery__c d, String key, Id ownerId) {
        String detail = 'Incident ' + incident.Name + ' (' + incident.Type__c + ', severity ' + incident.Severity__c + ')'
            + '\nVehicle: ' + vehicle.Vehicle_Number__c
            + '\nDelivery: ' + d.Delivery_Number__c
            + (d.Destination__c == null ? '' : '\nDestination: ' + d.Destination__c)
            + (d.Expected_Date__c == null ? '' : '\nExpected delivery date: ' + d.Expected_Date__c.format())
            + (String.isBlank(incident.Description__c) ? '' : '\n\n' + incident.Description__c);

        Case c = new Case(
            AccountId = d.Account__c,
            Subject = ('Delivery ' + d.Delivery_Number__c + ' affected by ' + incident.Type__c + ' (' + incident.Name + ')').left(255),
            Description = detail.left(32000),
            Priority = PRIORITY_BY_SEVERITY.get(incident.Severity__c),
            Incident__c = incident.Id,
            Delivery__c = d.Id,
            Case_Key__c = key,
            Escalation_Deadline__c = System.now().addMinutes(DEADLINE_MINUTES.get(incident.Severity__c))
        );
        if (ownerId != null) {
            c.OwnerId = ownerId;
        }
        return c;
    }
}
