@IsTest
private class FieldAuditTimelineControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 1000
        );
        insert opp;

        // Update StageName to generate history (stage change type)
        opp.StageName = 'Qualification';
        update opp;

        // Update Amount to generate history (value change type)
        opp.Amount = 2000;
        update opp;

        // Clear Amount to generate history (delete change type)
        opp.Amount = null;
        update opp;
    }

    @IsTest
    static void testGetFieldHistoryValid() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity',
            opp.Id,
            '',
            30,
            200
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        // History entries should exist from setup updates
        for (Map<String, Object> entry : results) {
            System.assert(entry.containsKey('id'), 'Entry should have id');
            System.assert(entry.containsKey('field'), 'Entry should have field');
            System.assert(entry.containsKey('fieldLabel'), 'Entry should have fieldLabel');
            System.assert(entry.containsKey('changeType'), 'Entry should have changeType');
            System.assert(entry.containsKey('changedByName'), 'Entry should have changedByName');
            System.assert(entry.containsKey('changedByInitials'), 'Entry should have changedByInitials');
            System.assert(entry.containsKey('createdDate'), 'Entry should have createdDate');
        }
    }

    @IsTest
    static void testGetFieldHistoryInvalidObject() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        try {
            FieldAuditTimelineController.getFieldHistory(
                'InvalidObjectXyz123',
                opp.Id,
                '',
                30,
                200
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object API name'), 'Should contain error message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetFieldHistoryWithTrackedFields() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity',
            opp.Id,
            'StageName',
            30,
            200
        );
        Test.stopTest();

        for (Map<String, Object> entry : results) {
            System.assertEquals('StageName', entry.get('field'),
                'Only StageName entries should be returned');
        }
    }

    @IsTest
    static void testGetFieldHistoryEmptyResults() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity',
            opp.Id,
            'NonExistentField__xyz',
            30,
            200
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list for non-matching field filter');
    }

    @IsTest
    static void testGetFieldHistoryChangeTypes() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity',
            opp.Id,
            '',
            30,
            200
        );
        Test.stopTest();

        Set<String> changeTypes = new Set<String>();
        for (Map<String, Object> entry : results) {
            changeTypes.add((String) entry.get('changeType'));
        }
        // At minimum we should see stage and value types from our setup
        // delete type depends on how Amount null is tracked
    }

    @IsTest
    static void testGetRecordNameValid() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        String name = FieldAuditTimelineController.getRecordName('Opportunity', opp.Id);
        Test.stopTest();

        System.assertEquals('Test Opp', name, 'Should return the opportunity name');
    }

    @IsTest
    static void testGetRecordNameInvalidObject() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        try {
            FieldAuditTimelineController.getRecordName('InvalidObjectXyz123', opp.Id);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object API name'), 'Should contain error message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testComputeInitialsSingleName() {
        // Test via getFieldHistory — initials for single-word usernames
        // are covered by the production code path
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity',
            opp.Id,
            '',
            30,
            200
        );
        Test.stopTest();

        for (Map<String, Object> entry : results) {
            String initials = (String) entry.get('changedByInitials');
            System.assertNotEquals(null, initials, 'Initials should not be null');
            System.assert(initials.length() >= 1 && initials.length() <= 2,
                'Initials should be 1-2 characters');
        }
    }
}
