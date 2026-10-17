@IsTest
private class IncidentServiceTest {

    @TestSetup
    static void setup() {
        Account acme = new Account(Name = 'Acme Retail');
        Account zenith = new Account(Name = 'Zenith Foods');
        insert new List<Account>{ acme, zenith };

        Vehicle__c truck12 = TestDataFactory.createVehicle('TRK-12');
        TestDataFactory.createVehicle('TRK-99'); // no deliveries

        insert new List<Delivery__c>{
            TestDataFactory.delivery('D-101', acme.Id, truck12.Id, 'In Transit'),
            TestDataFactory.delivery('D-102', zenith.Id, truck12.Id, 'Scheduled'),
            TestDataFactory.delivery('D-103', acme.Id, truck12.Id, 'Delivered'),
            TestDataFactory.delivery('D-104', acme.Id, truck12.Id, 'Cancelled')
        };
    }

    @IsTest
    static void validIncidentCreatesOneCasePerActiveDelivery() {
        RestResponse res = TestDataFactory.post(TestDataFactory.payload('INC-1', 'TRK-12', 'High'));
        Map<String, Object> body = TestDataFactory.bodyOf(res);

        Assert.areEqual(200, res.statusCode);
        Assert.areEqual('Processed', body.get('status'));
        Assert.areEqual(2, (Integer) body.get('casesCreated'), 'Delivered and Cancelled deliveries must be ignored');

        List<Case> cases = [
            SELECT Case_Key__c, Priority, Escalation_Deadline__c, Incident__c, Delivery__c, AccountId
            FROM Case ORDER BY Case_Key__c
        ];
        Assert.areEqual(2, cases.size());
        Assert.areEqual('INC-1-D-101', cases[0].Case_Key__c);
        Assert.areEqual('INC-1-D-102', cases[1].Case_Key__c);
        Assert.areEqual('High', cases[0].Priority);
        Assert.isNotNull(cases[0].AccountId);
        Assert.isTrue(cases[0].Escalation_Deadline__c > System.now(), 'Deadline must be in the future');

        Incident__c inc = [SELECT Processing_Status__c, Total_Cases__c, Type__c, Vehicle__c FROM Incident__c];
        Assert.areEqual('Processed', inc.Processing_Status__c);
        Assert.areEqual(2, inc.Total_Cases__c);
        Assert.isNotNull(inc.Vehicle__c);
    }

