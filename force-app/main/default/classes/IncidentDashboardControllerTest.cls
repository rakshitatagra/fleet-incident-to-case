@IsTest
private class IncidentDashboardControllerTest {

    @TestSetup
    static void setup() {
        Incident__c inc = TestDataFactory.createIncident('INC-D1', 'High');
        insert new Case(Subject = 'Open one', Incident__c = inc.Id, Case_Key__c = 'INC-D1-D-1',
                        Escalation_Deadline__c = System.now().addHours(4));
        insert new Case(Subject = 'Closed one', Incident__c = inc.Id, Case_Key__c = 'INC-D1-D-2',
                        Status = 'Closed');
        Incident__c failed = TestDataFactory.createIncident('INC-D2', 'Low');
        failed.Processing_Status__c = 'Failed';
        update failed;
    }

    @IsTest
    static void summaryCountsOnlyOpenIncidentCasesAndFailures() {
        IncidentDashboardController.Summary s = IncidentDashboardController.getSummary();
        Assert.areEqual(1, s.openIncidents);
        Assert.areEqual(1, s.openCases);
        Assert.areEqual(0, s.overdueTasks);
        Assert.areEqual(1, s.failedIncidents);
    }

    @IsTest
    static void incidentListSupportsSeverityFilter() {
        Assert.areEqual(2, IncidentDashboardController.getRecentIncidents(null).size());
        Assert.areEqual(2, IncidentDashboardController.getRecentIncidents('').size());

        List<IncidentDashboardController.IncidentRow> high = IncidentDashboardController.getRecentIncidents('High');
        Assert.areEqual(1, high.size());
        Assert.areEqual('INC-D1', high[0].name);
        Assert.areEqual(0, IncidentDashboardController.getRecentIncidents('Critical').size());
    }

    @IsTest
    static void casesForIncidentAreReturned() {
        Id incidentId = [SELECT Id FROM Incident__c WHERE Name = 'INC-D1'].Id;
        List<IncidentDashboardController.CaseRow> rows = IncidentDashboardController.getCasesForIncident(incidentId);
        Assert.areEqual(2, rows.size());
        Assert.areEqual('Open one', rows[0].subject);
    }
}
