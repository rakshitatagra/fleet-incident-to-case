@IsTest
private class CaseEscalationJobTest {

    private static Case newCase(Id incidentId, String subject, Datetime deadline) {
        return new Case(
            Subject = subject,
            Incident__c = incidentId,
            Case_Key__c = 'K-' + subject,
            Escalation_Deadline__c = deadline
        );
    }

    @IsTest
    static void overdueOpenCasesAreEscalatedExactlyOnce() {
        Incident__c inc = TestDataFactory.createIncident('INC-E1', 'Low');

        Case overdue = newCase(inc.Id, 'overdue', System.now().addHours(-2));
        Case notDue = newCase(inc.Id, 'notdue', System.now().addHours(5));
        Case closedOverdue = newCase(inc.Id, 'closed', System.now().addHours(-2));
        closedOverdue.Status = 'Closed';
        Case unlinked = new Case(Subject = 'unlinked', Escalation_Deadline__c = System.now().addHours(-2));
        insert new List<Case>{ overdue, notDue, closedOverdue, unlinked };

        Test.startTest();
        Database.executeBatch(new CaseEscalationJob(), 200);
        Test.stopTest();

        Case escalated = [SELECT Escalated__c, Priority, Status FROM Case WHERE Id = :overdue.Id];
        Assert.isTrue(escalated.Escalated__c);
        Assert.areEqual('High', escalated.Priority);
        Assert.areEqual('Escalated', escalated.Status);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :overdue.Id]);

        Assert.isFalse([SELECT Escalated__c FROM Case WHERE Id = :notDue.Id].Escalated__c, 'Not yet due');
        Assert.isFalse([SELECT Escalated__c FROM Case WHERE Id = :closedOverdue.Id].Escalated__c, 'Closed cases are ignored');
        Assert.isFalse([SELECT Escalated__c FROM Case WHERE Id = :unlinked.Id].Escalated__c, 'Non-incident cases are ignored');
    }

    @IsTest
    static void alreadyEscalatedCasesAreNotEscalatedAgain() {
        Incident__c inc = TestDataFactory.createIncident('INC-E2', 'Low');
        Case done = newCase(inc.Id, 'done', System.now().addHours(-3));
        done.Escalated__c = true;
        done.Priority = 'Medium';
        insert done;

        Test.startTest();
        Database.executeBatch(new CaseEscalationJob(), 200);
        Test.stopTest();

        Assert.areEqual('Medium', [SELECT Priority FROM Case WHERE Id = :done.Id].Priority, 'Must not be touched again');
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :done.Id], 'No second escalation task');
    }

    @IsTest
    static void schedulingTwiceCreatesOnlyOneScheduledJob() {
        Test.startTest();
        CaseEscalationJob.scheduleHourly();
        CaseEscalationJob.scheduleHourly();
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :CaseEscalationJob.JOB_NAME]);
    }
}
