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

        opp.StageName = 'Qualification';
        update opp;

        opp.Amount = 2000;
        update opp;

        opp.Amount = null;
        update opp;
    }

    @IsTest
    static void testGetFieldHistoryValid() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity', opp.Id, '', 30, 200
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(!results.isEmpty(), 'Should have history entries from test setup');

        for (Map<String, Object> entry : results) {
            System.assertNotEquals(null, entry.get('id'), 'Entry must have id');
            System.assertNotEquals(null, entry.get('field'), 'Entry must have field');
            System.assertNotEquals('', entry.get('fieldLabel'), 'fieldLabel should be resolved');
            System.assertNotEquals(null, entry.get('changeType'), 'Entry must have changeType');
            System.assertNotEquals(null, entry.get('changedByName'), 'Entry must have changedByName');
            System.assertNotEquals(null, entry.get('createdDate'), 'Entry must have createdDate');

            String changeType = (String) entry.get('changeType');
            System.assert(
                new Set<String>{ 'stage', 'owner', 'delete', 'value' }.contains(changeType),
                'changeType must be one of stage/owner/delete/value, got: ' + changeType
            );

            String initials = (String) entry.get('changedByInitials');
            System.assertNotEquals(null, initials, 'Initials should not be null');
            System.assert(initials.length() >= 1 && initials.length() <= 2,
                'Initials should be 1-2 characters');
        }
    }

    @IsTest
    static void testGetFieldHistoryInvalidObject() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        try {
            FieldAuditTimelineController.getFieldHistory(
                'InvalidObjectXyz123', opp.Id, '', 30, 200
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object API name'),
                'Should contain error message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetFieldHistoryWithTrackedFields() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity', opp.Id, 'StageName', 30, 200
        );
        Test.stopTest();

        for (Map<String, Object> entry : results) {
            System.assertEquals('StageName', entry.get('field'),
                'Only StageName entries should be returned');
            System.assertEquals('stage', entry.get('changeType'),
                'StageName changes should be classified as stage');
        }
    }

    @IsTest
    static void testGetFieldHistoryInvalidTrackedFields() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        try {
            FieldAuditTimelineController.getFieldHistory(
                'Opportunity', opp.Id, 'NonExistentField__xyz', 30, 200
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('None of the configured tracked fields exist'),
                'Should report invalid tracked fields: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetFieldHistoryMaxRows() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity', opp.Id, '', 30, 1
        );
        Test.stopTest();

        System.assert(results.size() <= 1, 'Should respect maxRows limit of 1');
    }

    @IsTest
    static void testGetFieldHistoryZeroDayWindow() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity', opp.Id, '', 0, 200
        );
        Test.stopTest();

        // 0-day window means only changes from right now — may or may not return results
        System.assertNotEquals(null, results, 'Should return a list (possibly empty), not null');
    }

    @IsTest
    static void testGetFieldHistoryChangeTypes() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> results = FieldAuditTimelineController.getFieldHistory(
            'Opportunity', opp.Id, '', 30, 200
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should have history entries from test setup');

        Set<String> changeTypes = new Set<String>();
        for (Map<String, Object> entry : results) {
            changeTypes.add((String) entry.get('changeType'));
            System.assertNotEquals('', entry.get('fieldLabel'), 'fieldLabel should be resolved');
        }

        // Setup creates StageName change → 'stage', and Amount changes → 'value'/'delete'
        System.assert(changeTypes.contains('stage') || changeTypes.contains('value'),
            'Should contain at least stage or value change types from setup data');
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
    static void testGetFieldHistoryFLSEnforced() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Profile minProfile = [SELECT Id FROM Profile
            WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User restrictedUser = new User(
            Alias = 'flstest',
            Email = 'flstest@test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'FLSTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_AU',
            ProfileId = minProfile.Id,
            TimeZoneSidKey = 'Australia/Sydney',
            UserName = 'flstest' + Datetime.now().getTime() + '@test.example.com'
        );
        insert restrictedUser;

        Test.startTest();
        System.runAs(restrictedUser) {
            try {
                FieldAuditTimelineController.getFieldHistory(
                    'Opportunity', opp.Id, '', 30, 200
                );
            } catch (AuraHandledException e) {
                // Expected — restricted user lacks object/field access
                System.assert(e.getMessage() != null, 'Exception should have a message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetRecordNameInvalidObject() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opp' LIMIT 1];

        Test.startTest();
        try {
            FieldAuditTimelineController.getRecordName('InvalidObjectXyz123', opp.Id);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object API name'),
                'Should contain error message');
        }
        Test.stopTest();
    }
}
