/**
 * Thin REST layer: parse, delegate, translate the outcome into an HTTP status. No business logic here.
 *
 * POST /services/apexrest/fleet/incidents
 *   200 processed (or no active deliveries)   400 invalid input
 *   404 unknown vehicle (incident saved as Failed)   409 concurrent duplicate   500 unexpected / partial failure
 */
@RestResource(urlMapping='/fleet/incidents/*')
global with sharing class IncidentRestService {

    @HttpPost
    global static void createIncident() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        IncidentService.Result result = new IncidentService.Result();
        try {
            IncidentRequest payload = IncidentRequest.parse(RestContext.request.requestBody);
            result = IncidentService.process(payload);
        } catch (IncidentRequest.ValidationException e) {
            result.statusCode = 400;
            result.status = 'Rejected';
            result.message = e.getMessage();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Incident endpoint error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            result.statusCode = 500;
            result.status = 'Error';
            result.message = 'Unexpected error: ' + e.getMessage();
        }

        res.statusCode = result.statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(result, true));
    }
}
