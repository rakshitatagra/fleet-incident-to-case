/**
 * Escalates overdue incident Cases. Runs hourly once scheduled:
 *   CaseEscalationJob.scheduleHourly();
 *
 * Idempotent: only Cases with Escalated__c = false are picked up, and the flag is set on escalation.
 * Closed Cases and Cases not linked to an incident are ignored.
 */
public with sharing class CaseEscalationJob implements Database.Batchable<SObject>, Schedulable {

    public static final String JOB_NAME = 'Fleet Case Escalation (hourly)';
    public static final String ESCALATION_QUEUE = 'Fleet_Escalation_Queue';

    /** Safe to call repeatedly: does nothing if the job is already scheduled. */
    public static void scheduleHourly() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME
        ];
        if (existing.isEmpty()) {
            System.schedule(JOB_NAME, '0 0 * * * ?', new CaseEscalationJob());
        }
    }

    // Schedulable
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CaseEscalationJob(), 200);
    }

    // Batchable
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime nowTs = System.now();
        return Database.getQueryLocator([
            SELECT Id, OwnerId
            FROM Case
            WHERE Incident__c != null
              AND IsClosed = false
              AND Escalated__c = false
              AND Escalation_Deadline__c != null
              AND Escalation_Deadline__c <= :nowTs
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Case> cases = (List<Case>) scope;
        Id queueId = IncidentSelector.caseQueueId(ESCALATION_QUEUE);

        List<Case> updates = new List<Case>();
        for (Case c : cases) {
            updates.add(new Case(
                Id = c.Id,
                Escalated__c = true,
                Priority = 'High',
                Status = 'Escalated',
                OwnerId = queueId != null ? queueId : c.OwnerId
            ));
        }

        List<Database.SaveResult> results = Database.update(updates, false, AccessLevel.USER_MODE);

        // Task owners must be users (not queues). In a real org, assign this to the support manager.
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                tasks.add(new Task(
                    Subject = 'Escalated: customer follow-up is overdue',
                    WhatId = updates[i].Id,
                    OwnerId = UserInfo.getUserId(),
                    ActivityDate = Date.today(),
                    Priority = 'High',
                    Status = 'Not Started'
                ));
            } else {
                System.debug(LoggingLevel.ERROR, 'Escalation failed for Case ' + updates[i].Id + ': '
                    + results[i].getErrors()[0].getMessage());
            }
        }
        if (!tasks.isEmpty()) {
            Database.insert(tasks, false, AccessLevel.USER_MODE);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}
