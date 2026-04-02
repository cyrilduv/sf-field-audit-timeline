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

        if (!globalDescribe.containsKey(objectApiName.toLowerCase())) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }

        String historyObjectName = resolveHistoryObject(objectApiName, globalDescribe);
        String parentIdField = resolveParentIdField(historyObjectName, globalDescribe);
        Datetime windowStart = Datetime.now().addDays(-auditWindowDays);

        List<String> fieldList = new List<String>();
        if (String.isNotBlank(trackedFields)) {
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
        }

        String query = 'SELECT Id, Field, OldValue, NewValue, CreatedById, CreatedBy.Name, CreatedDate'
            + ' FROM ' + historyObjectName
            + ' WHERE ' + parentIdField + ' = :recordId'
            + ' AND CreatedDate >= :windowStart';

        if (!fieldList.isEmpty()) {
            query += ' AND Field IN :fieldList';
        }

        query += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT :maxRows';

        List<SObject> historyRecords = Database.query(query);

        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectApiName.toLowerCase())
            .getDescribe().fields.getMap();

        List<Map<String, Object>> results = new List<Map<String, Object>>();

        for (SObject rec : historyRecords) {
            String fieldName = (String) rec.get('Field');
            Object oldValue = rec.get('OldValue');
            Object newValue = rec.get('NewValue');

            // Skip duplicate lookup entries that show raw IDs instead of names
            if (looksLikeSalesforceId(oldValue) || looksLikeSalesforceId(newValue)) {
                continue;
            }

            Datetime createdDate = (Datetime) rec.get('CreatedDate');
            String createdByName = (String) rec.getSObject('CreatedBy').get('Name');

            String fieldLabel = fieldName;
            String fieldNameLower = fieldName.toLowerCase();
            if (fieldMap.containsKey(fieldNameLower)
                    && fieldMap.get(fieldNameLower).getDescribe().isAccessible()) {
                fieldLabel = fieldMap.get(fieldNameLower).getDescribe().getLabel();
            }

            Map<String, Object> entry = new Map<String, Object>{
                'id' => (String) rec.get('Id'),
                'field' => fieldName,
                'fieldLabel' => fieldLabel,
                'oldValue' => oldValue != null ? String.valueOf(oldValue) : null,
                'newValue' => newValue != null ? String.valueOf(newValue) : null,
                'changedById' => (String) rec.get('CreatedById'),
                'changedByName' => createdByName,
                'changedByInitials' => computeInitials(createdByName),
                'createdDate' => createdDate.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                'formattedDate' => createdDate.format('dd MMM yyyy'),
                'changeType' => classifyChangeType(fieldName, oldValue, newValue)
            };

            results.add(entry);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static String getRecordName(String objectApiName, Id recordId) {
        Map<String, Schema.SObjectType> globalDescribe = getGlobalDescribe();

        if (!globalDescribe.containsKey(objectApiName.toLowerCase())) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }

        String query = 'SELECT Name FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1';

        List<SObject> records = Database.query(query);
        return records.isEmpty() ? '' : (String) records[0].get('Name');
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
        if (value == null) return false;
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