    @IsTest
    static void resendingSameIncidentCreatesNothingNew() {
        String payload = TestDataFactory.payload('INC-2', 'TRK-12', 'High');
        TestDataFactory.post(payload);
        RestResponse second = TestDataFactory.post(payload);
        Map<String, Object> body = TestDataFactory.bodyOf(second);

        Assert.areEqual(200, second.statusCode);
        Assert.areEqual(0, (Integer) body.get('casesCreated'));
        Assert.areEqual(2, (Integer) body.get('casesAlreadyExisting'));
        Assert.areEqual(1, [SELECT COUNT() FROM Incident__c]);
        Assert.areEqual(2, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void resendDoesNotReopenAClosedCase() {
        String payload = TestDataFactory.payload('INC-3', 'TRK-12', 'High');
        TestDataFactory.post(payload);

        Case worked = [SELECT Id FROM Case WHERE Case_Key__c = 'INC-3-D-101'];
        worked.Status = 'Closed';
        update worked;

        TestDataFactory.post(payload);

        Assert.areEqual('Closed', [SELECT Status FROM Case WHERE Id = :worked.Id].Status,
            'A re-sent event must not overwrite a Case an agent already closed');
    }

    @IsTest
    static void unknownVehicleReturns404AndSavesFailedIncident() {
        RestResponse res = TestDataFactory.post(TestDataFactory.payload('INC-4', 'TRK-404', 'High'));

        Assert.areEqual(404, res.statusCode);
        Incident__c inc = [SELECT Processing_Status__c, Error_Message__c, Vehicle__c FROM Incident__c];
        Assert.areEqual('Failed', inc.Processing_Status__c);
        Assert.isTrue(inc.Error_Message__c.contains('TRK-404'));
        Assert.isNull(inc.Vehicle__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void failedIncidentIsRecoveredByResendingAfterVehicleExists() {
        String payload = TestDataFactory.payload('INC-5', 'TRK-55', 'Medium');
        Assert.areEqual(404, TestDataFactory.post(payload).statusCode);

        Account acme = [SELECT Id FROM Account WHERE Name = 'Acme Retail'];
        Vehicle__c truck55 = TestDataFactory.createVehicle('TRK-55');
        insert TestDataFactory.delivery('D-555', acme.Id, truck55.Id, 'Scheduled');

        RestResponse retry = TestDataFactory.post(payload);
        Assert.areEqual(200, retry.statusCode);

        Incident__c inc = [SELECT Processing_Status__c, Error_Message__c, Vehicle__c, Total_Cases__c FROM Incident__c];
        Assert.areEqual(1, [SELECT COUNT() FROM Incident__c], 'Retry must update the same incident');
        Assert.areEqual('Processed', inc.Processing_Status__c);
        Assert.isNull(inc.Error_Message__c);
        Assert.areEqual(truck55.Id, inc.Vehicle__c);
        Assert.areEqual(1, inc.Total_Cases__c);
    }

    @IsTest
    static void vehicleWithNoActiveDeliveriesSavesIncidentWithZeroCases() {
        RestResponse res = TestDataFactory.post(TestDataFactory.payload('INC-6', 'TRK-99', 'Low'));

        Assert.areEqual(200, res.statusCode);
        Assert.areEqual('No Active Deliveries', TestDataFactory.bodyOf(res).get('status'));
        Assert.areEqual('No Active Deliveries', [SELECT Processing_Status__c FROM Incident__c].Processing_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void deliveryWithoutAccountIsSkippedNotFatal() {
        Account acme = [SELECT Id FROM Account WHERE Name = 'Acme Retail'];
        Vehicle__c truck = TestDataFactory.createVehicle('TRK-77');
        insert new List<Delivery__c>{
            TestDataFactory.delivery('D-701', acme.Id, truck.Id, 'Scheduled'),
            TestDataFactory.delivery('D-702', null, truck.Id, 'Scheduled')
        };

        RestResponse res = TestDataFactory.post(TestDataFactory.payload('INC-7', 'TRK-77', 'High'));
        Map<String, Object> body = TestDataFactory.bodyOf(res);

        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(1, (Integer) body.get('casesCreated'));
        Assert.areEqual(1, (Integer) body.get('deliveriesSkipped'));
        Assert.isTrue(((String) body.get('message')).contains('D-702'));
    }

    @IsTest
    static void inputIsNormalisedBeforeUse() {
        String payload = JSON.serialize(new Map<String, Object>{
            'incidentId' => '  INC-8  ',
            'vehicleNumber' => ' trk-12 ',
            'type' => 'breakdown',
            'severity' => 'CRITICAL',
            'reportedAt' => '2026-11-02T10:05:00Z'
        });
        RestResponse res = TestDataFactory.post(payload);

        Assert.areEqual(200, res.statusCode);
        Incident__c inc = [SELECT Name, Type__c, Severity__c FROM Incident__c];
        Assert.areEqual('INC-8', inc.Name);
        Assert.areEqual('Breakdown', inc.Type__c);
        Assert.areEqual('Critical', inc.Severity__c);

        Case c = [SELECT Priority, Escalation_Deadline__c FROM Case LIMIT 1];
        Assert.areEqual('High', c.Priority);
        Assert.isTrue(c.Escalation_Deadline__c <= System.now().addMinutes(61), 'Critical deadline is 60 minutes');
    }

    @IsTest
    static void invalidRequestsReturn400AndCreateNothing() {
        String tooLongId = 'X'.repeat(81);
        List<String> badBodies = new List<String>{
            '',
            '{not json',
            '[]',
            'null',
            '{}',
            JSON.serialize(new Map<String, Object>{ 'incidentId' => 'I-1', 'type' => 'Delay', 'severity' => 'High', 'reportedAt' => '2026-11-02T10:05:00Z' }),
            TestDataFactory.payload('I-2', 'TRK-12', 'Catastrophic'),
            TestDataFactory.payload(tooLongId, 'TRK-12', 'High'),
            TestDataFactory.payload('I-3', 'TRK-12', 'High').replace('2026-11-02T10:05:00Z', 'yesterday'),
            TestDataFactory.payload('I-4', 'TRK-12', 'High').replace('Breakdown', 'Explosion')
        };

        for (String body : badBodies) {
            RestResponse res = TestDataFactory.post(body);
            Assert.areEqual(400, res.statusCode, 'Expected 400 for body: ' + body);
            Assert.isNotNull(TestDataFactory.bodyOf(res).get('message'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Incident__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void largeVehicleLoadStaysWithinGovernorLimits() {
        Account acme = [SELECT Id FROM Account WHERE Name = 'Acme Retail'];
        Vehicle__c truck = TestDataFactory.createVehicle('TRK-BULK');
        List<Delivery__c> many = new List<Delivery__c>();
        for (Integer i = 0; i < 200; i++) {
            many.add(TestDataFactory.delivery('B-' + i, acme.Id, truck.Id, 'Scheduled'));
        }
        insert many;

        RestResponse res = TestDataFactory.post(TestDataFactory.payload('INC-BULK', 'TRK-BULK', 'High'));

        Assert.areEqual(200, res.statusCode);
        Assert.areEqual(200, (Integer) TestDataFactory.bodyOf(res).get('casesCreated'));
        Assert.areEqual(200, [SELECT COUNT() FROM Case WHERE Incident__r.Name = 'INC-BULK']);
    }
}
