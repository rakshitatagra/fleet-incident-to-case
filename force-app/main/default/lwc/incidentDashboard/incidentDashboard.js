import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSummary from '@salesforce/apex/IncidentDashboardController.getSummary';
import getRecentIncidents from '@salesforce/apex/IncidentDashboardController.getRecentIncidents';
import getCasesForIncident from '@salesforce/apex/IncidentDashboardController.getCasesForIncident';

const DATE_FORMAT = {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
};

const INCIDENT_COLUMNS = [
    { label: 'Incident', fieldName: 'name' },
    { label: 'Vehicle', fieldName: 'vehicle' },
    { label: 'Type', fieldName: 'type' },
    { label: 'Severity', fieldName: 'severity' },
    { label: 'Status', fieldName: 'status' },
    { label: 'Cases', fieldName: 'totalCases', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Reported', fieldName: 'reportedAt', type: 'date', typeAttributes: DATE_FORMAT },
    { type: 'button', typeAttributes: { label: 'View cases', name: 'view', variant: 'base' } }
];

const CASE_COLUMNS = [
    { label: 'Case', fieldName: 'caseNumber' },
    { label: 'Subject', fieldName: 'subject' },
    { label: 'Customer', fieldName: 'account' },
    { label: 'Status', fieldName: 'status' },
    { label: 'Priority', fieldName: 'priority' },
    { label: 'Escalated', fieldName: 'escalated', type: 'boolean' },
    { label: 'Deadline', fieldName: 'deadline', type: 'date', typeAttributes: DATE_FORMAT }
];

const SEVERITY_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'Critical', value: 'Critical' },
    { label: 'High', value: 'High' },
    { label: 'Medium', value: 'Medium' },
    { label: 'Low', value: 'Low' }
];

function reduceError(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Unknown error';
}

export default class IncidentDashboard extends LightningElement {
    incidentColumns = INCIDENT_COLUMNS;
    caseColumns = CASE_COLUMNS;
    severityOptions = SEVERITY_OPTIONS;

    severity = '';
    summary;
    incidents = [];
    cases = [];
    selectedIncident;
    selectedIncidentId;
    errorMessage;
    loading = true;

    wiredSummaryResult;
    wiredIncidentsResult;

    @wire(getSummary)
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.summary = result.data;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.errorMessage = reduceError(result.error);
        }
    }

    @wire(getRecentIncidents, { severity: '$severity' })
    wiredIncidents(result) {
        this.wiredIncidentsResult = result;
        this.loading = false;
        if (result.data) {
            this.incidents = result.data;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.incidents = [];
            this.errorMessage = reduceError(result.error);
        }
    }

    get tiles() {
        const s = this.summary || {};
        return [
            { label: 'Open incidents', value: s.openIncidents ?? '-' },
            { label: 'Open cases', value: s.openCases ?? '-' },
            { label: 'Overdue tasks', value: s.overdueTasks ?? '-' },
            { label: 'Failed incidents', value: s.failedIncidents ?? '-' }
        ];
    }

    get hasIncidents() {
        return this.incidents && this.incidents.length > 0;
    }

    get hasCases() {
        return this.cases && this.cases.length > 0;
    }

    handleSeverityChange(event) {
        this.severity = event.detail.value;
        this.loading = true;
        this.clearSelection();
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view') {
            this.selectedIncident = event.detail.row.name;
            this.selectedIncidentId = event.detail.row.id;
            this.loadCases();
        }
    }

    async handleRefresh() {
        this.loading = true;
        try {
            await Promise.all([refreshApex(this.wiredSummaryResult), refreshApex(this.wiredIncidentsResult)]);
            if (this.selectedIncidentId) {
                await this.loadCases();
            }
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.loading = false;
        }
    }

    async loadCases() {
        try {
            this.cases = await getCasesForIncident({ incidentId: this.selectedIncidentId });
            this.errorMessage = undefined;
        } catch (error) {
            this.cases = [];
            this.errorMessage = reduceError(error);
        }
    }

    clearSelection() {
        this.selectedIncident = undefined;
        this.selectedIncidentId = undefined;
        this.cases = [];
    }
}
