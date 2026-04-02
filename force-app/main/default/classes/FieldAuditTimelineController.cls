public with sharing class FieldAuditTimelineController {

    private static Map<String, Schema.SObjectType> cachedGlobalDescribe;

    private static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (cachedGlobalDescribe == null) {
            cachedGlobalDescribe = Schema.getGlobalDescribe();
        }
        return cachedGlobalDescribe;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFieldHistory(
        String objectApiName,
        Id recordId,
        String trackedFields,
        Integer auditWindowDays,
        Integer maxRows
    ) {
        Map<String, Schema.SObjectType> globalDescribe = getGlobalDescribe();
        validateObjectApiName(objectApiName, globalDescribe);

        List<String> fieldList = parseTrackedFields(trackedFields, objectApiName, globalDescribe);
        List<SObject> historyRecords = queryHistory(
            objectApiName, recordId, fieldList, auditWindowDays, maxRows, globalDescribe
        );

        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectApiName.toLowerCase())
            .getDescribe().fields.getMap();

        return buildEntries(historyRecords, fieldMap);
    }

    @AuraEnabled(cacheable=true)
    public static String getRecordName(String objectApiName, Id recordId) {
        Map<String, Schema.SObjectType> globalDescribe = getGlobalDescribe();
        validateObjectApiName(objectApiName, globalDescribe);

        String query = 'SELECT Name FROM ' + objectApiName
            + ' WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1';

        List<SObject> records = Database.query(query);
        return records.isEmpty() ? '' : (String) records[0].get('Name');
    }

    // --- Validation ---

    private static void validateObjectApiName(String objectApiName, Map<String, Schema.SObjectType> globalDescribe) {
        if (!globalDescribe.containsKey(objectApiName.toLowerCase())) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
    }

    private static List<String> parseTrackedFields(
        String trackedFields, String objectApiName, Map<String, Schema.SObjectType> globalDescribe
    ) {
        List<String> fieldList = new List<String>();
        if (String.isBlank(trackedFields)) {
            return fieldList;
        }

        Map<String, Schema.SObjectField> objFields = globalDescribe.get(objectApiName.toLowerCase())
            .getDescribe().fields.getMap();

        for (String f : trackedFields.split(',')) {
            String trimmed = f.trim();
            if (String.isNotBlank(trimmed) && objFields.containsKey(trimmed.toLowerCase())) {
                fieldList.add(trimmed);
            }
        }

        if (fieldList.isEmpty()) {
            throw new AuraHandledException(
                'None of the configured tracked fields exist on ' + objectApiName + ': ' + trackedFields
            );
        }
        return fieldList;
    }

    // --- Query ---

    private static List<SObject> queryHistory(
        String objectApiName, Id recordId, List<String> fieldList,
        Integer auditWindowDays, Integer maxRows, Map<String, Schema.SObjectType> globalDescribe
    ) {
        String historyObjectName = resolveHistoryObject(objectApiName, globalDescribe);
        String parentIdField = resolveParentIdField(historyObjectName, globalDescribe);
        Datetime windowStart = Datetime.now().addDays(-auditWindowDays);

        String query = 'SELECT Id, Field, OldValue, NewValue, CreatedById, CreatedBy.Name, CreatedDate'
            + ' FROM ' + historyObjectName
            + ' WHERE ' + parentIdField + ' = :recordId'
            + ' AND CreatedDate >= :windowStart';

        if (!fieldList.isEmpty()) {
            query += ' AND Field IN :fieldList';
        }

        query += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT :maxRows';
        return Database.query(query);
    }

    private static String resolveHistoryObject(String objectApiName, Map<String, Schema.SObjectType> globalDescribe) {
        if (objectApiName.endsWithIgnoreCase('__c')) {
            String customHistory = objectApiName.removeEndIgnoreCase('__c') + '__History';
            if (globalDescribe.containsKey(customHistory.toLowerCase())) {
                return customHistory;
            }
            throw new AuraHandledException('History tracking is not enabled for: ' + objectApiName);
        }

        String fieldHistoryName = objectApiName + 'FieldHistory';
        if (globalDescribe.containsKey(fieldHistoryName.toLowerCase())) {
            return fieldHistoryName;
        }

        String historyName = objectApiName + 'History';
        if (globalDescribe.containsKey(historyName.toLowerCase())) {
            Map<String, Schema.SObjectField> histFields = globalDescribe.get(historyName.toLowerCase())
                .getDescribe().fields.getMap();
            if (histFields.containsKey('field')) {
                return historyName;
            }
        }

        throw new AuraHandledException('History tracking is not enabled for: ' + objectApiName);
    }

    private static String resolveParentIdField(String historyObjectName, Map<String, Schema.SObjectType> globalDescribe) {
        if (historyObjectName.endsWithIgnoreCase('__History')) {
            return 'ParentId';
        }

        Schema.SObjectType histType = globalDescribe.get(historyObjectName.toLowerCase());
        Map<String, Schema.SObjectField> histFields = histType.getDescribe().fields.getMap();

        for (String fieldName : histFields.keySet()) {
            Schema.DescribeFieldResult dfr = histFields.get(fieldName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && fieldName != 'createdbyid') {
                return dfr.getName();
            }
        }

        return 'ParentId';
    }

    // --- Result building ---

    private static List<Map<String, Object>> buildEntries(
        List<SObject> historyRecords, Map<String, Schema.SObjectField> fieldMap
    ) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        for (SObject rec : historyRecords) {
            Object oldValue = rec.get('OldValue');
            Object newValue = rec.get('NewValue');

            // Skip duplicate lookup entries that show raw IDs instead of names
            if (looksLikeSalesforceId(oldValue) || looksLikeSalesforceId(newValue)) {
                continue;
            }

            results.add(mapEntry(rec, oldValue, newValue, fieldMap));
        }

        return results;
    }

    private static Map<String, Object> mapEntry(
        SObject rec, Object oldValue, Object newValue, Map<String, Schema.SObjectField> fieldMap
    ) {
        String fieldName = (String) rec.get('Field');
        Datetime createdDate = (Datetime) rec.get('CreatedDate');
        String createdByName = (String) rec.getSObject('CreatedBy').get('Name');

        return new Map<String, Object>{
            'id' => (String) rec.get('Id'),
            'field' => fieldName,
            'fieldLabel' => resolveFieldLabel(fieldName, fieldMap),
            'oldValue' => oldValue != null ? String.valueOf(oldValue) : null,
            'newValue' => newValue != null ? String.valueOf(newValue) : null,
            'changedById' => (String) rec.get('CreatedById'),
            'changedByName' => createdByName,
            'changedByInitials' => computeInitials(createdByName),
            'createdDate' => createdDate.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
            'formattedDate' => createdDate.format('dd MMM yyyy'),
            'changeType' => classifyChangeType(fieldName, oldValue, newValue)
        };
    }

    private static String resolveFieldLabel(String fieldName, Map<String, Schema.SObjectField> fieldMap) {
        String key = fieldName.toLowerCase();
        if (fieldMap.containsKey(key) && fieldMap.get(key).getDescribe().isAccessible()) {
            return fieldMap.get(key).getDescribe().getLabel();
        }
        return fieldName;
    }

    // --- Helpers ---

    private static String computeInitials(String fullName) {
        if (String.isBlank(fullName)) {
            return '??';
        }
        List<String> parts = fullName.trim().split('\\s+');
        if (parts.size() >= 2) {
            return (parts[0].substring(0, 1) + parts[parts.size() - 1].substring(0, 1)).toUpperCase();
        }
        return fullName.length() >= 2
            ? fullName.substring(0, 2).toUpperCase()
            : fullName.toUpperCase();
    }

    private static Boolean looksLikeSalesforceId(Object value) {
        if (value == null) {
            return false;
        }
        String str = String.valueOf(value);
        return (str.length() == 15 || str.length() == 18) && Pattern.matches('[a-zA-Z0-9]{15,18}', str);
    }

    private static String classifyChangeType(String fieldName, Object oldValue, Object newValue) {
        if ('StageName'.equals(fieldName)) {
            return 'stage';
        }
        if ('OwnerId'.equals(fieldName)) {
            return 'owner';
        }
        if (newValue == null && oldValue != null) {
            return 'delete';
        }
        return 'value';
    }
}
