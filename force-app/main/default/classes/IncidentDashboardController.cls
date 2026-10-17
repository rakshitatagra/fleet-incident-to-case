/**
 * Read-only data for the incidentDashboard LWC. User-mode queries, so users only see what they may access.
 */
public with sharing class IncidentDashboardController {

    public class Summary {
        @AuraEnabled public Integer openIncidents;
        @AuraEnabled public Integer openCases;
        @AuraEnabled public Integer overdueTasks;
        @AuraEnabled public Integer failedIncidents;
    }

    public class IncidentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String vehicle;
        @AuraEnabled public String type;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal totalCases;
        @AuraEnabled public Datetime reportedAt;
    }

    public class CaseRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String account;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Boolean escalated;
        @AuraEnabled public Datetime deadline;
    }

    @AuraEnabled(cacheable=true)
    public static Summary getSummary() {
        try {
            Summary s = new Summary();
            List<AggregateResult> agg = [
                SELECT COUNT_DISTINCT(Incident__c) n
                FROM Case
                WHERE Incident__c != null AND IsClosed = false
                WITH USER_MODE
            ];
            s.openIncidents = Integer.valueOf(agg[0].get('n'));
            s.openCases = [
                SELECT COUNT() FROM Case
                WHERE Incident__c != null AND IsClosed = false
                WITH USER_MODE
            ];
            s.overdueTasks = [
                SELECT COUNT() FROM Task
                WHERE IsClosed = false
                  AND ActivityDate < TODAY
                  AND WhatId IN (SELECT Id FROM Case WHERE Incident__c != null)
                WITH USER_MODE
            ];
            s.failedIncidents = [
                SELECT COUNT() FROM Incident__c
                WHERE Processing_Status__c = 'Failed'
                WITH USER_MODE
            ];
            return s;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<IncidentRow> getRecentIncidents(String severity) {
        try {
            List<Incident__c> incidents = String.isBlank(severity)
                ? [
                    SELECT Id, Name, Vehicle__r.Name, Vehicle_Number_Raw__c, Type__c, Severity__c,
                           Processing_Status__c, Total_Cases__c, Reported_At__c
                    FROM Incident__c
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT 50
                ]
                : [
                    SELECT Id, Name, Vehicle__r.Name, Vehicle_Number_Raw__c, Type__c, Severity__c,
                           Processing_Status__c, Total_Cases__c, Reported_At__c
                    FROM Incident__c
                    WHERE Severity__c = :severity
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT 50
                ];

            List<IncidentRow> rows = new List<IncidentRow>();
            for (Incident__c i : incidents) {
                IncidentRow r = new IncidentRow();
                r.id = i.Id;
                r.name = i.Name;
                r.vehicle = i.Vehicle__r != null ? i.Vehicle__r.Name : i.Vehicle_Number_Raw__c;
                r.type = i.Type__c;
                r.severity = i.Severity__c;
                r.status = i.Processing_Status__c;
                r.totalCases = i.Total_Cases__c;
                r.reportedAt = i.Reported_At__c;
                rows.add(r);
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<CaseRow> getCasesForIncident(Id incidentId) {
        try {
            List<CaseRow> rows = new List<CaseRow>();
            for (Case c : [
                SELECT Id, CaseNumber, Subject, Account.Name, Status, Priority, Escalated__c, Escalation_Deadline__c
                FROM Case
                WHERE Incident__c = :incidentId
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                CaseRow r = new CaseRow();
                r.id = c.Id;
                r.caseNumber = c.CaseNumber;
                r.subject = c.Subject;
                r.account = c.Account != null ? c.Account.Name : null;
                r.status = c.Status;
                r.priority = c.Priority;
                r.escalated = c.Escalated__c;
                r.deadline = c.Escalation_Deadline__c;
                rows.add(r);
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
