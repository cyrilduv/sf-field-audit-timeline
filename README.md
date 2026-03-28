# Field Audit Timeline — Lightning Web Component

A field-level audit trail viewer for Salesforce record pages. Drop it onto any record page to visualise field history changes in a clean, colour-coded timeline.

<img width="967" height="632" alt="image" src="https://github.com/user-attachments/assets/93f6a560-aba9-4fb4-af04-4cfda2f94301" />


![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=flat&logo=salesforce&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)


---

## Features

- **Universal object support** — works on any standard or custom object with field history tracking enabled
- **Dynamic history resolution** — automatically detects the correct history object (`AccountHistory`, `OpportunityFieldHistory`, `MyObj__History`, etc.) and parent ID field
- **Colour-coded timeline entries** — stage changes (green), owner changes (amber), value deletions (red), and field edits (blue)
- **Date-grouped display** — entries grouped under "Today", "Yesterday", or "DD MMM" headers
- **Diff visualisation** — old values shown as red strikethrough pills, new values as green pills, cleared fields shown as italic "— cleared"
- **User attribution** — avatar initials and username on every entry
- **Field filter dropdown** — filter the timeline to a specific tracked field
- **Search bar** — full-text search across field names, values, and usernames (debounced 300ms)
- **CSV export** — export all audit entries (unfiltered) with one click
- **Summary statistics** — total changes, distinct fields, distinct users, and audit window at a glance
- **Fully configurable via App Builder** — all settings exposed as design-time properties
- **Security enforced** — all SOQL queries use `WITH SECURITY_ENFORCED`, object API names validated via Schema describe before any dynamic query

## Components

| File | Description |
|------|-------------|
| `force-app/main/default/lwc/fieldAuditTimeline/` | LWC bundle (HTML, JS, CSS, meta XML) |
| `force-app/main/default/classes/FieldAuditTimelineController.cls` | Apex controller with dynamic SOQL |
| `force-app/main/default/classes/FieldAuditTimelineControllerTest.cls` | Apex test class |
| `force-app/main/default/permissionsets/Field_Audit_Timeline_User.permissionset-meta.xml` | Permission set for component access |

## App Builder Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| Card Title | String | `Field Audit Timeline` | Title shown on the lightning card |
| Object API Name | String | *(required)* | API name of the object (e.g. `Opportunity`, `Account`, `My_Custom_Obj__c`) |
| Tracked Fields | String | *(blank = all)* | Comma-separated API names to filter (e.g. `StageName,Amount`) |
| Audit Window (days) | Integer | `30` | How far back to query history records |
| Max Rows | Integer | `200` | Maximum number of history records to return |
| Enable Search Bar | Boolean | `false` | Show the search input in the toolbar |
| Enable CSV Export | Boolean | `false` | Show the Export CSV button in the toolbar |

## Prerequisites

- Salesforce org with **Field History Tracking** enabled on the target object and fields
- Salesforce CLI (`sf`) installed for manual deployment
- API version 62.0+

## Installation

### Option 1 — One-click deploy

<a href="https://githubsfdeploy.herokuapp.com?owner=cyrilduv&repo=sf-field-audit-timeline&ref=main">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

### Option 2 — Salesforce CLI

```bash
git clone https://github.com/cyrilduv/sf-field-audit-timeline.git
cd sf-field-audit-timeline
sf project deploy start --source-dir force-app --target-org YOUR_ORG_ALIAS --wait 10
```

## Post-Installation Setup

After deploying, assign the **Field Audit Timeline User** permission set to any users who need access:

```bash
sf org assign permset --name Field_Audit_Timeline_User --target-org YOUR_ORG_ALIAS
```

Or via Setup: **Setup > Permission Sets > Field Audit Timeline User > Manage Assignments > Add Assignments**

This permission set grants access to the `FieldAuditTimelineController` Apex class. Without it, users will see an error when the component loads.

## Usage

1. Navigate to **Setup > Object Manager > [Your Object] > Fields & Relationships**
2. Ensure **Field History Tracking** is enabled and the desired fields are checked
3. Open the record page in **Lightning App Builder**
4. Drag the **Field Audit Timeline** component onto the page
5. Set the **Object API Name** to match the page object (e.g. `Opportunity`)
6. Optionally configure tracked fields, audit window, search, and export
7. Save and activate the page

## How It Works

### History Object Resolution

The Apex controller dynamically resolves the correct history object:

| Object Type | History Object | Parent ID Field |
|-------------|---------------|-----------------|
| Custom (`MyObj__c`) | `MyObj__History` | `ParentId` |
| Standard with FieldHistory (e.g. Opportunity) | `OpportunityFieldHistory` | `OpportunityId` |
| Standard with History (e.g. Account) | `AccountHistory` | `AccountId` |

The controller introspects the Schema to verify the history object exists and has the required `Field`, `OldValue`, `NewValue` columns before querying.

### Change Type Classification

| Type | Colour | Detection |
|------|--------|-----------|
| Stage | Green (`#10B981`) | Field is `StageName` |
| Owner | Amber (`#F59E0B`) | Field is `OwnerId` |
| Delete | Red (`#EF4444`) | New value is null, old value is not |
| Value | Blue (`#3B82F6`) | All other field changes |

## Project Structure

```
field-audit-timeline/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/
│           │   ├── FieldAuditTimelineController.cls
│           │   ├── FieldAuditTimelineController.cls-meta.xml
│           │   ├── FieldAuditTimelineControllerTest.cls
│           │   └── FieldAuditTimelineControllerTest.cls-meta.xml
│           ├── permissionsets/
│           │   └── Field_Audit_Timeline_User.permissionset-meta.xml
│           └── lwc/
│               └── fieldAuditTimeline/
│                   ├── fieldAuditTimeline.html
│                   ├── fieldAuditTimeline.js
│                   ├── fieldAuditTimeline.css
│                   └── fieldAuditTimeline.js-meta.xml
├── sfdx-project.json
└── README.md
```

## License

MIT
