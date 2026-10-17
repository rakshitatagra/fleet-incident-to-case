/**
 * Shape of the JSON an external fleet system must send, plus validation.
 * All input problems are collected and reported together as a ValidationException (HTTP 400).
 */
public with sharing class IncidentRequest {

    public class ValidationException extends Exception {}

    // JSON fields
    public String incidentId;
    public String vehicleNumber;
    public String type;
    public String severity;
    public String description;
    public String reportedAt;

    // Filled in by validate()
    public Datetime reportedAtParsed;

    private static final Integer MAX_ID_LENGTH = 80;
    private static final Integer MAX_DESCRIPTION_LENGTH = 5000;

    // lower-case input -> canonical picklist value
    private static final Map<String, String> TYPES = new Map<String, String>{
        'breakdown' => 'Breakdown',
        'delay' => 'Delay',
        'accident' => 'Accident'
    };
    private static final Map<String, String> SEVERITIES = new Map<String, String>{
        'low' => 'Low',
        'medium' => 'Medium',
        'high' => 'High',
        'critical' => 'Critical'
    };

    public static IncidentRequest parse(Blob body) {
        if (body == null || body.size() == 0) {
            throw new ValidationException('Request body is empty.');
        }
        IncidentRequest req;
        try {
            req = (IncidentRequest) JSON.deserialize(body.toString(), IncidentRequest.class);
        } catch (Exception e) {
            throw new ValidationException('Malformed JSON: ' + e.getMessage());
        }
        if (req == null) {
            throw new ValidationException('Request body must be a JSON object.');
        }
        req.validate();
        return req;
    }

    private void validate() {
        List<String> problems = new List<String>();

        incidentId = clean(incidentId);
        vehicleNumber = clean(vehicleNumber);
        if (vehicleNumber != null) {
            vehicleNumber = vehicleNumber.toUpperCase();
        }

        if (String.isBlank(incidentId)) {
            problems.add('incidentId is required');
        } else if (incidentId.length() > MAX_ID_LENGTH) {
            problems.add('incidentId must be at most ' + MAX_ID_LENGTH + ' characters');
        }

        if (String.isBlank(vehicleNumber)) {
            problems.add('vehicleNumber is required');
        } else if (vehicleNumber.length() > MAX_ID_LENGTH) {
            problems.add('vehicleNumber must be at most ' + MAX_ID_LENGTH + ' characters');
        }

        if (String.isBlank(type)) {
            problems.add('type is required');
        } else if (TYPES.containsKey(type.trim().toLowerCase())) {
            type = TYPES.get(type.trim().toLowerCase());
        } else {
            problems.add('type must be one of ' + String.join(TYPES.values(), ', '));
        }

        if (String.isBlank(severity)) {
            problems.add('severity is required');
        } else if (SEVERITIES.containsKey(severity.trim().toLowerCase())) {
            severity = SEVERITIES.get(severity.trim().toLowerCase());
        } else {
            problems.add('severity must be one of ' + String.join(SEVERITIES.values(), ', '));
        }

        if (String.isBlank(reportedAt)) {
            problems.add('reportedAt is required');
        } else {
            try {
                reportedAtParsed = (Datetime) JSON.deserialize(JSON.serialize(reportedAt.trim()), Datetime.class);
            } catch (Exception e) {
                problems.add('reportedAt must be ISO 8601, for example 2026-11-02T10:05:00Z');
            }
        }

        if (description != null && description.length() > MAX_DESCRIPTION_LENGTH) {
            description = description.left(MAX_DESCRIPTION_LENGTH);
        }

        if (!problems.isEmpty()) {
            throw new ValidationException(String.join(problems, '; '));
        }
    }

    private static String clean(String value) {
        return value == null ? null : value.trim();
    }
}
