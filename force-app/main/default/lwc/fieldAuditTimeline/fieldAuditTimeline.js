import { LightningElement, api, wire } from 'lwc';
import getFieldHistory from '@salesforce/apex/FieldAuditTimelineController.getFieldHistory';
import getRecordName from '@salesforce/apex/FieldAuditTimelineController.getRecordName';

const CHANGE_TYPE_CONFIG = {
    stage: { border: '#10B981', iconBg: '#D1FAE5', symbol: '\u25B6' },
    owner: { border: '#F59E0B', iconBg: '#FEF3C7', symbol: '\u21C4' },
    delete: { border: '#EF4444', iconBg: '#FEE2E2', symbol: '\u2715' },
    value: { border: '#3B82F6', iconBg: '#DBEAFE', symbol: '\u270E' }
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export default class FieldAuditTimeline extends LightningElement {
    @api title = 'Field Audit Timeline';
    @api objectApiName = '';
    @api trackedFields = '';
    @api auditWindowDays = 30;
    @api enableExport = false;
    @api enableSearch = false;
    @api maxRows = 200;
    @api recordId;

    allEntries = [];
    filteredEntries = [];
    searchTerm = '';
    fieldFilter = '';
    isLoading = true;
    error = null;
    recordName = '';

    _searchTimeout;
    _cachedGrouped = null;
    _cachedFieldOptions = null;
    _filteredVersion = 0;
    _allEntriesVersion = 0;
    _lastGroupedVersion = -1;
    _lastFieldOptionsVersion = -1;

    @wire(getRecordName, {
        objectApiName: '$objectApiName',
        recordId: '$recordId'
    })
    wiredRecordName({ error, data }) {
        if (data) {
            this.recordName = data;
        } else if (error) {
            this.recordName = '';
        }
    }

    @wire(getFieldHistory, {
        objectApiName: '$objectApiName',
        recordId: '$recordId',
        trackedFields: '$trackedFields',
        auditWindowDays: '$auditWindowDays',
        maxRows: '$maxRows'
    })
    wiredHistory({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.allEntries = data.map(entry => ({ ...entry }));
            this._allEntriesVersion++;
            this.error = null;
            this.filterEntries();
        } else if (error) {
            this.error = error.body ? error.body.message : 'An error occurred loading audit data.';
            this.allEntries = [];
            this.filteredEntries = [];
        }
    }

    get showContent() {
        return !this.isLoading && !this.error;
    }

    get objectPillLabel() {
        const objName = this.objectApiName
            ? this.objectApiName.replace(/__c$/, '').replace(/_/g, ' ')
            : '';
        return this.recordName ? `${objName} \u00B7 ${this.recordName}` : objName;
    }

    get totalChanges() {
        return this.filteredEntries.length;
    }

    get fieldsTracked() {
        const fields = new Set(this.allEntries.map(e => e.field));
        return fields.size;
    }

    get usersInvolved() {
        const users = new Set(this.allEntries.map(e => e.changedById));
        return users.size;
    }

    get auditWindowLabel() {
        return `${this.auditWindowDays}d`;
    }

    get fieldOptions() {
        if (this._lastFieldOptionsVersion === this._allEntriesVersion) {
            return this._cachedFieldOptions;
        }
        const options = [{ label: 'All Fields', value: '' }];
        const seen = new Set();
        for (const e of this.allEntries) {
            const label = e.fieldLabel || e.field;
            if (!seen.has(label)) {
                seen.add(label);
                options.push({ label, value: label });
            }
        }
        this._cachedFieldOptions = options;
        this._lastFieldOptionsVersion = this._allEntriesVersion;
        return options;
    }

    get hasEntries() {
        return this.filteredEntries.length > 0;
    }

    get isEmpty() {
        return this.filteredEntries.length === 0;
    }

    get groupedEntries() {
        if (this._lastGroupedVersion === this._filteredVersion) {
            return this._cachedGrouped;
        }

        const groups = [];
        const groupMap = new Map();
        const now = new Date();
        const todayMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const yesterdayMs = todayMs - 86400000;

        for (const entry of this.filteredEntries) {
            const entryDate = new Date(entry.createdDate);
            const entryDayMs = new Date(entryDate.getFullYear(), entryDate.getMonth(), entryDate.getDate()).getTime();

            let dateLabel;
            if (entryDayMs === todayMs) {
                dateLabel = 'Today';
            } else if (entryDayMs === yesterdayMs) {
                dateLabel = 'Yesterday';
            } else {
                dateLabel = `${String(entryDate.getDate()).padStart(2, '0')} ${MONTHS[entryDate.getMonth()]}`;
            }

            if (!groupMap.has(dateLabel)) {
                const group = { dateLabel, entries: [] };
                groupMap.set(dateLabel, group);
                groups.push(group);
            }

            const config = CHANGE_TYPE_CONFIG[entry.changeType] || CHANGE_TYPE_CONFIG.value;
            const oldVal = entry.oldValue != null ? String(entry.oldValue) : '';
            const newVal = entry.newValue != null ? String(entry.newValue) : '';
            const hasOldValue = oldVal !== '';
            const hasNewValue = newVal !== '';
            const isCleared = !hasNewValue && hasOldValue;

            groupMap.get(dateLabel).entries.push({
                id: entry.id,
                fieldLabel: entry.fieldLabel || entry.field,
                formattedTime: `${String(entryDate.getHours()).padStart(2, '0')}:${String(entryDate.getMinutes()).padStart(2, '0')}`,
                oldValue: oldVal,
                newValue: newVal,
                hasOldValue,
                hasNewValue,
                isCleared,
                showArrow: hasOldValue && (hasNewValue || isCleared),
                changedByName: entry.changedByName || '',
                changedByInitials: entry.changedByInitials || '',
                changeType: entry.changeType,
                borderStyle: `border-left: 4px solid ${config.border};`,
                iconBgStyle: `background-color: ${config.iconBg};`,
                iconSymbol: config.symbol,
                tagStyle: `background-color: ${config.iconBg}; color: ${config.border};`
            });
        }

        this._cachedGrouped = groups;
        this._lastGroupedVersion = this._filteredVersion;
        return groups;
    }

    filterEntries() {
        let entries = this.allEntries;

        if (this.fieldFilter) {
            entries = entries.filter(e => (e.fieldLabel || e.field) === this.fieldFilter);
        }

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            entries = entries.filter(e => {
                return [e.field, e.fieldLabel, e.changedByName,
                    e.oldValue != null ? String(e.oldValue) : '',
                    e.newValue != null ? String(e.newValue) : ''
                ].join(' ').toLowerCase().includes(term);
            });
        }

        this.filteredEntries = entries;
        this._filteredVersion++;
    }

    handleSearchChange(event) {
        const value = event.target.value || '';
        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }
        this._searchTimeout = setTimeout(() => {
            this.searchTerm = value;
            this.filterEntries();
        }, 300);
    }

    handleFieldFilterChange(event) {
        this.fieldFilter = event.detail.value;
        this.filterEntries();
    }

    handleExportCsv() {
        if (!this.allEntries.length) return;

        const headers = ['Field', 'Old Value', 'New Value', 'Changed By', 'Date', 'Time', 'Change Type'];
        const rows = this.allEntries.map(entry => {
            const dt = new Date(entry.createdDate);
            return [
                this._csvEscape(entry.fieldLabel || entry.field),
                this._csvEscape(entry.oldValue != null ? String(entry.oldValue) : ''),
                this._csvEscape(entry.newValue != null ? String(entry.newValue) : ''),
                this._csvEscape(entry.changedByName || ''),
                dt.toISOString().split('T')[0],
                dt.toTimeString().split(' ')[0],
                entry.changeType
            ].join(',');
        });

        const csv = [headers.join(','), ...rows].join('\n');
        const today = new Date().toISOString().split('T')[0];

        const link = document.createElement('a');
        link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        link.target = '_blank';
        link.download = `${this.objectApiName}_audit_${today}.csv`;
        link.click();
    }

    _csvEscape(value) {
        if (value == null) return '';
        const str = String(value);
        if (str.includes(',') || str.includes('"') || str.includes('\n')) {
            return '"' + str.replace(/"/g, '""') + '"';
        }
        return str;
    }
}
